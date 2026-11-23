# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# hl7 - white-box tests for the messages topic. Spliced into hl7_test.j via
# include.

func testNewMessagesAndSegments() {
    def m as Message init newMessage("ADT", "A01", "X1", "2.5");
    testing.assertEqual(get($m, "MSH-9-1") + "^" + get($m, "MSH-9-2"), "ADT^A01");
    testing.assertEqual(get($m, "MSH-10"), "X1");
    testing.assertEqual(get($m, "MSH-11"), "P");
    testing.assertEqual(get($m, "MSH-12"), "2.5");
    testing.assertTrue(regex.matches('^20[0-9]{12}$', get($m, "MSH-7")));
    def pid as Segment init setField(segment("PID", $m.delimiters), 3, "12345");
    $m = addSegment($m, $pid);
    testing.assertEqual(get($m, "PID-3"), "12345");
    testing.assertEqual(parse(encode($m)), $m);
    for (def bad in [
        ["adt", "A01", "X1", "2.5"],
        ["ADT", "A1", "X1", "2.5"],
        ["ADT", "A01", "", "2.5"],
        ["ADT", "A01", "X1", "3.0"]
    ]) {
        try {
            newMessage($bad[0], $bad[1], $bad[2], $bad[3]);
            missed("a bad header");
        } catch (e) {
            testing.assertEqual($e.kind, "hl7");
        }
    }
    try {
        addSegment($m, segment("MSH", $m.delimiters));
        missed("a second MSH");
    } catch (e) {
        testing.assertContains($e.message, "a message has one MSH");
    }
    try {
        addSegment($m, segment("PID", delimiters("#", "^~\\&")));
        missed("other delimiters");
    } catch (e) {
        testing.assertContains($e.message, "other delimiters");
    }
}

func testAcknowledgements() {
    def a as Message init ack(parse(ORU), "AE", "bad | value", "ACK7");
    def msh as Segment init $a.segments[0];
    testing.assertEqual(raw($msh, 3) + "/" + raw($msh, 4), "EHR/HOSP");
    testing.assertEqual(raw($msh, 5) + "/" + raw($msh, 6), "LAB/HOSP");
    testing.assertEqual(raw($msh, 9), "ACK^R01^ACK");
    testing.assertEqual(get($a, "MSH-10"), "ACK7");
    testing.assertEqual(get($a, "MSH-12"), "2.5.1");
    testing.assertEqual(encodeSegment($a.segments[1]), "MSA|AE|MSG00001|bad \\F\\ value");
    try {
        ack(parse(ORU), "OK", "", "ACK8");
        missed("code OK");
    } catch (e) {
        testing.assertContains(
            $e.message,
            "an acknowledgement code is one of AA, AE, AR, CA, CE, CR");
    }
    try {
        ack(parse("MSH|^~\\&|A\r"), "AA", "", "ACK9");
        missed("no MSH-10");
    } catch (e) {
        testing.assertContains($e.message, "no control ID");
    }
}

func testCharacterSets() {
    def text as string init "MSH|^~\\&|A|||||||C1|P|2.5||||||8859/1\rNTE|1||Müller\r";
    def latin as bytes init encoding.encode("iso-8859-1", $text);
    def m as Message init parseBytes($latin, "ascii");
    testing.assertEqual(get($m, "NTE-3"), "Müller");
    testing.assertEqual(encodeBytes($m, "ascii"), $latin);
    def utf as string init strings.replace($text, "8859/1", "UNICODE UTF-8");
    testing.assertEqual(
        get(parseBytes(encoding.encode("utf-8", $utf), "ascii"), "NTE-3"),
        "Müller");
    try {
        parseBytes($latin, "ascii");
        parseBytes(encoding.encode("iso-8859-1", strings.replace($text, "|8859/1", "|")), "ascii");
        missed("Latin-1 as ASCII");
    } catch (e) {
        testing.assertContains($e.message, "not valid ascii");
    }
    for (def name in ["ISO IR87", "8859/99"]) {
        try {
            parseBytes(
                encoding.encode("iso-8859-1", strings.replace($text, "8859/1", $name)),
                "ascii");
            missed($name);
        } catch (e) {
            testing.assertEqual($e.kind, "hl7");
        }
    }
    try {
        encodeBytes(parse(strings.replace($text, "|8859/1", "|")), "ascii");
        missed("ü in ascii");
    } catch (e) {
        testing.assertContains($e.message, "cannot be written in ascii");
    }
    try {
        parseBytes($latin, "klingon");
        missed("klingon");
    } catch (e) {
        testing.assertContains($e.message, "an unknown character set");
    }
}

func testAckAndCharsetEdges() {
    def d as Delimiters init defaultDelimiters();
    for (def bad in [
        Message{delimiters: $d, segments: []},
        Message{delimiters: $d, segments: [segment("PID", $d)]}
    ]) {
        try {
            ack($bad, "AA", "", "A1");
            missed("no MSH");
        } catch (e) {
            testing.assertContains($e.message, "does not start with MSH");
        }
    }
    try {
        parseBytes(encoding.encode("utf-8", "MSH|^~\\&|A|||||||C1|P|2.5||||||8859/12\r"), "ascii");
        missed("8859/12");
    } catch (e) {
        testing.assertContains($e.message, "is not read");
    }
}
