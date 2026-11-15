<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# MLLP

MLLP frames each message as the byte 0x0B, the message, 0x1C 0x0D. The
sender waits for the acknowledgement before it sends the next message.
Port 2575 is registered for it.

## Sending

```jennifer
def c as hl7.Connection init hl7.connect("10.0.0.30:2575", hl7.options());
def reply as hl7.Message init hl7.send($c, $m);
if (hl7.get($reply, "MSA-1") != "AA") {
    io.printf("refused: %s\n", hl7.get($reply, "MSA-3"));
}
hl7.close($c);
```

`send` needs a control ID in MSH-10. When no acknowledgement comes within
`timeoutMs` (30 s) it sends the message again, up to `retries` (3) times,
then fails. The reply must be an acknowledgement (one MSA) whose MSA-2 is
this message's control ID; what its code means is the caller's to judge.
A resend can bring two acknowledgements, and one can arrive after `send`
gave up: the next `send` on the connection skips acknowledgements of the
message sent before it, so the connection stays in step.

A network failure (nothing listening, a reset, an unreachable host) is not
resent: it reaches the caller as the interpreter's `net.NetError`, kind
`"net"`, with its `reason` (`refused`, `reset`, ...) and `op`. No
acknowledgement after the retries is kind `"timeout"`, and a peer that
closes the connection kind `"closed"`.

## Receiving

`receive` returns the next message, or nothing when none began within the
wait; `reply` sends the answer:

```jennifer
def c as hl7.Connection init hl7.accept(hl7.listen(":2575"), hl7.options());
for (def m in hl7.receive($c, 60000)) {
    hl7.reply($c, hl7.ack($m, "AA", "", "ACK" + hl7.get($m, "MSH-10")));
}
```

Messages that arrive back to back are read one at a time. Once a
message's first byte came, the whole message must arrive within
`timeoutMs`, however slowly it is sent. A byte before a message's 0x0B
(kind `"hl7"`), a message larger than `maxBytes` (kind `"limit"`), or one
that does not arrive whole in time (kind `"timeout"`) is an error; close
the connection after one. A connection the peer closed is kind
`"closed"`.

## Serving

`serve` accepts every client and gives each its own task; each message goes
to the handler and its return value back to the sender:

```jennifer
func onMessage(m as hl7.Message) {
    return hl7.ack($m, "AA", "", "ACK" + hl7.get($m, "MSH-10"));
}

hl7.serve(hl7.listen(":2575"), hl7.options(), onMessage);
```

A handler that throws, or returns something other than a message, is
answered with an `AE` acknowledgement carrying the error. A connection
whose input breaks the framing or does not parse, sends a message without a
control ID, or sends nothing for `idleMs` (an hour) is closed. When the
listener is closed with `net.close` from another task, `serve` closes every
connection still open and returns once their tasks ended. Other accept
errors (out of file descriptors, say) pause it for 100 ms and it goes on.
`serve` does not limit how many clients connect at once.

## Options

| Field | Default | Means |
|---|---|---|
| `charset` | `ascii` | the character set when MSH-18 is empty |
| `timeoutMs` | 30000 | the wait for an acknowledgement, and for a whole message once it began |
| `retries` | 3 | how often `send` sends again |
| `maxBytes` | 1 MiB | the largest message, both ways |
| `idleMs` | 3600000 | how long `serve` keeps a connection that sends nothing |

MLLP has no encryption; run it on a trusted network or through a tunnel.
