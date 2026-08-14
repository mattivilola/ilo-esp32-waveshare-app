# Board protocol

The reference device implementation is the Waveshare ESP32-S3-Touch-LCD-5B (SKU 28151, 1024×600); the protocol itself remains independent of display dimensions.

Protocol version `1` uses a four-byte big-endian payload length followed by UTF-8 JSON. A frame is rejected when it is empty, larger than 65,536 bytes, malformed JSON, or uses an unsupported protocol version.

After the board parses and applies a `snapshot`, it returns `snapshotAck` with the same revision. The companion advances its user-visible board sync time only for a valid, increasing acknowledgement that does not exceed a revision it sent. A queued write is never presented as a successful board sync.

Application frames can use either of two authenticated transports. Wi-Fi is primary and uses TLS 1.2 with a unique 32-byte PSK per board; Bonjour advertises `_iloboard._tcp` and never carries credentials or private task data. When no authenticated Wi-Fi session exists, a physically attached paired ESP32-S3 may use the encrypted USB Serial/JTAG fallback described below. Wi-Fi preempts an active USB session.

Firmware OTA control is defined separately in `firmware-update-v1.schema.json`. The paired Mac may send only `check` or `install`; all manifest, origin, artifact, signature, version, and rollback decisions remain on the board. Status exposes only bounded versions, state, percentage, and user-readable progress.

Phase-1 client flow:

1. Board establishes an authenticated Wi-Fi TLS or USB session using its opaque board ID and provisioned PSK.
2. Board sends `hello`, including its optional bounded `firmwareVersion` metadata.
3. Host replies `helloAck` with `tasks.read`, bounded `tasks.chat.read`, fixed `tasks.continue.fixed`, `macPower.read`, and the gated `xNews.refresh.request` capability. Dashboard snapshots add `xNews.read` only when a bounded X News cache is present.
4. Board sends `subscribe` and advertises `tasks.read`, bounded `tasks.chat.read`, fixed `tasks.continue.fixed`, diagnostic `display.capture.rgb565`, and gated `xNews.refresh.request` support in `hello`.
5. Host sends complete `snapshot` frames, including optional bounded `hostTime` and `companionVersion` metadata.

## USB fallback envelope

USB uses newline-delimited `~ILOUSB1` control/envelope records around the unchanged four-byte-length-prefixed application frames. Both peers generate fresh 32-byte nonces. The board's `CHALLENGE` authenticates the protocol label, board ID, and both nonces with HMAC-SHA256; the Mac's `AUTH` proves possession of the same PSK before the board sends `READY`. A session key is derived with HKDF-SHA256 using both nonces and the fixed `ILO Board USB v1` context.

Each application frame is then protected with ChaCha20-Poly1305. The direction and strictly increasing sequence number are authenticated as associated data, and the deterministic 12-byte nonce combines the direction marker with that sequence. Mac-to-board and board-to-Mac sequences start at one and never repeat within a session. A malformed handshake, wrong board ID, failed tag, wrong direction, duplicate/reordered sequence, oversized line, timeout, disconnect, or Wi-Fi preemption closes the USB session. Plain serial logs are ignored by the Mac parser and never accepted as protocol data.

An explicit one-shot capture host may then send `screenCaptureRequest` version 1. The request fixes format `rgb565le` and dimensions 1024×600. The board replies with one `screenCaptureBegin`, exactly 100 ordered `screenCaptureChunk` frames of at most 12,288 decoded bytes, and one `screenCaptureResult` containing the full-byte count and lowercase SHA-256 digest. The chunk limit stays below the 65,536-byte frame ceiling even if a JSON encoder escapes every slash in worst-case Base64. An error result contains only a bounded code/message and no pixel data. See `screen-capture-v1.schema.json`.

The optional `codexEnabled` snapshot boolean tells current firmware whether the Codex page and task-backed Dashboard controls belong in navigation. `false` hides the complete page, omits task capabilities/data, and switches Dashboard to its weather/device fallback. A board with no configured Mac starts in that standalone state. For compatibility with older hosts, a missing boolean is inferred from the existing `tasks.read` capability.

The optional `xNewsEnabled` snapshot boolean tells current firmware whether the Mac-approved X News page belongs in navigation. `false` hides the complete page even when an older cache exists. For compatibility with older hosts, a missing boolean is treated as enabled only when a `newsFeed` object is present. The optional `newsFeed` field carries at most five bounded AI/robotics stories and three direct X citations per story. It contains no Grok prompt, reasoning, session, usage, authentication, or tool output beyond the locally validated story contract.

The optional `macPower` field carries only a clamped battery percentage and one coarse state: `battery`, `charging`, `powerAdapter`, or `full`. It intentionally excludes the Mac name, battery serial, hardware identifiers, capacity/health history, power-adapter details, and time-remaining estimates. Missing or invalid power data is treated as unavailable, so desktop Macs and older hosts remain compatible.

The optional `hostTime` field carries the Mac's current UTC offset and a bounded timezone abbreviation. Current companions regenerate it for every snapshot from the configured macOS timezone, so daylight-saving changes reach a connected board automatically. A valid Mac timezone takes precedence over weather-location timezone data; older companions that omit `hostTime` continue using weather data and the board's last persisted offset. The absolute clock still comes from SNTP, and no Mac location or locale data is transmitted.

The optional version strings are display-only operational metadata. The board advertises `firmwareVersion` in its authenticated hello, and the host advertises `companionVersion` in snapshots. Missing fields remain compatible with earlier protocol-v1 peers and are shown as unknown rather than blocking the connection.

An authenticated board may send `xNewsRefreshRequest` after hello/subscription when the user pulls down at the top of X News. The host replies with bounded `xNewsRefreshStatus` states: `fetching`, `updated`, `disabled`, `cooldown`, `busy`, or `failed`. This never bypasses Mac-side Grok opt-in, the 15-minute cost cooldown, one-in-flight limit, direct-X/timestamp validation, or cache preservation. See `x-news-refresh-v1.schema.json`.

An authenticated board may send `codexChatRequest` only after the user opens one of the six tasks in the latest visible snapshot. The companion reads at most four recent turns, keeps only the newest six user/assistant text messages, sanitizes each to at most 360 board-safe characters, and returns them in `codexChatDetail`. Commands, tool output, reasoning, file paths, approval payloads, attachments, and hidden metadata never cross to the board. The board presents the result as a read-only, vertically scrollable recent-chat view; its privacy setting can suppress the request entirely. See `codex-chat-v1.schema.json`.

After explicit Mac-side opt-in, an authenticated board may send `codexContinueRequest` only after the user taps a recent task, holds to arm the action, and taps a separate confirmation. The request carries a one-time bounded ID, one of the six currently visible task IDs, and the fixed action token `continue`; it never carries prompt text. The companion rechecks consent and that the task is still idle or unloaded, rejects replays for two minutes, resumes it through the supported Codex App Server, and constructs exactly `Please continue.` on the Mac. Active tasks, questions, approvals, failed tasks, arbitrary text, commands, and permission changes remain unsupported. See `codex-continue-v1.schema.json`.
