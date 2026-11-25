# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# hl7 - messages: building a message and its MSH, acknowledgements, and the
# character set of MSH-18 for bytes. Spliced into hl7.j via include.

# the acknowledgement codes of MSA-1: original mode, then enhanced mode
def const ACK_CODES as list of string init ["AA", "AE", "AR", "CA", "CE", "CR"];

/**
 * A new message with only its MSH: the default delimiters, MSH-7 the time
 * now, MSH-9 the type and trigger event, MSH-10 the control ID, MSH-11 `P`
 * (production) and MSH-12 the version. Set the sending and receiving
 * application and facility (MSH-3 to MSH-6) with `set`, and add segments
 * with `addSegment`.
 *
 * @param type {string} the message type, such as `ADT`, `ORU`, `ORM`
 * @param trigger {string} the trigger event, such as `A01`, `R01`
 * @param controlId {string} the message control ID, unique per sender
 * @param version {string} the HL7 version, such as `2.5.1`
 * @return {Message} the message
 * @throws {Error} kind "hl7" when the type, trigger or version is malformed or the control ID is empty
 * @example
 *   def m as hl7.Message init hl7.newMessage("ORU", "R01", "MSG00001", "2.5.1");
 *   $m = hl7.set($m, "MSH-3", "LAB");
 */
export func newMessage(type as string, trigger as string, controlId as string, version as string) {
    if (not regex.matches('^[A-Z][A-Z0-9]{2}$', $type) or
        not regex.matches('^[A-Z0-9]{3}$', $trigger)) {
        fail("a message type and trigger event are three upper-case letters or digits, got " +
            shown($type + "^" + $trigger));
    }
    if (not regex.matches('^2\.[0-9]+(\.[0-9]+)?$', $version)) {
        fail("a version is 2.x or 2.x.y, got " + shown($version));
    }
    if ($controlId == "") {
        fail("the control ID is empty");
    }
    def d as Delimiters init defaultDelimiters();
    def msh as Segment init segment("MSH", $d);
    $msh = setField($msh, 7, timestamp());
    $msh = setComponent($msh, 9, 1, 1, $type);
    $msh = setComponent($msh, 9, 1, 2, $trigger);
    $msh = setField($msh, 10, $controlId);
    $msh = setField($msh, 11, "P");
    $msh = setField($msh, 12, $version);
    return Message{delimiters: $d, segments: [$msh]};
}

/**
 * The time now as HL7 writes a timestamp, `YYYYMMDDHHMMSS`.
 *
 * @return {string} the timestamp
 */
func timestamp() {
    return time.format(time.now(), "%Y%m%d%H%M%S");
}

/**
 * Add a segment to the end of a message.
 *
 * @param m {Message} the message
 * @param s {Segment} the segment, built with the message's delimiters
 * @return {Message} the message
 * @throws {Error} kind "hl7" when the segment is an MSH, has other delimiters, or is not valid
 * @example
 *   def pid as hl7.Segment init hl7.setField(hl7.segment("PID", $m.delimiters), 3, "12345");
 *   $m = hl7.addSegment($m, $pid);
 */
export func addSegment(m as Message, s as Segment) {
    if (segmentId($s) == "MSH") {
        fail("a message has one MSH");
    }
    if ($s.delimiters != $m.delimiters) {
        fail("the segment has other delimiters than the message");
    }
    checkSegment($s);
    $m.segments[] = $s;
    return $m;
}

/**
 * The acknowledgement of a message: an MSH with the sender and receiver
 * swapped (MSH-3 / MSH-4 and MSH-5 / MSH-6), MSH-9 `ACK^<trigger>^ACK`, the
 * original's version, and an MSA with the code, the original's control ID
 * and a text.
 *
 * @param m {Message} the message acknowledged
 * @param code {string} `AA` (accept), `AE` (error), `AR` (reject), or in enhanced mode `CA`, `CE`, `CR`
 * @param text {string} MSA-3, a text message, `""` for none
 * @param controlId {string} the acknowledgement's own control ID
 * @return {Message} the acknowledgement, with the original's delimiters
 * @throws {Error} kind "hl7" when the code is unknown, the control ID is empty, or the original has no MSH-10
 * @example
 *   def reply as hl7.Message init hl7.ack($m, "AA", "", "ACK00001");
 */
