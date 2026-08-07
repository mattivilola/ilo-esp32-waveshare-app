# Board protocol

Protocol version `1` uses a four-byte big-endian payload length followed by UTF-8 JSON. A frame is rejected when it is empty, larger than 65,536 bytes, malformed JSON, or uses an unsupported protocol version.

The transport is TLS 1.2 with a unique 32-byte PSK per board. Bonjour advertises `_iloboard._tcp`; it never carries credentials or private task data.

Phase-1 client flow:

1. Board establishes TLS using its opaque board ID as PSK identity.
2. Board sends `hello`.
3. Host replies `helloAck` with `capabilities: ["tasks.read"]`.
4. Board sends `subscribe`.
5. Host sends complete `snapshot` frames and periodic `ping` frames.

Mutating message types are unsupported in protocol version 1.

