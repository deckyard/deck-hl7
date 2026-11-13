# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# hl7 - white-box tests for the paths topic. Spliced into hl7_test.j via
# include.

func testGetReadsPaths() {
    def m as Message init parse(ORU);
    testing.assertEqual(get($m, "MSH-1"), "|");
    testing.assertEqual(get($m, "MSH-2"), "^~\\&");
    testing.assertEqual(get($m, "MSH-9-2"), "R01");
    testing.assertEqual(get($m, "MSH-10"), "MSG00001");
    testing.assertEqual(get($m, "PID-3-1"), "12345");
    testing.assertEqual(get($m, "PID-3(2)-4"), "SSA");
    testing.assertEqual(get($m, "PID-5-2"), "Jane");
    testing.assertEqual(get($m, "OBX-5"), "5.4");
    testing.assertEqual(get($m, "OBX(2)-5"), "line one\nline two & more");
    testing.assertEqual(get($m, "OBX(3)-5"), "");
    testing.assertEqual(get($m, "NTE-3"), "");
    testing.assertEqual(count($m, "OBX"), 2);
    testing.assertEqual(len(segmentsOf($m, "OBX")), 2);
    testing.assertEqual(get(parse("MSH|^~\\&\rPID|1||A~B\r"), "PID-3(2)"), "B");
    for (def bad in ["PID", "PID-0", "pid-1", "PID(0)-1", "PID-1-0", "PID-1-2-3-4", "PID-1234567"]) {
        try {
            get($m, $bad);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "hl7");
        }
    }
    try {
        get($m, "PID-5");
        missed("PID-5 has components");
    } catch (e) {
        testing.assertContains($e.message, "has repetitions, components or subcomponents");
    }
}

func testSetWritesPaths() {
    def m as Message init parse(ORU);
    $m = set($m, "PID-5-2", "Ann|Marie");
    $m = set($m, "PID-3(3)-1", "777");
    $m = set($m, "OBX(2)-5", "plain");
    $m = set($m, "PID-3(2)", "X");
    $m = set($m, "PID-1-1-2", "s");
    testing.assertEqual(get($m, "PID-5-2"), "Ann|Marie");
    testing.assertEqual(raw(segmentsOf($m, "PID")[0], 3), "12345^^^HOSP^MR~X~777");
    testing.assertEqual(get($m, "OBX(2)-5"), "plain");
    testing.assertEqual(raw($m.segments[1], 1), "1&s");
    try {
        set($m, "NTE-3", "x");
        missed("no NTE");
    } catch (e) {
        testing.assertContains($e.message, "the message has no NTE(1) segment");
    }
    try {
        set($m, "MSH-2", "x");
        missed("MSH-2");
    } catch (e) {
        testing.assertContains($e.message, "MSH-1 and MSH-2 are the delimiters");
    }
}

func testExplicitRepetitions() {
    def m as Message init parse("MSH|^~\\&\rPID|1||a~b^c\r");
    try {
        get($m, "PID-3");
        missed("a repeated field without a repetition");
    } catch (e) {
        testing.assertContains($e.message, "has repetitions");
    }
    testing.assertEqual(get($m, "PID-3(1)"), "a");
    $m = set($m, "PID-3(1)", "z");
    testing.assertEqual(raw($m.segments[1], 3), "z~b^c");
    $m = set($m, "PID-3", "only");
    testing.assertEqual(raw($m.segments[1], 3), "only");
}
