# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# hl7 - segments: the ER7 encoding of HL7 v2. Delimiters from MSH-1 / MSH-2,
# escape sequences, field / repetition / component / subcomponent access,
# building segments, parsing and encoding messages. Spliced into hl7.j via
# include.

/** The most segments `parse` reads in one call: 4096. */
export def const MAX_SEGMENTS as int init 4096;

/** The most fields, repetitions, components and subcomponents `parse` reads in one call: 65536. */
export def const MAX_FIELDS as int init 65536;

# the most lines or spaces one formatting escape (`\.sp n\`, `\.sk n\`) gives
def const MAX_FORMAT_REPEAT as int init 100;

# the escape sequences HL7 v2 defines, without the escape characters
def const ESCAPES as string init '^([FSTREPHN]|X([0-9A-Fa-f]{2})+|\.br|\.sp( ?[0-9]+)?|\.fi|\.nf|\.ce|\.in ?[+-]?[0-9]+|\.ti ?[+-]?[0-9]+|\.sk ?[0-9]+|C[0-9A-Fa-f]{4}|M[0-9A-Fa-f]{4}([0-9A-Fa-f]{2})?|Z.*)$';

/**
 * The delimiters of a message: MSH-1 and the encoding characters of MSH-2.
 *
 * @field field {string} between fields, MSH-1, usually `|`
 * @field component {string} between components, usually `^`
 * @field repetition {string} between repetitions, usually `~`
 * @field escape {string} opens and closes an escape sequence, usually `\`
 * @field subcomponent {string} between subcomponents, usually `&`
 * @field truncation {string} the truncation character of v2.7 and later, usually `#`; `""` when MSH-2 has four characters
 */
export def struct Delimiters {
    field as string,
    component as string,
    repetition as string,
    escape as string,
    subcomponent as string,
    truncation as string
};

/**
 * One segment: its fields as they are on the wire, still escaped, and the
 * delimiters they use. `fields[0]` is the segment ID; field n of a segment
 * is `fields[n]`, except in MSH, where MSH-1 is the field separator itself
 * and MSH-n is `fields[n - 1]`.
 *
 * @field fields {list of string} the segment ID and the fields
 * @field delimiters {Delimiters} the delimiters of its message
 */
export def struct Segment {
    fields as list of string,
    delimiters as Delimiters
};

/**
 * One message: an MSH segment and the segments after it.
 *
 * @field delimiters {Delimiters} the delimiters its MSH declares
 * @field segments {list of Segment} every segment, MSH first
 */
export def struct Message {
    delimiters as Delimiters,
    segments as list of Segment
};

/**
 * The delimiters a message declares: the field separator (MSH-1) and the
 * encoding characters (MSH-2: component, repetition, escape, subcomponent,
 * and from v2.7 truncation).
 *
 * @param separator {string} the field separator, one character
 * @param encoding {string} the encoding characters, 4 or 5
 * @return {Delimiters} the delimiters
 * @throws {Error} kind "hl7" unless they are distinct printable ASCII characters that are not letters, digits or spaces
 * @example
 *   def d as hl7.Delimiters init hl7.delimiters("|", "^~\\&");
 */
export func delimiters(separator as string, encoding as string) {
    if (len($separator) != 1 or (len($encoding) != 4 and len($encoding) != 5)) {
        fail("delimiters are one field separator and 4 or 5 encoding characters, got " +
            shown($separator + $encoding));
    }
    def all as string init $separator + $encoding;
    def chars as list of string init strings.chars($all);
    for (def c in $chars) {
        if (not regex.matches('^[!-/:-@\[-`{-~]$', $c)) {
            fail("a delimiter is printable ASCII and not a letter, digit or space: " + shown($all));
        }
        if (strings.count($all, $c) != 1) {
            fail("the delimiters must differ: " + shown($all));
        }
    }
    def truncation as string init "";
    if (len($chars) == 6) {
        $truncation = $chars[5];
    }
    return Delimiters{
        field: $chars[0],
        component: $chars[1],
        repetition: $chars[2],
        escape: $chars[3],
        subcomponent: $chars[4],
        truncation: $truncation
    };
}

