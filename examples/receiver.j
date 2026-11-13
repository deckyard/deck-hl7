#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * receiver example: an MLLP listener that prints the type, control ID and
 * patient of every message it receives and acknowledges it with AA; a
 * message without a PID is answered with AE.
 *
 *   jennifer run examples/receiver.j :2575
 *
 * Without arguments it prints this usage, so CI runs it without a sender.
 */

use io;
use os;

import "../src/hl7.j" as hl7;

/**
 * Print a message and acknowledge it.
 *
 * @param m {hl7.Message} the message
 * @return {hl7.Message} the acknowledgement
 */
func onMessage(m as hl7.Message) {
    def id as string init hl7.get($m, "MSH-10");
    io.printf("%s^%s %s", hl7.get($m, "MSH-9-1"), hl7.get($m, "MSH-9-2"), $id);
    if (hl7.count($m, "PID") == 0) {
        io.printf(" (no patient)\n");
        return hl7.ack($m, "AE", "no PID segment", "ACK" + $id);
    }
    io.printf(" %s, %s\n", hl7.get($m, "PID-5-1"), hl7.get($m, "PID-5-2"));
    return hl7.ack($m, "AA", "", "ACK" + $id);
}

def args as list of string init os.ARGS;
if (len($args) != 2) {
    io.printf("usage: jennifer run examples/receiver.j <[host]:port>\n");
    exit 0;
}
try {
    hl7.serve(hl7.listen($args[1]), hl7.options(), onMessage);
} catch (e) {
    io.eprintf("%s\n", $e.message);
    exit 1;
}
