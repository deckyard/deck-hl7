<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Messages and segments

A message is a list of segments, each one line ended by CR. The first is
always MSH, the message header:

```text
MSH|^~\&|LAB|HOSP|EHR|HOSP|20260312094500||ORU^R01^ORU_R01|MSG00001|P|2.5.1
PID|1||12345^^^HOSP^MR~99887^^^SSA^SS||Doe^Jane^Q||19800214|F
OBR|1|ORD1|FIL1|24323-8^Comprehensive metabolic panel^LN
OBX|1|NM|2345-7^Glucose^LN||5.4|mmol/L|3.9-6.1|N|||F
```

Fields are separated by MSH-1 (`|`), and MSH-2 names the rest: component
(`^`), repetition (`~`), escape (`\`), subcomponent (`&`), and from v2.7 a
truncation character (`#`). The deck reads them from every MSH.

## Paths

`get` and `set` take terser-style paths. `SEG(n)` is the nth segment with
that ID and `field(r)` the rth repetition, both from 1 and 1 when left out
(HAPI's terser counts both from 0, so its `OBX(1)` is this `OBX(2)`):

```jennifer
def m as hl7.Message init hl7.parse($text);
hl7.get($m, "MSH-9-2");      # "R01"
hl7.get($m, "PID-5-1");      # "Doe"
hl7.get($m, "PID-3(2)-1");   # "99887", the second identifier
hl7.get($m, "OBX(2)-5");     # the second OBX's value
$m = hl7.set($m, "PID-5-2", "Janet");
```

A path without a component or repetition reads and sets the whole field;
reading one that has repetitions or components is an error (name the one
you mean). `PID-3(2)` reads or replaces just that repetition. A segment
that is absent reads as `""`; `set` needs it to exist.

Each `get` and `set` looks its segment up from the start, and a call into
the deck copies the message it is given. On a large message (hundreds of
segments) walk the segments once with `segmentsOf` instead of calling `get`
in a loop.

## Segments

`segmentsOf` gives every segment with an ID, and the segment functions read
it at any depth:

```jennifer
for (def obx in hl7.segmentsOf($m, "OBX")) {
    io.printf("%s = %s %s\n", hl7.component($obx, 3, 1, 2),
        hl7.field($obx, 5), hl7.field($obx, 6));
}
```

`raw` shows a field as sent. `field`, `component`, `subcomponent`,
`components`, `values` and `componentOfEach` unescape (to read a component
of every repetition, use `componentOfEach`: calling `component` for each
repetition re-reads the field every time); each refuses to read a level that has
more structure below it (a component with subcomponents is read with
`subcomponent`), so structured data is never read as if it were text.

## Escapes

| Sequence | Reads as |
|---|---|
| `\F\` `\S\` `\T\` `\R\` `\E\` `\P\` | the field, component, subcomponent, repetition, escape, truncation character |
| `\Xhh..\` | each hex pair one character, 00 to FF, as Latin-1 whatever MSH-18 says; for UTF-8 or another character set read the field with `raw` |
| `\H\` `\N\` | nothing (highlighting on, off) |
| `\.br\`, `\.sp n\` | line breaks |
| `\.sk n\` | spaces |
| `\.fi\` `\.nf\` `\.ce\` `\.in n\` `\.ti n\` | nothing (layout) |
| `\Cxxyy\` `\Mxxyy\` `\Mxxyyzz\` `\Z..\` | an error: character-set switches and local escapes have no plain-text meaning; read the field with `raw` |

`setField`, `setComponent`, `setSubcomponent` and `set` escape every
delimiter and control character in a value. `parse` checks every escape
sequence, so a message it accepts encodes back.

## Building messages

`newMessage` makes the MSH; `segment` and the `set*` functions build the
rest, `addSegment` appends:

```jennifer
def m as hl7.Message init hl7.newMessage("ADT", "A01", "ADT00001", "2.5.1");
$m = hl7.set($m, "MSH-3", "REG");
def pid as hl7.Segment init hl7.setField(hl7.segment("PID", $m.delimiters), 1, "1");
$pid = hl7.setComponent($pid, 5, 1, 1, "Roe");
$m = hl7.addSegment($m, $pid);
```

`encode` and `encodeSegment` check every segment: a field holding the
field separator, a CR or an invalid escape sequence is an error, so a
segment built by hand cannot turn into two on the wire.

## Acknowledgements

`ack` answers a message: the sender and receiver swapped, MSH-9
`ACK^<trigger>^ACK`, and an MSA with the code (`AA` accept, `AE` error,
`AR` reject, or `CA` / `CE` / `CR` in enhanced mode), the original's
control ID and a text.

```jennifer
def reply as hl7.Message init hl7.ack($m, "AA", "", "ACK00001");
```

## Character sets

Text has no character set; bytes do. `parseBytes` and `encodeBytes` use
the one MSH-18 names (`ASCII`, `8859/1` to `8859/9`, `8859/15`, `UNICODE
UTF-8`), or
the `charset` given when MSH-18 is empty (HL7's default is ASCII). Other
character sets are refused.

## Limits

`parse` reads at most `MAX_SEGMENTS` (4096) segments and `MAX_FIELDS`
(65536) fields, repetitions, components and subcomponents in one call, and
`encode` refuses a message beyond them, so what it writes parses back. The
caps bound the parts of a message, not its length: the length is bounded by
MLLP's `maxBytes` (1 MiB by default, about 130 MB to hold at worst), or by
the caller for text from elsewhere.