/**
 * The delimiters most senders use: `|` and `^~\&`.
 *
 * @return {Delimiters} the delimiters
 */
export func defaultDelimiters() {
    return delimiters("|", DEFAULT_ENCODING);
}

/**
 * The encoding characters of delimiters, as MSH-2 writes them.
 *
 * @param d {Delimiters} the delimiters
 * @return {string} component, repetition, escape, subcomponent and truncation
 */
func encodingOf(d as Delimiters) {
    return $d.component + $d.repetition + $d.escape + $d.subcomponent + $d.truncation;
}

/**
 * Refuse a segment ID that is not an upper-case letter and two upper-case
 * letters or digits.
 *
 * @param id {string} the ID
 */
func checkId(id as string) {
    if (not regex.matches('^[A-Z][A-Z0-9]{2}$', $id)) {
        fail("a segment ID is an upper-case letter and two upper-case letters or digits, got " +
            shown($id));
    }
}

/**
 * A new segment with no fields. An MSH also gets its encoding characters as
 * MSH-2.
 *
 * @param id {string} the segment ID, such as `PID`, `OBX` or `ZPI`
 * @param d {Delimiters} the delimiters of its message
 * @return {Segment} the segment
 * @throws {Error} kind "hl7" when the ID is not valid
 * @example
 *   def obx as hl7.Segment init hl7.segment("OBX", $m.delimiters);
 */
export func segment(id as string, d as Delimiters) {
    checkId($id);
    if ($id == "MSH") {
        return Segment{fields: ["MSH", encodingOf($d)], delimiters: $d};
    }
    return Segment{fields: [$id], delimiters: $d};
}

/**
 * The ID of a segment.
 *
 * @param s {Segment} the segment
 * @return {string} such as `MSH`, `PID`, `OBX`
 */
export func segmentId(s as Segment) {
    if (len($s.fields) == 0) {
        fail("a segment without fields");
    }
    return $s.fields[0];
}

/**
 * Where field n of a segment is in its `fields`.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1
 * @return {int} the index
 */
func slot(s as Segment, n as int) {
    if ($n < 1) {
        fail(io.sprintf("fields are numbered from 1, got %d", $n));
    }
    if (segmentId($s) == "MSH") {
        return $n - 1;
    }
    return $n;
}

/**
 * Whether field n of a segment is MSH-1 or MSH-2, the delimiters.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number
 * @return {bool} true for MSH-1 and MSH-2
 */
func isDefinition(s as Segment, n as int) {
    return segmentId($s) == "MSH" and $n <= 2;
}

/**
 * Refuse a segment that would not encode as one valid segment.
 *
 * @param s {Segment} the segment
 * @throws {Error} kind "hl7" on an invalid ID, MSH-2 that is not its encoding characters, or a field holding the field separator, a control character or an invalid escape sequence
 */
func checkSegment(s as Segment) {
    def id as string init segmentId($s);
    checkId($id);
    def d as Delimiters init $s.delimiters;
    def first as int init 1;
    if ($id == "MSH") {
        if (len($s.fields) < 2 or $s.fields[1] != encodingOf($d)) {
            fail("MSH-2 is not the message's encoding characters");
        }
        $first = 2;
    }
    for (def i in $first..len($s.fields)) {
        def f as string init $s.fields[$i];
        if (strings.contains($f, $d.field) or regex.matches(CONTROL, $f)) {
            fail(io.sprintf(
                "a field of the %s segment holds the field separator or a control character: %s",
                $id,
                shown($f)));
        }
        checkEscapes($f, $d);
    }
}

/**
 * Parse one segment without its CR.
 *
 * @param text {string} the segment
 * @param d {Delimiters} the delimiters of its message
 * @return {Segment} the segment
 */
func parseSegment(text as string, d as Delimiters) {
    if ($text == "") {
        fail("an empty segment");
    }
    if (regex.matches(CONTROL, $text)) {
        fail("a segment holds a control character: " + shown($text));
    }
    def s as Segment init Segment{fields: strings.split($text, $d.field), delimiters: $d};
    checkId($s.fields[0]);
    if ($s.fields[0] == "MSH" and (len($s.fields) < 2 or $s.fields[1] != encodingOf($d))) {
        fail("a second set of delimiters in one message: " + shown($text));
    }
    def first as int init 1;
    if ($s.fields[0] == "MSH") {
        $first = 2;
    }
    for (def i in $first..len($s.fields)) {
        checkEscapes($s.fields[$i], $d);
    }
    return $s;
}