export func ack(m as Message, code as string, text as string, controlId as string) {
    if (not lists.contains(ACK_CODES, $code)) {
        fail("an acknowledgement code is one of " + strings.join(ACK_CODES, ", ") + ", got " +
            shown($code));
    }
    if ($controlId == "") {
        fail("the control ID is empty");
    }
    if (len($m.segments) == 0 or segmentId($m.segments[0]) != "MSH") {
        fail("the message does not start with MSH");
    }
    def original as Segment init $m.segments[0];
    if (field($original, 10) == "") {
        fail("the message has no control ID (MSH-10) to acknowledge");
    }
    def d as Delimiters init $m.delimiters;
    def msh as Segment init segment("MSH", $d);
    $msh = setRaw($msh, 3, raw($original, 5));
    $msh = setRaw($msh, 4, raw($original, 6));
    $msh = setRaw($msh, 5, raw($original, 3));
    $msh = setRaw($msh, 6, raw($original, 4));
    $msh = setField($msh, 7, timestamp());
    $msh = setComponent($msh, 9, 1, 1, "ACK");
    $msh = setComponent($msh, 9, 1, 2, component($original, 9, 1, 2));
    $msh = setComponent($msh, 9, 1, 3, "ACK");
    $msh = setField($msh, 10, $controlId);
    $msh = setRaw($msh, 11, raw($original, 11));
    $msh = setRaw($msh, 12, raw($original, 12));
    def msa as Segment init setField(segment("MSA", $d), 1, $code);
    $msa = setRaw($msa, 2, raw($original, 10));
    $msa = setField($msa, 3, $text);
    return Message{delimiters: $d, segments: [$msh, $msa]};
}

/**
 * The codec of an MSH-18 character set.
 *
 * @param name {string} MSH-18's first value, `""` when absent
 * @param otherwise {string} the codec when MSH-18 is empty
 * @return {string} the codec, such as `ascii`, `iso-8859-1`, `utf-8`
 * @throws {Error} kind "hl7" for a character set the deck does not read
 */
func codecOf(name as string, otherwise as string) {
    if ($name == "") {
        return $otherwise;
    }
    if ($name == "ASCII") {
        return "ascii";
    }
    if ($name == "UNICODE UTF-8") {
        return "utf-8";
    }
    def m as regex.Match init regex.find('^8859/([1-9]|15)$', $name);
    if ($m.start == 0) {
        return "iso-8859-" + $m.groups[0];
    }
    fail("the character set " + shown($name) +
        " is not read: ASCII, 8859/1 to 8859/9, 8859/15 and UNICODE UTF-8 are");
}

/**
 * The first character set MSH-18 names.
 *
 * @param msh {Segment} the MSH
 * @return {string} its first value, `""` when MSH-18 is empty
 */
func charsetName(msh as Segment) {
    if (repeats($msh, 18) == 0) {
        return "";
    }
    return values($msh, 18)[0];
}

/**
 * Refuse a codec the encoding library does not know.
 *
 * @param codec {string} the codec
 */
func checkCodec(codec as string) {
    if ($codec == "utf-8") {
        return null;
    }
    try {
        encoding.encode($codec, "A");
    } catch (e) {
        fail("an unknown character set " + shown($codec));
    }
}

/**
 * A message as bytes in the character set MSH-18 names, or `charset` when
 * MSH-18 is empty.
 *
 * @param m {Message} the message
 * @param charset {string} the codec for an empty MSH-18: `ascii` (HL7's default), `iso-8859-1`, `utf-8`, ...
 * @return {bytes} the encoded message
 * @throws {Error} kind "hl7" when the message does not encode, MSH-18 names a character set the deck does not read, or a character has no byte in it
 * @example
 *   fs.writeBytes("out.hl7", hl7.encodeBytes($m, "ascii"));
 */
export func encodeBytes(m as Message, charset as string) {
    checkCodec($charset);
    def text as string init encode($m);
    def codec as string init codecOf(charsetName($m.segments[0]), $charset);
    try {
        if ($codec == "utf-8") {
            return encoding.encode("utf-8", $text);
        }
        return encoding.encode($codec, $text);
    } catch (e) {
        fail("the message cannot be written in " + $codec + ": " + $e.message);
    }
}

/**
 * Parse a message from bytes, in the character set its MSH-18 names, or
 * `charset` when MSH-18 is empty.
 *
 * @param b {bytes} the message
 * @param charset {string} the codec for an empty MSH-18: `ascii` (HL7's default), `iso-8859-1`, `utf-8`, ...
 * @return {Message} the message
 * @throws {Error} kind "hl7" when the bytes are not valid in the character set, MSH-18 names one the deck does not read, or the text does not parse
 * @example
 *   def m as hl7.Message init hl7.parseBytes(fs.readBytes("in.hl7"), "ascii");
 */
export func parseBytes(b as bytes, charset as string) {
    checkCodec($charset);
    def end as int init binary.indexOf($b, encoding.encode("utf-8", CR_TEXT));
    if ($end < 0) {
        $end = len($b);
    }
    def head as string init encoding.decode("iso-8859-1", $b[..$end]);
    def msh as Segment init parseSegment($head, delimitersOf($head));
    def codec as string init codecOf(charsetName($msh), $charset);
    def text as string init "";
    try {
        if ($codec == "utf-8") {
            $text = encoding.decode("utf-8", $b);
        } else {
            $text = encoding.decode($codec, $b);
        }
    } catch (e) {
        fail("the message is not valid " + $codec + ": " + $e.message);
    }
    return parse($text);
}
