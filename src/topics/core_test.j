# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# hl7 - white-box tests for the core topic, and the helpers the other
# overlays share. Spliced into hl7_test.j via include.

# a result message, segments joined by CR
def const ORU as string init "MSH|^~\\&|LAB|HOSP|EHR|HOSP|20260312094500||ORU^R01^ORU_R01|MSG00001|P|2.5.1\r" +
    "PID|1||12345^^^HOSP^MR~99887^^^SSA^SS||Doe^Jane^Q||19800214|F\r" +
    "OBR|1|ORD1|FIL1|24323-8^Comprehensive metabolic panel^LN\r" +
    "OBX|1|NM|14749-6^Glucose^LN||5.4|mmol/L|3.9-6.1|N|||F\r" +
    "OBX|2|FT|NOTE^Note^L||line one\\.br\\line two \\T\\ more||||||F\r";

/**
 * Fail a test that should have thrown: the error is not of kind `hl7`, so
 * the catch that expects one fails.
 *
 * @param what {string} what should have thrown
 */
func missed(what as string) {
    throw Error{kind: "missed", message: "no error for " + $what};
}

/**
 * The message of the error a parse throws.
 *
 * @param text {string} the text
 * @return {string} the error's message, `""` when it parsed
 */
func parseError(text as string) {
    try {
        parseAll($text);
    } catch (e) {
        testing.assertEqual($e.kind, "hl7");
        return $e.message;
    }
    return "";
}

func testShownCleansAndCuts() {
    testing.assertEqual(shown("a\rb"), "\"a?b\"");
    testing.assertEqual(len(shown(strings.replicate("x", 300))), 85);
}

func testRanges() {
    try {
        checkRange(6, 1, 5, "the count");
        missed("6");
    } catch (e) {
        testing.assertEqual($e.message, "hl7: the count must be 1 to 5, got 6");
    }
}