/**
 * The delimiters an MSH segment's text declares.
 *
 * @param line {string} the MSH segment
 * @return {Delimiters} the delimiters
 */
func delimitersOf(line as string) {
    if (len($line) < 8 or not strings.startsWith($line, "MSH")) {
        fail("a message starts with MSH, its field separator and encoding characters, got " +
            shown($line));
    }
    def separator as string init $line[3..4];
    def end as int init strings.indexOf($line, $separator, 4);
    if ($end < 0) {
        $end = len($line);
    }
    return delimiters($separator, $line[4..$end]);
}

/**
 * Parse one message: an MSH segment and the segments after it, each ended by
 * a CR (the segment terminator HL7 defines; LF is refused). The delimiters
 * are read from MSH-1 and MSH-2.
 *
 * @param text {string} the message
 * @return {Message} the message
 * @throws {Error} kind "hl7" when the text is empty, does not start with MSH, a segment does not end with a CR, a segment does not parse, or a second MSH follows; kind "limit" when the text holds more than `MAX_SEGMENTS` segments or `MAX_FIELDS` fields, repetitions, components and subcomponents
 * @example
 *   def m as hl7.Message init hl7.parse($text);
 *   io.printf("%s\n", hl7.get($m, "PID-5-1"));
 */
export func parse(text as string) {
    def found as list of Message init parseAll($text);
    if (len($found) != 1) {
        fail(io.sprintf("one message expected, found %d", len($found)));
    }
    return $found[0];
}

/**
 * Parse messages that follow each other, each from its MSH: a file or log of
 * messages. Batch envelopes (FHS, BHS, BTS, FTS) are not read.
 *
 * @param text {string} the messages
 * @return {list of Message} the messages in order
 * @throws {Error} kind "hl7" as `parse` does
 */
export func parseAll(text as string) {
    if ($text == "") {
        fail("no segments");
    }
    if (not strings.endsWith($text, CR_TEXT)) {
        fail("the last segment does not end with a CR: " + shown($text));
    }
    if (strings.count($text, CR_TEXT) > MAX_SEGMENTS) {
        failLimit(io.sprintf("more than %d segments", MAX_SEGMENTS));
    }
    def messages as list of Message init [];
    def current as list of Segment init [];
    def d as Delimiters init defaultDelimiters();
    def parts as int init 0;
    def n as int init 0;
    for (def line in strings.split($text[..len($text) - 1], CR_TEXT)) {
        $n = $n + 1;
        if (strings.startsWith($line, "MSH")) {
            if (len($current) > 0) {
                $messages[] = Message{delimiters: $d, segments: $current};
            }
            $d = delimitersOf($line);
            $current = [];
        } elseif ($n == 1) {
            fail("a message starts with MSH, got " + shown($line));
        }
        $parts = countParts($parts, $line, $d);
        $current[] = parseSegment($line, $d);
    }
    $messages[] = Message{delimiters: $d, segments: $current};
    return $messages;
}

/**
 * Add a segment's fields, repetitions, components and subcomponents to a
 * count, refusing more than `MAX_FIELDS`.
 *
 * @param count {int} the count so far
 * @param line {string} the segment
 * @param d {Delimiters} its delimiters
 * @return {int} the new count
 */
func countParts(count as int, line as string, d as Delimiters) {
    def total as int init $count + strings.count($line, $d.field) +
        strings.count($line, $d.repetition) + strings.count($line, $d.component) +
        strings.count($line, $d.subcomponent) + 1;
    if ($total > MAX_FIELDS) {
        failLimit(io.sprintf(
            "more than %d fields, repetitions, components and subcomponents",
            MAX_FIELDS));
    }
    return $total;
}

