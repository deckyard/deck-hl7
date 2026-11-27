# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# hl7 - white-box tests for the segments topic. Spliced into hl7_test.j via
# include.

func testParseKeepsTheTextExactly() {
    def m as Message init parse(ORU);
    testing.assertEqual(len($m.segments), 5);
    testing.assertEqual(encode($m), ORU);
    testing.assertEqual(segmentId($m.segments[3]), "OBX");
}

func testDelimitersComeFromTheMsh() {
    def m as Message init parse("MSH#!*%$|#A\rPID#1##X!Y*Z$W\r");
    def d as Delimiters init $m.delimiters;
    testing.assertEqual(
        $d.field + $d.component + $d.repetition + $d.escape + $d.subcomponent,
        "#!*%$");
    def pid as Segment init $m.segments[1];
    testing.assertEqual(field($pid, 1), "1");
    testing.assertEqual(component($pid, 3, 1, 2), "Y");
    testing.assertEqual(subcomponent($pid, 3, 2, 1, 2), "W");
    testing.assertEqual(field($m.segments[0], 1), "#");
    testing.assertEqual(field($m.segments[0], 2), "!*%$|");
    testing.assertEqual($d.truncation, "|");
    testing.assertEqual(raw($m.segments[0], 3), "A");
}

func testDelimitersAreChecked() {
    for (def bad in [["|", "^~\\"], ["||", "^~\\&"], ["|", "^~\\|"], ["|", "^~a&"], ["|", "^~\\é"]]) {
        try {
            delimiters($bad[0], $bad[1]);
            missed($bad[0] + $bad[1]);
        } catch (e) {
            testing.assertEqual($e.kind, "hl7");
        }
    }
}

func testParseRefusesWhatBreaksHl7() {
    testing.assertContains(parseError(""), "no segments");
    testing.assertContains(parseError("MSH|^~\\&|A"), "does not end with a CR");
    testing.assertContains(parseError("PID|1\r"), "a message starts with MSH");
    testing.assertContains(parseError("MSH|^~\\&|A\nPID|1\r"), "control character");
    testing.assertContains(parseError("MSH|^~\\&|A\r\rPID|1\r"), "an empty segment");
    testing.assertContains(parseError("MSH|^~\\&|A\rpid|1\r"), "a segment ID is");
    testing.assertContains(parseError("MSH|^~\r"), "a message starts with MSH");
    testing.assertEqual(parseError(ORU), "");
    try {
        parse(ORU + ORU);
        missed("two messages");
    } catch (e) {
        testing.assertContains($e.message, "one message expected, found 2");
    }
    testing.assertEqual(len(parseAll(ORU + ORU)), 2);
}

/**
 * The message of a parse past a cap, which must be kind "limit".
 *
 * @param text {string} the text to parse
 * @return {string} the message, "" when it parsed
 */
func capError(text as string) {
    try {
        parse($text);
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        return $e.message;
    }
    return "";
}

func testParseCapsWhatItHolds() {
    testing.assertEqual(
        capError("MSH|^~\\&\rZZZ" + strings.replicate("|", MAX_FIELDS) + "\r"),
        "hl7: more than 262144 fields, repetitions, components and subcomponents");
    testing.assertEqual(
        capError(strings.replicate("\r", MAX_SEGMENTS + 1)),
        "hl7: more than 16384 segments");
}

func testFieldAccess() {
    def m as Message init parse(ORU);
    def pid as Segment init $m.segments[1];
    testing.assertEqual(repeats($pid, 3), 2);
    testing.assertEqual(components($pid, 3, 2), ["99887", "", "", "SSA", "SS"]);
    testing.assertEqual(components($pid, 3, 3), []);
    testing.assertEqual(values($pid, 3), ["12345", "99887"]);
    testing.assertEqual(component($pid, 5, 1, 9), "");
    testing.assertEqual(field($pid, 7), "19800214");
    testing.assertEqual(field($pid, 99), "");
    try {
        field($pid, 5);
        missed("components through field");
    } catch (e) {
        testing.assertContains($e.message, "PID-5 has repetitions, components or subcomponents");
    }
    try {
        repeats($m.segments[0], 2);
        missed("MSH-2");
    } catch (e) {
        testing.assertContains($e.message, "MSH-1 and MSH-2 are the delimiters");
    }
    try {
        raw($pid, 0);
        missed("field 0");
    } catch (e) {
        testing.assertContains($e.message, "fields are numbered from 1");
    }
    def obx as Segment init parse("MSH|^~\\&\rOBX|1|CE|A&B^x\r").segments[1];
    try {
        component($obx, 3, 1, 1);
        missed("subcomponents through component");
    } catch (e) {
        testing.assertContains($e.message, "has subcomponents");
    }
    testing.assertEqual(subcomponent($obx, 3, 1, 1, 2), "B");
}

func testEscapesAreDecoded() {
    def d as Delimiters init defaultDelimiters();
    testing.assertEqual(unescaped("a\\F\\b\\S\\c\\T\\d\\R\\e\\E\\f", $d), "a|b^c&d~e\\f");
    testing.assertEqual(unescaped("x\\X0D0A\\y\\XB5\\", $d), "x\r\nyµ");
    testing.assertEqual(
        unescaped("\\H\\bold\\N\\ a\\.br\\b\\.sp 2\\c\\.sk 3\\d\\.in +4\\e\\.fi\\", $d),
        "bold a\nb\n\nc   de");
    for (def bad in ["a\\F", "\\Q\\", "\\X1\\", "\\P\\", "\\Zlocal\\", "\\C2842\\"]) {
        try {
            unescaped($bad, $d);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "hl7");
        }
    }
    def v27 as Delimiters init delimiters("|", "^~\\&#");
    testing.assertEqual(unescaped("a\\P\\b", $v27), "a#b");
    testing.assertEqual(escaped("a#b", $v27), "a\\P\\b");
}

