# @deckyard/hl7

[![test](https://github.com/deckyard/deck-hl7/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-hl7/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-hl7/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-hl7)](https://github.com/deckyard/deck-hl7/releases/latest)

HL7™ version 2 for [Jennifer](https://jennifer-lang.dev/) programs: parse,
read, change and build ADT, ORU, ORM, SIU and any other message in the
pipe-delimited encoding, with terser-style paths (`PID-5-1`, `OBX(2)-5`),
escapes, character sets from MSH-18 and acknowledgements; and send,
receive and serve them over MLLP. Strict: input that breaks HL7's encoding
is an error, and an unchanged message encodes back byte for byte.

**[Documentation](https://deckyard.github.io/deck-hl7/)**

## Install

```sh
jvc add @deckyard/hl7
```

This vendors the deck to `vendor/<scope>/hl7/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`<scope>-hl7-<version>.tar.gz`) there.

## Usage

```jennifer
use io;

import "@deckyard/hl7/" as hl7;

def m as hl7.Message init hl7.parse($text);
io.printf("%s, %s\n", hl7.get($m, "PID-5-1"), hl7.get($m, "PID-5-2"));
for (def obx in hl7.segmentsOf($m, "OBX")) {
    io.printf("%s = %s\n", hl7.component($obx, 3, 1, 2), hl7.field($obx, 5));
}
```

## Requirements

Jennifer 0.28.0 or newer and the default `jennifer` binary: MLLP needs
`net`, which the stock `jennifer-tiny` lacks.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/hl7_test.j         # the tests, with a scripted MLLP peer
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Trademarks

HL7™ and FHIR™ are trademarks of Health Level Seven International. Other
product and company names may be trademarks of their respective owners. They
are used only to identify the standards this deck works with. This deck is
an independent project, not affiliated with, sponsored or endorsed by Health
Level Seven International.

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.