/**
 * A message as text: every segment followed by a CR. A parsed message that
 * was not changed encodes to the text it was parsed from.
 *
 * @param m {Message} the message
 * @return {string} its segments
 * @throws {Error} kind "hl7" when the first segment is not MSH, a later one is, or a segment is not valid (see `encodeSegment`); kind "limit" when the message holds more than `parse` reads (`MAX_SEGMENTS`, `MAX_FIELDS`)
 */
export func encode(m as Message) {
    if (len($m.segments) == 0 or segmentId($m.segments[0]) != "MSH") {
        fail("a message starts with MSH");
    }
    if (len($m.segments) > MAX_SEGMENTS) {
        failLimit(io.sprintf("more than %d segments", MAX_SEGMENTS));
    }
    def lines as list of string init [];
    def parts as int init 0;
    for (def i in 0..len($m.segments)) {
        def s as Segment init $m.segments[$i];
        if ($s.delimiters != $m.delimiters) {
            fail(io.sprintf("segment %d has other delimiters than the message", $i + 1));
        }
        if ($i > 0 and segmentId($s) == "MSH") {
            fail(io.sprintf("segment %d is a second MSH", $i + 1));
        }
        def line as string init encodeSegment($s);
        $parts = countParts($parts, $line, $m.delimiters);
        $lines[] = $line;
    }
    return strings.join($lines, CR_TEXT) + CR_TEXT;
}

/**
 * A segment as text, without its CR.
 *
 * @param s {Segment} the segment
 * @return {string} its fields joined by the field separator
 * @throws {Error} kind "hl7" when a field holds the field separator, a control character or an invalid escape sequence, or MSH-2 is not the encoding characters
 */
export func encodeSegment(s as Segment) {
    checkSegment($s);
    return strings.join($s.fields, $s.delimiters.field);
}

/**
 * A field as it is on the wire, still escaped; `""` past the last field.
 * MSH-1 is the field separator, MSH-2 the encoding characters.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1
 * @return {string} the field
 */
export func raw(s as Segment, n as int) {
    def at as int init slot($s, $n);
    if ($at == 0) {
        return $s.delimiters.field;
    }
    if ($at >= len($s.fields)) {
        return "";
    }
    return $s.fields[$at];
}

/**
 * A field's value, unescaped. The field holds one value: a field with
 * repetitions, components or subcomponents is read with `component`,
 * `subcomponent`, `components` or `values`. MSH-1 and MSH-2 give the
 * delimiters.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1
 * @return {string} the value, `""` when the field is empty or absent
 * @throws {Error} kind "hl7" when the field has repetitions, components or subcomponents, or an escape sequence that is invalid or has no text meaning
 * @example
 *   def id as string init hl7.field($msh, 10);   # the message control ID
 */
export func field(s as Segment, n as int) {
    def text as string init raw($s, $n);
    if (isDefinition($s, $n)) {
        return $text;
    }
    def d as Delimiters init $s.delimiters;
    if (strings.contains($text, $d.repetition) or strings.contains($text, $d.component) or
        strings.contains($text, $d.subcomponent)) {
        fail(io.sprintf(
            "%s-%d has repetitions, components or subcomponents: %s",
            segmentId($s),
            $n,
            shown($text)));
    }
    return unescaped($text, $d);
}

/**
 * Refuse MSH-1 and MSH-2 for structured access.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number
 */
func checkNotDefinition(s as Segment, n as int) {
    if (isDefinition($s, $n)) {
        fail("MSH-1 and MSH-2 are the delimiters: read them with raw or field");
    }
}

/**
 * How many repetitions a field has: 0 when it is empty.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1
 * @return {int} the number of repetitions
 */
export func repeats(s as Segment, n as int) {
    checkNotDefinition($s, $n);
    def text as string init raw($s, $n);
    if ($text == "") {
        return 0;
    }
    return len(strings.split($text, $s.delimiters.repetition));
}

/**
 * The text of one repetition of a field, still escaped; `""` when absent.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number
 * @param rep {int} the repetition, from 1
 * @return {string} the repetition
 */
func repetitionOf(s as Segment, n as int, rep as int) {
    checkNotDefinition($s, $n);
    if ($rep < 1) {
        fail(io.sprintf("repetitions are numbered from 1, got %d", $rep));
    }
    def text as string init raw($s, $n);
    if ($text == "") {
        return "";
    }
    def reps as list of string init strings.split($text, $s.delimiters.repetition);
    if ($rep > len($reps)) {
        return "";
    }
    return $reps[$rep - 1];
}