func testValuesAreEscaped() {
    def d as Delimiters init defaultDelimiters();
    def value as string init "a|b^c&d~e\\f\r" + convert.fromCodepoint(1);
    def s as Segment init setField(segment("NTE", $d), 3, $value);
    testing.assertEqual(raw($s, 3), "a\\F\\b\\S\\c\\T\\d\\R\\e\\E\\f\\X0D\\\\X01\\");
    testing.assertEqual(field($s, 3), $value);
    testing.assertEqual(escaped("plain", $d), "plain");
}

func testSegmentsAreBuilt() {
    def d as Delimiters init defaultDelimiters();
    testing.assertEqual(encodeSegment(segment("MSH", $d)), "MSH|^~\\&");
    def pid as Segment init setField(segment("PID", $d), 1, "1");
    $pid = setComponent($pid, 5, 1, 2, "Jane");
    $pid = setComponent($pid, 5, 1, 1, "Doe");
    $pid = setSubcomponent($pid, 3, 2, 4, 2, "x&y");
    testing.assertEqual(encodeSegment($pid), "PID|1||~^^^&x\\T\\y||Doe^Jane");
    testing.assertEqual(len(setField($pid, 40, "").fields), 6);
    testing.assertEqual(encodeSegment(setComponent(segment("PV1", $d), 3, 2, 1, "")), "PV1");
    $pid = setRaw($pid, 8, "F");
    testing.assertEqual(field($pid, 8), "F");
    for (def bad in ["a|b", "a\\Q\\", "a\rb"]) {
        try {
            setRaw($pid, 9, $bad);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "hl7");
        }
    }
    def msh as Segment init segment("MSH", $d);
    for (def n in [1, 2]) {
        try {
            setField($msh, $n, "x");
            missed("MSH-" + convert.toString($n));
        } catch (e) {
            testing.assertContains($e.message, "MSH-1 and MSH-2 are the delimiters");
        }
    }
    testing.assertEqual(encodeSegment(setField($msh, 3, "LAB")), "MSH|^~\\&|LAB");
    try {
        segment("pid", $d);
        missed("pid");
    } catch (e) {
        testing.assertContains($e.message, "a segment ID is");
    }
}

func testEncodeRefusesWhatWouldNotParseBack() {
    def m as Message init parse(ORU);
    def d as Delimiters init $m.delimiters;
    for (def bad in [
        Segment{fields: ["NTE", "a\rMSH|evil"], delimiters: $d},
        Segment{fields: ["NTE", "x|y"], delimiters: $d},
        Segment{fields: ["NTE", "\\Q\\"], delimiters: $d},
        Segment{fields: ["nte"], delimiters: $d},
        Segment{fields: [], delimiters: $d}
    ]) {
        def broken as Message init $m;
        $broken.segments[] = $bad;
        try {
            encode($broken);
            missed("an invalid segment");
        } catch (e) {
            testing.assertEqual($e.kind, "hl7");
        }
    }
    def twice as Message init $m;
    $twice.segments[] = $m.segments[0];
    try {
        encode($twice);
        missed("a second MSH");
    } catch (e) {
        testing.assertContains($e.message, "a second MSH");
    }
}

func testEscapesAreReadInLinearTime() {
    def d as Delimiters init defaultDelimiters();
    def started as time.Time init time.now();
    def value as string init unescaped(strings.replicate("é\\H\\", 40000), $d);
    testing.assertEqual(len($value), 40000);
    def s as Segment init setField(segment("NTE", $d), 3, strings.replicate("é^", 20000));
    testing.assertEqual(len(field($s, 3)), 40000);
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 5000);
}

func testParseRefusesInvalidEscapes() {
    for (def bad in ["NTE|1||\\Q\\x", "NTE|1||a\\b", "NTE|1||\\P\\", "NTE|1||\\Za^b\\"]) {
        testing.assertContains(parseError("MSH|^~\\&\r" + $bad + "\r"), "escape sequence");
    }
    def m as Message init parse("MSH|^~\\&\rNTE|1||\\M2442\\x\\C2842\\\r");
    testing.assertEqual(encode($m), "MSH|^~\\&\rNTE|1||\\M2442\\x\\C2842\\\r");
    try {
        get($m, "NTE-3");
        missed("a character-set switch read as text");
    } catch (e) {
        testing.assertContains($e.message, "has no plain-text meaning");
    }
    try {
        unescaped("\\.sp 99999999999999999999\\", defaultDelimiters());
        missed("a huge .sp");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
    }
    try {
        unescaped("\\.sp 500\\", defaultDelimiters());
        missed(".sp over the cap");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertEqual($e.message, "hl7: a formatting escape repeats more than 100 times");
    }
}

func testComponentOfEachReadsTheFieldOnce() {
    def pid as Segment init parse(ORU).segments[1];
    testing.assertEqual(componentOfEach($pid, 3, 4), ["HOSP", "SSA"]);
    testing.assertEqual(componentOfEach($pid, 3, 9), ["", ""]);
    testing.assertEqual(componentOfEach($pid, 9, 1), []);
}

func testEncodeRefusesWhatParseWouldRefuse() {
    def m as Message init set(parse(ORU), "PID-270000", "x");
    try {
        encode($m);
        missed("270000 fields");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertContains($e.message, "more than 262144 fields");
    }
}
