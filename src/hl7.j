# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * HL7 version 2 messages in the pipe-delimited ER7 encoding (ADT, ORU, ORM,
 * OML, SIU and any other type), and MLLP, the framing hospital interfaces
 * send them over TCP.
 *
 * Segments keep their fields as they are on the wire: a parsed message that
 * was not changed encodes to the same text. `field`, `component`,
 * `subcomponent` and `values` read a segment unescaped; `get` and `set` take
 * terser-style paths (`PID-5-1`, `OBX(2)-5`); the `set*` functions write
 * escaped. Delimiters come from MSH-1 and MSH-2, the character set from
 * MSH-18. `ack` builds the acknowledgement; `send`, `receive`, `reply` and
 * `serve` move messages over MLLP. Input that breaks HL7 is an error, never
 * repaired; every failure is `Error{kind: "hl7"}`. There is no validation
 * against the per-version message structures.
 *
 * | topic | covers |
 * | --- | --- |
 * | `core` | errors and checks |
 * | `segments` | delimiters, escapes, segments, parsing and encoding |
 * | `paths` | `get`, `set`, finding segments |
 * | `messages` | new messages, acknowledgements, character sets |
 * | `mllp` | connections, sending, receiving, serving |
 *
 * @module hl7
 * @see https://www.hl7.org/implement/standards/product_brief.cfm?product_id=185
 * @example
 *   def m as hl7.Message init hl7.parse($text);
 *   io.printf("%s %s\n", hl7.get($m, "PID-5-1"), hl7.get($m, "PID-5-2"));
 */
use binary;
use channel;
use convert;
use encoding;
use io;
use lists;
use maps;
use net;
use regex;
use strings;
use task;
use time;
use uuid;

include "topics/core.j";
include "topics/segments.j";
include "topics/paths.j";
include "topics/messages.j";
include "topics/mllp.j";