/**
 * One part of a list split by a delimiter, from 1; `""` when absent.
 *
 * @param text {string} the text
 * @param separator {string} the delimiter
 * @param n {int} the part, from 1
 * @param what {string} what the parts are, for the message
 * @return {string} the part
 */
func partOf(text as string, separator as string, n as int, what as string) {
    if ($n < 1) {
        fail(io.sprintf("%s are numbered from 1, got %d", $what, $n));
    }
    if ($text == "") {
        return "";
    }
    def parts as list of string init strings.split($text, $separator);
    if ($n > len($parts)) {
        return "";
    }
    return $parts[$n - 1];
}

/**
 * The components of one repetition of a field, unescaped.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1
 * @param rep {int} the repetition, from 1
 * @return {list of string} its components, empty when the repetition is absent
 * @throws {Error} kind "hl7" when a component has subcomponents, or on an escape sequence that is invalid or has no text meaning
 */
export func components(s as Segment, n as int, rep as int) {
    def out as list of string init [];
    def text as string init repetitionOf($s, $n, $rep);
    if ($text == "") {
        return $out;
    }
    for (def c in strings.split($text, $s.delimiters.component)) {
        $out[] = componentText($c, $s, $n);
    }
    return $out;
}

/**
 * A component's value, refusing one with subcomponents.
 *
 * @param text {string} the component, escaped
 * @param s {Segment} its segment
 * @param n {int} its field number, for the message
 * @return {string} the value
 */
func componentText(text as string, s as Segment, n as int) {
    if (strings.contains($text, $s.delimiters.subcomponent)) {
        fail(io.sprintf(
            "a component of %s-%d has subcomponents: read it with subcomponent",
            segmentId($s),
            $n));
    }
    return unescaped($text, $s.delimiters);
}

/**
 * One component of one repetition of a field, unescaped.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1
 * @param rep {int} the repetition, from 1
 * @param component {int} the component, from 1
 * @return {string} the component, `""` when absent
 * @throws {Error} kind "hl7" when the component has subcomponents, or on an escape sequence that is invalid or has no text meaning
 * @example
 *   def family as string init hl7.component($pid, 5, 1, 1);
 */
export func component(s as Segment, n as int, rep as int, component as int) {
    def text as string init partOf(
        repetitionOf($s, $n, $rep),
        $s.delimiters.component,
        $component,
        "components");
    return componentText($text, $s, $n);
}

/**
 * One subcomponent of one component of one repetition of a field,
 * unescaped.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1
 * @param rep {int} the repetition, from 1
 * @param component {int} the component, from 1
 * @param sub {int} the subcomponent, from 1
 * @return {string} the subcomponent, `""` when absent
 * @throws {Error} kind "hl7" on an escape sequence that is invalid or has no text meaning
 */
export func subcomponent(s as Segment, n as int, rep as int, component as int, sub as int) {
    def d as Delimiters init $s.delimiters;
    def text as string init partOf(
        partOf(repetitionOf($s, $n, $rep), $d.component, $component, "components"),
        $d.subcomponent,
        $sub,
        "subcomponents");
    return unescaped($text, $d);
}

/**
 * The first component of every repetition of a field, unescaped: the values
 * of a repeated coded field.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1
 * @return {list of string} one value per repetition
 * @throws {Error} kind "hl7" as `component` does
 */
export func values(s as Segment, n as int) {
    checkNotDefinition($s, $n);
    def out as list of string init [];
    def text as string init raw($s, $n);
    if ($text == "") {
        return $out;
    }
    for (def rep in strings.split($text, $s.delimiters.repetition)) {
        $out[] = componentText(partOf($rep, $s.delimiters.component, 1, "components"), $s, $n);
    }
    return $out;
}

