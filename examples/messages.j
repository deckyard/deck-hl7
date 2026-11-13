#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * messages example: HL7 v2 without a network. It reads a lab result
 * message with paths and segment access, changes a value, builds an ADT
 * message from nothing, and prints the acknowledgement of the result.
 *
 *   jennifer run examples/messages.j
 */

use io;
use strings;

import "../src/hl7.j" as hl7;

# an ORU^R01 from a lab system; every segment ends with CR
def text as string init "MSH|^~\\&|LAB|HOSP|EHR|HOSP|20260312094500||ORU^R01^ORU_R01|MSG00001|P|2.5.1\r" +
    "PID|1||12345^^^HOSP^MR||Doe^Jane^Q||19800214|F\r" +
    "OBR|1|ORD1|FIL1|24323-8^Comprehensive metabolic panel^LN\r" +
    "OBX|1|NM|2345-7^Glucose^LN||5.4|mmol/L|3.9-6.1|N|||F\r" +
    "OBX|2|NM|2160-0^Creatinine^LN||133|umol/L|45-90|H|||F\r";

def m as hl7.Message init hl7.parse($text);
io.printf("%s %s, born %s\n", hl7.get($m, "PID-5-2"), hl7.get($m, "PID-5-1"), hl7.get($m, "PID-7"));
for (def obx in hl7.segmentsOf($m, "OBX")) {
    io.printf(
        "  %s: %s %s (%s, flag %s)\n",
        hl7.component($obx, 3, 1, 2),
        hl7.field($obx, 5),
        hl7.field($obx, 6),
        hl7.field($obx, 7),
        hl7.field($obx, 8));
}

def adt as hl7.Message init hl7.newMessage("ADT", "A01", "ADT00001", "2.5.1");
$adt = hl7.set($adt, "MSH-3", "REG");
$adt = hl7.set($adt, "MSH-4", "HOSP");
def pid as hl7.Segment init hl7.setField(hl7.segment("PID", $adt.delimiters), 1, "1");
$pid = hl7.setComponent($pid, 3, 1, 1, "67890");
$pid = hl7.setComponent($pid, 5, 1, 1, "Roe");
$pid = hl7.setComponent($pid, 5, 1, 2, "Richard");
$adt = hl7.addSegment($adt, $pid);
io.printf("ADT segments: %d, PID-5: %s\n", len($adt.segments), hl7.raw($pid, 5));

def reply as hl7.Message init hl7.ack($m, "AA", "", "ACK00001");
io.printf("%s", strings.replace(hl7.encode($reply), "\r", "\n"));
