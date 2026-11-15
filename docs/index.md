<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/hl7

HL7 version 2 is how hospital systems tell each other about patients,
orders, results and appointments: ADT (admissions), ORM / OML (orders),
ORU (results), SIU (scheduling) and many more message types, each a list
of pipe-delimited segments. This deck reads, changes and builds those
messages in their usual encoding (ER7), acknowledges them, and moves them
over MLLP, the TCP framing interfaces use.

- [Messages and segments](messages.md): parsing, paths, segment access,
  escapes, building messages, acknowledgements, character sets.
- [MLLP](mllp.md): sending, receiving, serving.
- [Cheatsheet](cheatsheet.md): every export.

## Conventions

Snippets assume this import:

```jennifer
import "@deckyard/hl7/" as hl7;
```

Every failure is `Error{kind: "hl7"}` with a message that names what broke
the rules, except a reached cap - more than `MAX_SEGMENTS` segments,
`MAX_FIELDS` fields or a formatting escape repeated more than
`MAX_FORMAT_REPEAT` times, or an MLLP message over `maxBytes` - which is
kind `"limit"`. On an MLLP connection a deadline that passed is kind
`"timeout"`, a peer that closed kind `"closed"`, and a network failure the
interpreter's `net.NetError` (kind `"net"`), passed on unchanged. The deck is strict: input that breaks HL7's encoding is refused,
never repaired. Segments end with CR (an LF is a control character and an
error), delimiters come from MSH-1 and MSH-2 and nowhere else, an unknown
escape sequence is an error. A parsed message keeps its text, so one that
was not changed encodes back byte for byte.

```jennifer
try {
    def m as hl7.Message init hl7.parse($text);
} catch (e) {
    io.printf("%s\n", $e.message);
}
```

The deck does not validate a message against the structures of its HL7
version (which segments an ADT^A01 must have, the data types of each
field): those tables are large and licence-restricted. It reads and writes
any segment, including Z-segments.

The deck needs the `net` capability for MLLP and does not run on
`jennifer-tiny`.