/**
 * One component of every repetition of a field, unescaped, reading the
 * field once. Calling `component` for each repetition in turn re-reads the
 * field each time.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1
 * @param component {int} the component, from 1
 * @return {list of string} one value per repetition, `""` where a repetition lacks it
 * @throws {Error} kind "hl7" as `component` does
 * @example
 *   def ids as list of string init hl7.componentOfEach($pid, 3, 1);   # every PID-3-1
 */
export func componentOfEach(s as Segment, n as int, component as int) {
    checkNotDefinition($s, $n);
    if ($component < 1) {
        fail(io.sprintf("components are numbered from 1, got %d", $component));
    }
    def out as list of string init [];
    def text as string init raw($s, $n);
    if ($text == "") {
        return $out;
    }
    for (def rep in strings.split($text, $s.delimiters.repetition)) {
        def parts as list of string init strings.split($rep, $s.delimiters.component);
        if ($component > len($parts)) {
            $out[] = "";
        } else {
            $out[] = componentText($parts[$component - 1], $s, $n);
        }
    }
    return $out;
}

/**
 * Put a field's wire text, adding empty fields before it as needed.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number; not MSH-1 or MSH-2
 * @param text {string} the escaped text
 * @return {Segment} the segment with the field set
 */
func put(s as Segment, n as int, text as string) {
    if (isDefinition($s, $n)) {
        fail("MSH-1 and MSH-2 are the delimiters and cannot be set");
    }
    def at as int init slot($s, $n);
    if ($text == "" and $at >= len($s.fields)) {
        return $s;
    }
    while (len($s.fields) <= $at) {
        $s.fields[] = "";
    }
    $s.fields[$at] = $text;
    return $s;
}

/**
 * Replace part n of a delimited list, adding empty parts before it.
 *
 * @param text {string} the list
 * @param separator {string} the delimiter
 * @param n {int} the part, from 1
 * @param value {string} the new part
 * @return {string} the list
 */
func replacePart(text as string, separator as string, n as int, value as string) {
    def parts as list of string init [];
    if ($text != "") {
        $parts = strings.split($text, $separator);
    }
    while (len($parts) < $n) {
        $parts[] = "";
    }
    $parts[$n - 1] = $value;
    return strings.join($parts, $separator);
}

/**
 * Set a field to one value, escaping every delimiter in it.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1 (from 3 in MSH)
 * @param value {string} the value
 * @return {Segment} the segment with the field set
 * @example
 *   $pid = hl7.setField($pid, 8, "F");
 */
export func setField(s as Segment, n as int, value as string) {
    def text as string init escaped($value, $s.delimiters);
    $s = put($s, $n, $text);
    return $s;
}

/**
 * Set one subcomponent, escaping the value and adding empty repetitions,
 * components and subcomponents before it as needed. Subcomponent 0 sets the
 * whole component.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number
 * @param rep {int} the repetition, from 1
 * @param component {int} the component, from 1
 * @param sub {int} the subcomponent, from 1, or 0 for the whole component
 * @param value {string} the value
 * @return {Segment} the segment
 */
func setPart(s as Segment, n as int, rep as int, component as int, sub as int, value as string) {
    checkNotDefinition($s, $n);
    if ($rep < 1 or $component < 1 or $sub < 0) {
        fail(io.sprintf(
            "repetitions and components are numbered from 1, got %d and %d",
            $rep,
            $component));
    }
    def d as Delimiters init $s.delimiters;
    def text as string init raw($s, $n);
    if ($value == "" and $text == "") {
        return $s;
    }
    def reps as string init $text;
    def repText as string init partOf($text, $d.repetition, $rep, "repetitions");
    def compText as string init partOf($repText, $d.component, $component, "components");
    def newComp as string init escaped($value, $d);
    if ($sub > 0) {
        $newComp = replacePart($compText, $d.subcomponent, $sub, $newComp);
    }
    def newRep as string init replacePart($repText, $d.component, $component, $newComp);
    $reps = replacePart($text, $d.repetition, $rep, $newRep);
    $s = put($s, $n, $reps);
    return $s;
}

/**
 * Set one component of one repetition of a field, escaping every delimiter
 * in the value and adding empty repetitions and components before it.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1 (from 3 in MSH)
 * @param rep {int} the repetition, from 1
 * @param component {int} the component, from 1
 * @param value {string} the value
 * @return {Segment} the segment with the component set
 * @example
 *   $pid = hl7.setComponent($pid, 5, 1, 2, "Jane");   # PID-5-2, the given name
 */
