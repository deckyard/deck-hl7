<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

HL7™ v2.x messages in ER7, the pipe-delimited encoding, and MLLP, the framing
hospital interfaces send them over. Any message type (ADT, ORU, ORM / OML,
SIU, Z-segments) is parsed into segments, fields, repetitions, components and
subcomponents, read and changed through terser-style paths, and encoded back.
`ack` builds the acknowledgement; the MLLP side is a client (`connect`,
`send`), a receiver (`listen`, `accept`, `receive`, `reply`) and `serve`,
one task per connection.

Out of scope:

- **Validation against the version's message structures and data-type
  tables** (which segments an ADT^A01 must have, each field's type): the
  tables are large and licence-restricted.
- Conformance profiles, batch and file headers (FHS / BHS) and the v2 XML
  encoding.
- FHIR™, the REST standard newer systems expose, is `@deckyard/fhir`; the
  lab-instrument protocol is `@deckyard/astm`, a sibling built on the same
  strict stance and field model.

## Decisions

- **Strict, not lenient.** The roadmap first planned a lenient reader with
  warnings. Malformed input is refused instead, never repaired: CR is the
  only segment terminator (an LF is a control character and an error),
  delimiters come from MSH-1 and MSH-2 only (with the v2.7 truncation
  character), and an unknown escape sequence is an error. There is no
  `warnings` list and no separate strict parse.
- **Segments keep their wire text.** A parsed message that was not changed
  encodes back byte for byte, and `parse` checks every escape up front, so
  any parsed message encodes. MSH-1 is the field separator itself and is
  not stored, so MSH-n sits one slot lower than in other segments; MSH-1 and
  MSH-2 cannot be set.
- **Paths are 1-based throughout** (`PID-5-1`, `OBX(2)-5`, `PID-3(2)-1`),
  segment occurrence and repetition included, unlike HAPI's terser, which
  counts those from 0. A path without `(r)` means the whole field, so reading
  a repeated or structured field that way is an error rather than a silent
  first repetition; each read level refuses structure below it.
- **Escapes.** `\F\ \S\ \T\ \R\ \E\`, `\P\`, `\Xhh\`, highlighting and the
  formatting commands are decoded and encoded; the character-set escapes
  (`\C\`, `\M\`) and `\Z\` are refused on read. Decoding splits on the
  escape character once: a position-based scan was quadratic on non-ASCII
  text (45 s for a 200 KB field), which the interpreter's string positions
  made costly.
- **Character sets** come from MSH-18 (ASCII, ISO 8859 parts, UNICODE
  UTF-8) through `encoding`, or from the caller's `charset` when MSH-18 is
  empty. Others are refused.
- **Bulk reads.** `componentOfEach` reads one component of every repetition
  in a single pass; `component` in a loop over repetitions is quadratic.
- **MLLP framing.** A frame is read into a list of chunks, searching only the
  newest chunk (and an end marker split across reads), and joined once;
  growing one buffer was quadratic. Bytes past a frame are kept for the next
  read.
- **Acknowledged sending.** `send` requires a control ID (MSH-10), waits for
  the acknowledgement, resends up to `retries` times when none comes, and
  checks that MSA-2 names the message. A resend can bring two
  acknowledgements, one late, so the next `send` skips acknowledgements of
  the previous control ID.
- **`serve`.** One task per connection; connections are tracked and closed
  when the listener closes, and `serve` returns once their tasks end. A
  handler that throws or returns something other than a message is answered
  with an `AE` acknowledgement. An accept error other than a closed listener
  pauses 100 ms and continues.
- **Pure `.j`.** No interpreter change was needed; the deck needs only `net`
  for MLLP.

## Errors

Every failure is an `Error` of kind `"hl7"` with a message starting `hl7: `
that names what broke the rules, except a reached cap, which is kind
`"limit"`: more than `MAX_SEGMENTS` segments or `MAX_FIELDS` fields,
repetitions, components and subcomponents in `parse` or `encode`, and a
formatting escape repeated more than 100 times. A malformed path number
stays `"hl7"`. On the MLLP side the situations every library shares have
their generic kinds: a received message over `maxBytes` is `"limit"`, a
message that does not arrive whole in time and no acknowledgement after the
retries are `"timeout"`, a peer that closes is `"closed"`, and a network
failure (refused, reset, unreachable, DNS) is the interpreter's
`net.NetError` of kind `"net"`, passed on unchanged with its `reason` and
`op`; it is not resent. The wrappers around `net` pass all of these on.
Refused framing and an outgoing message over `maxBytes` (the caller's
input) stay `"hl7"`.

## Security and limits

- `MAX_SEGMENTS` (4096) and `MAX_FIELDS` (65536) bound the parts of a
  message; at the caps the worst case holds about 127 MB. `encode` refuses a
  message past them, so what it writes parses back.
- The length is bounded by MLLP's `maxBytes` (`DEFAULT_MAX_BYTES`, 1 MiB),
  both ways; it stays that high because base64 PDFs travel in one OBX-5
  field. Text from elsewhere is the caller's to bound.
- A frame must arrive whole within `timeoutMs` of its first byte; a per-read
  deadline let a trickling peer hold a connection forever. `serve` closes a
  connection idle for `idleMs` (an hour by default) and one whose input
  breaks the framing or does not parse.
- `serve` does not limit concurrent clients.
- MLLP has no encryption; run it on a trusted network or through a tunnel.
- Strings from messages are stripped of control and bidirectional-override
  characters before they appear in an error message.

## Testing and validation

- 36 tests over sample messages (ADT, ORU and others built in the tests) and
  MLLP against a scripted raw peer on a loopback TCP socket that writes
  framed or raw bytes, reads frames, pauses and closes, so resends, late
  acknowledgements, split frames, trickling peers and a peer that resets
  the connection are exercised.
- Checked end to end with `examples/receiver.j` and a separate sender.
- Not tested against a production interface engine or a vendor's feed.

## Known limitations and open questions

- A call into the deck rebuilds the `Message` it is given (the interpreter's
  rule for a module's own structs): about 12 MB per `get` on a
  2000-segment message. `get` and `set` avoid a second copy; on large
  messages walk `segmentsOf` instead of calling `get` per field.

## Dependencies on the interpreter

- Floor `>=0.27.0`, for the UTF-8 codecs of `encoding.encode` / `decode`
  and `strings.replicate`; the default binary and the `net` capability (not
  `jennifer-tiny`).
- Read and write deadlines on sockets, `channel`, and tasks with
  `task.poll` for `serve`.
- A reached cap as kind `"limit"` (`jennifer`'s M28.54; the deck's caps moved
  under M28.57), and network failures as `net.NetError` (M28.65), which the
  tests provoke with `net.abort` (M28.71).
- The cost of a module struct crossing into the deck is `jennifer`'s M29.14;
  string positions on non-ASCII text are M29.13.
