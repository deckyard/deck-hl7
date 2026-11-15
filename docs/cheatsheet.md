<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# hl7 cheatsheet

Every export of `@deckyard/hl7`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/hl7/" as hl7;
```

Every failure is `Error{kind: "hl7"}`, except the generic kinds: a reached cap
(more segments, fields or formatting repeats than the limits allow, a received
message over `maxBytes`) is kind `"limit"`; on an MLLP connection a message that
does not arrive whole in time, or no acknowledgement after the retries, is kind
`"timeout"`, a peer that closes kind `"closed"`, and a network failure (refused,
reset, unreachable) the interpreter's `net.NetError` (kind `"net"`), passed on
unchanged.
An `m` argument is a `Message`, an
`s` a `Segment`, a `d` `Delimiters`, a `c` a `Connection`, an `o`
`Options`. Fields, repetitions, components and subcomponents are numbered
from 1, as HL7 numbers them; in MSH, MSH-1 is the field separator and MSH-2
the encoding characters.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `MAX_SEGMENTS` | `4096` | the most segments `parse` reads in one call |
| `MAX_FIELDS` | `65536` | the most fields, repetitions, components and subcomponents `parse` reads in one call |
| `DEFAULT_TIMEOUT_MS` | `30000` | how long MLLP waits for an acknowledgement, or for a whole message once it began |
| `DEFAULT_MAX_BYTES` | `1048576` | the largest MLLP message |

## Messages

| Function | Returns | Does |
|---|---|---|
| `hl7.parse(text)` | `Message` | one message, every segment ended by CR |
| `hl7.parseAll(text)` | `list of Message` | messages that follow each other, each from its MSH |
| `hl7.encode(m)` | `string` | the message as text, checked; an unchanged parsed message gives its text back |
| `hl7.parseBytes(b, charset)` | `Message` | a message from bytes, in MSH-18's character set or `charset` |
| `hl7.encodeBytes(m, charset)` | `bytes` | the message as bytes, in MSH-18's character set or `charset` |
| `hl7.newMessage(type, trigger, controlId, version)` | `Message` | a message with only its MSH |
| `hl7.addSegment(m, s)` | `Message` | add a segment at the end |
| `hl7.ack(m, code, text, controlId)` | `Message` | the acknowledgement: MSH with sender and receiver swapped, MSA |
| `hl7.get(m, path)` | `string` | the value at a path such as `PID-5-1`, `OBX(2)-5`, `PID-3(2)-1`; segment and repetition numbers from 1 |
| `hl7.set(m, path, value)` | `Message` | set the value at a path, escaped |
| `hl7.segmentsOf(m, id)` | `list of Segment` | every segment with an ID |
| `hl7.count(m, id)` | `int` | how many segments have an ID |

## Segments

| Function | Returns | Does |
|---|---|---|
| `hl7.delimiters(separator, encoding)` | `Delimiters` | the delimiters of MSH-1 and MSH-2 |
| `hl7.defaultDelimiters()` | `Delimiters` | `\|` and `^~\&` |
| `hl7.segment(id, d)` | `Segment` | a new segment; an MSH gets MSH-2 |
| `hl7.segmentId(s)` | `string` | the segment's ID |
| `hl7.encodeSegment(s)` | `string` | the segment as text, checked |
| `hl7.raw(s, n)` | `string` | field n as on the wire |
| `hl7.field(s, n)` | `string` | field n unescaped; one with repetitions, components or subcomponents is an error |
| `hl7.repeats(s, n)` | `int` | how many repetitions field n has |
| `hl7.components(s, n, rep)` | `list of string` | the components of one repetition |
| `hl7.component(s, n, rep, component)` | `string` | one component |
| `hl7.subcomponent(s, n, rep, component, sub)` | `string` | one subcomponent |
| `hl7.values(s, n)` | `list of string` | the first component of every repetition |
| `hl7.componentOfEach(s, n, component)` | `list of string` | one component of every repetition, reading the field once |
| `hl7.setField(s, n, value)` | `Segment` | set field n, escaped |
| `hl7.setComponent(s, n, rep, component, value)` | `Segment` | set one component, escaped |
| `hl7.setSubcomponent(s, n, rep, component, sub, value)` | `Segment` | set one subcomponent, escaped |
| `hl7.setRaw(s, n, text)` | `Segment` | set field n's wire text, checked |

## MLLP

| Function | Returns | Does |
|---|---|---|
| `hl7.options()` | `Options` | ASCII, 30 s, 3 retries, 1 MiB, one hour idle |
| `hl7.connect(address, o)` | `Connection` | connect to a listener |
| `hl7.listen(address)` | `net.Listener` | listen for clients |
| `hl7.accept(listener, o)` | `Connection` | wait for a client |
| `hl7.send(c, m)` | `Message` | send a message and return its acknowledgement; sent again on no reply; late acknowledgements of the one before are skipped |
| `hl7.receive(c, waitMs)` | `list of Message` | the next message, or nothing when none began in time |
| `hl7.reply(c, m)` | `null` | send a reply without waiting |
| `hl7.serve(listener, o, handler)` | `null` | answer every client with `handler(m)`, one task per connection; when the listener closes, close the connections and return |
| `hl7.close(c)` | `null` | close the connection |

## Types

### `Delimiters`

| Field | Meaning |
|---|---|
| `field as string` | MSH-1, usually `\|` |
| `component as string` | usually `^` |
| `repetition as string` | usually `~` |
| `escape as string` | usually `\` |
| `subcomponent as string` | usually `&` |
| `truncation as string` | v2.7 and later, usually `#`; `""` without |

### `Segment`

| Field | Meaning |
|---|---|
| `fields as list of string` | the ID and the fields as on the wire |
| `delimiters as Delimiters` | the delimiters of its message |

### `Message`

| Field | Meaning |
|---|---|
| `delimiters as Delimiters` | the delimiters its MSH declares |
| `segments as list of Segment` | every segment, MSH first |

### `Options`

| Field | Meaning |
|---|---|
| `charset as string` | the codec when MSH-18 is empty: `ascii`, `iso-8859-1`, `utf-8`, ... |
| `timeoutMs as int` | how long to wait for an acknowledgement, or for a whole message once it began |
| `retries as int` | how often `send` sends again without an acknowledgement, 0 to 100 |
| `maxBytes as int` | the largest message, 1024 to 67108864 bytes |
| `idleMs as int` | how long `serve` keeps a connection that sends nothing |

### `Connection`

| Field | Meaning |
|---|---|
| `conn as net.Conn` | the socket |
| `options as Options` | how it behaves |
| `pending as channel of bytes` | bytes read past the last message |
| `sent as channel of string` | the control ID sent last, whose late acknowledgements are skipped |