export func setComponent(s as Segment, n as int, rep as int, component as int, value as string) {
    $s = setPart($s, $n, $rep, $component, 0, $value);
    return $s;
}

/**
 * Set one subcomponent of one component of one repetition of a field,
 * escaping the value and adding empty parts before it.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1 (from 3 in MSH)
 * @param rep {int} the repetition, from 1
 * @param component {int} the component, from 1
 * @param sub {int} the subcomponent, from 1
 * @param value {string} the value
 * @return {Segment} the segment with the subcomponent set
 */
export func setSubcomponent(
    s as Segment,
    n as int,
    rep as int,
    component as int,
    sub as int,
    value as string) {
    if ($sub < 1) {
        fail(io.sprintf("subcomponents are numbered from 1, got %d", $sub));
    }
    $s = setPart($s, $n, $rep, $component, $sub, $value);
    return $s;
}

/**
 * Set a field's wire text as given: repetitions, components, subcomponents
 * and escape sequences already written with the segment's delimiters.
 *
 * @param s {Segment} the segment
 * @param n {int} the field number, from 1 (from 3 in MSH)
 * @param text {string} the text
 * @return {Segment} the segment with the field set
 * @throws {Error} kind "hl7" when the text holds the field separator, a control character or an invalid escape sequence
 * @example
 *   $obx = hl7.setRaw($obx, 3, "2345-7^Glucose^LN");
 */
export func setRaw(s as Segment, n as int, text as string) {
    if (strings.contains($text, $s.delimiters.field) or regex.matches(CONTROL, $text)) {
        fail("raw field text holds the field separator or a control character: " + shown($text));
    }
    checkEscapes($text, $s.delimiters);
    $s = put($s, $n, $text);
    return $s;
}

/**
 * A value with its delimiters and control characters escaped: `\F\`,
 * `\S\`, `\T\`, `\R\`, `\E\`, `\P\` and `\Xhh\` with the message's escape
 * character.
 *
 * @param value {string} the value
 * @param d {Delimiters} the delimiters
 * @return {string} the escaped text
 */
func escaped(value as string, d as Delimiters) {
    def specials as string init $d.field + encodingOf($d);
    def needed as bool init regex.matches(CONTROL, $value);
    for (def c in strings.chars($specials)) {
        if (strings.contains($value, $c)) {
            $needed = true;
        }
    }
    if (not $needed) {
        return $value;
    }
    def e as string init $d.escape;
    def out as list of string init [];
    for (def c in strings.chars($value)) {
        if ($c == $d.field) {
            $out[] = $e + "F" + $e;
        } elseif ($c == $d.component) {
            $out[] = $e + "S" + $e;
        } elseif ($c == $d.subcomponent) {
            $out[] = $e + "T" + $e;
        } elseif ($c == $d.repetition) {
            $out[] = $e + "R" + $e;
        } elseif ($c == $e) {
            $out[] = $e + "E" + $e;
        } elseif ($d.truncation != "" and $c == $d.truncation) {
            $out[] = $e + "P" + $e;
        } elseif (regex.matches(CONTROL, $c)) {
            $out[] = $e + "X" +
                strings.upper(io.sprintf("%d|base=16|pad=2|fill=0", convert.toCodepoint($c))) + $e;
        } else {
            $out[] = $c;
        }
    }
    return strings.join($out, "");
}

/**
 * Refuse text with an unclosed or unknown escape sequence.
 *
 * @param s {string} the escaped text
 * @param d {Delimiters} the delimiters
 * @throws {Error} kind "hl7" on an unclosed or unknown sequence
 */
