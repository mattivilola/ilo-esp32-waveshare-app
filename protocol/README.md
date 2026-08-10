# Board protocol

The reference device implementation is the Waveshare ESP32-S3-Touch-LCD-5B (SKU 28151, 1024×600); the protocol itself remains independent of display dimensions.

Protocol version `1` uses a four-byte big-endian payload length followed by UTF-8 JSON. A frame is rejected when it is empty, larger than 65,536 bytes, malformed JSON, or uses an unsupported protocol version.

The transport is TLS 1.2 with a unique 32-byte PSK per board. Bonjour advertises `_iloboard._tcp`; it never carries credentials or private task data.

Phase-1 client flow:

1. Board establishes TLS using its opaque board ID as PSK identity.
2. Board sends `hello`.
3. Host replies `helloAck` with its transport capabilities. Dashboard snapshots always support `tasks.read` and add `xNews.read` only when a verified cache is present.
4. Board sends `subscribe` and advertises its read-only `display.capture.rgb565` capability in `hello`.
5. Host sends complete `snapshot` frames.

An explicit one-shot capture host may then send `screenCaptureRequest` version 1. The request fixes format `rgb565le` and dimensions 1024×600. The board replies with one `screenCaptureBegin`, exactly 100 ordered `screenCaptureChunk` frames of at most 12,288 decoded bytes, and one `screenCaptureResult` containing the full-byte count and lowercase SHA-256 digest. The chunk limit stays below the 65,536-byte frame ceiling even if a JSON encoder escapes every slash in worst-case Base64. An error result contains only a bounded code/message and no pixel data. See `screen-capture-v1.schema.json`.

The optional `newsFeed` snapshot field carries at most five bounded AI/robotics stories and three direct X citations per story. It contains no Grok prompt, reasoning, session, usage, authentication, or tool output beyond the locally validated story contract. Mutating message types are unsupported in protocol version 1.