func checkEscapes(s as string, d as Delimiters) {
    if (not strings.contains($s, $d.escape)) {
        return null;
    }
    def parts as list of string init strings.split($s, $d.escape);
    if (len($parts) % 2 == 0) {
        fail("an escape sequence is not closed: " + shown($s));
    }
    def others as string init $d.field + $d.component + $d.repetition + $d.subcomponent;
    for (def i in 0..len($parts) // 2) {
        def sequence as string init $parts[2 * $i + 1];
        def bad as bool init not regex.matches(ESCAPES, $sequence) or
            ($sequence == "P" and $d.truncation == "");
        for (def c in strings.chars($others)) {
            if (strings.contains($sequence, $c)) {
                $bad = true;
            }
        }
        if ($bad) {
            fail("an unknown escape sequence " + shown($d.escape + $sequence + $d.escape) + " in " +
                shown($s));
        }
    }
}

/**
 * The number at the end of a formatting escape such as `.sp 2`, 1 when it
 * has none, refusing more than `MAX_FORMAT_REPEAT`.
 *
 * @param sequence {string} the sequence
 * @param skip {int} the length of its command
 * @return {int} the count
 */
func formatCount(sequence as string, skip as int) {
    def digits as string init strings.trim($sequence[$skip..]);
    if ($digits == "") {
        return 1;
    }
    if (len($digits) > 3) {
        failLimit(io.sprintf("a formatting escape repeats more than %d times", MAX_FORMAT_REPEAT));
    }
    def count as int init convert.toInt($digits);
    if ($count > MAX_FORMAT_REPEAT) {
        failLimit(io.sprintf("a formatting escape repeats more than %d times", MAX_FORMAT_REPEAT));
    }
    return $count;
}

/**
 * Text with its escape sequences decoded: `F`, `S`, `T`, `R`, `E`, `P` to
 * the delimiters; `X` with hex pairs, each pair one character from 00 to FF
 * (Latin-1); `H` and `N` (highlighting) to nothing; the formatting commands
 * `.br` and `.sp n` to line breaks, `.sk n` to spaces, and `.fi`, `.nf`,
 * `.ce`, `.in n`, `.ti n` to nothing.
 *
 * @param s {string} the escaped text
 * @param d {Delimiters} the delimiters
 * @return {string} the value
 * @throws {Error} kind "hl7" on an unclosed or unknown sequence, and on the character-set switches `C` and `M` and the local `Z`, which have no plain-text meaning (read such a field with `raw`); kind "limit" on a formatting escape repeated more than `MAX_FORMAT_REPEAT` times
 */
func unescaped(s as string, d as Delimiters) {
    if (not strings.contains($s, $d.escape)) {
        return $s;
    }
    checkEscapes($s, $d);
    def parts as list of string init strings.split($s, $d.escape);
    def out as list of string init [];
    for (def i in 0..len($parts)) {
        if ($i % 2 == 0) {
            $out[] = $parts[$i];
        } else {
            $out[] = decodeEscape($parts[$i], $d);
        }
    }
    return strings.join($out, "");
}

/**
 * The text one valid escape sequence stands for.
 *
 * @param sequence {string} the sequence without its escape characters
 * @param d {Delimiters} the delimiters
 * @return {string} the text
 */
func decodeEscape(sequence as string, d as Delimiters) {
    def simple as map of string to string init {
        "F": $d.field,
        "S": $d.component,
        "T": $d.subcomponent,
        "R": $d.repetition,
        "E": $d.escape,
        "P": $d.truncation,
        "H": "",
        "N": "",
        ".br": "\n",
        ".fi": "",
        ".nf": "",
        ".ce": ""
    };
    if (maps.has($simple, $sequence)) {
        return $simple[$sequence];
    }
    def first as string init $sequence[..1];
    if ($first == "X") {
        def out as list of string init [];
        def i as int init 1;
        while ($i < len($sequence)) {
            $out[] = convert.fromCodepoint(convert.toInt($sequence[$i..$i + 2], 16));
            $i = $i + 2;
        }
        return strings.join($out, "");
    }
    if (strings.startsWith($sequence, ".sp")) {
        return strings.replicate("\n", formatCount($sequence, 3));
    }
    if (strings.startsWith($sequence, ".sk")) {
        return strings.replicate(" ", formatCount($sequence, 3));
    }
    if (strings.startsWith($sequence, ".in") or strings.startsWith($sequence, ".ti")) {
        return "";
    }
    fail("the escape sequence " + shown($d.escape + $sequence + $d.escape) +
        " has no plain-text meaning: read the field with raw");
}
