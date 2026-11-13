# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# hl7 - paths: terser-style paths (`PID-5-1`, `OBX(2)-5`, `PID-3(2)-1`) to
# read and set values, and finding segments by ID. Spliced into hl7.j via
# include.

# a path: segment ID, its occurrence, field, repetition, component,
# subcomponent
def const PATH as string init '^([A-Z][A-Z0-9]{2})(\(([0-9]+)\))?-([0-9]+)(\(([0-9]+)\))?(-([0-9]+)(-([0-9]+))?)?$';

# a path, parsed; component and sub are 0 when the path stops before them
def struct Path {
    id as string,
    occurrence as int,
    field as int,
    rep as int,
    explicitRep as bool,
    component as int,
    sub as int
};

/**
 * Parse a path.
 *
 * @param path {string} such as `OBX(2)-5-1`
 * @return {Path} the path
 * @throws {Error} kind "hl7" when it is not a path
 */
func pathOf(path as string) {
    def m as regex.Match init regex.find(PATH, $path);
    if ($m.start < 0) {
        fail("a path is SEG[(n)]-field[(r)][-component[-subcomponent]], such as PID-5-1 or " +
            "OBX(2)-5, got " + shown($path));
    }
    def g as list of string init $m.groups;
    def p as Path init Path{
        id: $g[0],
        occurrence: numberOr($g[2], 1),
        field: numberOr($g[3], 0),
        rep: numberOr($g[5], 1),
        explicitRep: $g[5] != "",
        component: numberOr($g[7], 0),
        sub: numberOr($g[9], 0)
    };
    if ($p.occurrence < 1 or $p.field < 1 or $p.rep < 1 or
        ($g[7] != "" and $p.component < 1) or ($g[9] != "" and $p.sub < 1)) {
        fail("path numbers start at 1: " + shown($path));
    }
    return $p;
}

/**
 * A number from a path, or a default when the part is absent.
 *
 * @param digits {string} the digits, `""` when absent
 * @param otherwise {int} the default
 * @return {int} the number
 */
func numberOr(digits as string, otherwise as int) {
    if ($digits == "") {
        return $otherwise;
    }
    if (len($digits) > 6) {
        fail("a path number is too large: " + $digits);
    }
    return convert.toInt($digits);
}

/**
 * Every segment of a message with an ID, in order.
 *
 * @param m {Message} the message
 * @param id {string} the segment ID, such as `OBX`
 * @return {list of Segment} the segments
 * @example
 *   for (def obx in hl7.segmentsOf($m, "OBX")) {
 *       io.printf("%s = %s\n", hl7.component($obx, 3, 1, 2), hl7.field($obx, 5));
 *   }
 */
export func segmentsOf(m as Message, id as string) {
    checkId($id);
    def out as list of Segment init [];
    for (def s in $m.segments) {
        if (segmentId($s) == $id) {
            $out[] = $s;
        }
    }
    return $out;
}

/**
 * How many segments of a message have an ID.
 *
 * @param m {Message} the message
 * @param id {string} the segment ID
 * @return {int} the count
 */
export func count(m as Message, id as string) {
    checkId($id);
    def n as int init 0;
    for (def s in $m.segments) {
        if (segmentId($s) == $id) {
            $n = $n + 1;
        }
    }
    return $n;
}

/**
 * The value at a path, unescaped. `SEG(n)` picks the nth segment with that
 * ID and `field(r)` the rth repetition, both from 1 and 1 when left out.
 * Without a component the field must hold one value, as `field` reads it.
 *
 * @param m {Message} the message
 * @param path {string} such as `PID-5-1`, `OBX(2)-5`, `PID-3(2)-1`, `MSH-9-2`
 * @return {string} the value, `""` when the segment or the value is absent
 * @throws {Error} kind "hl7" when the path is not valid, or as `field`, `component` and `subcomponent` do
 * @example
 *   def family as string init hl7.get($m, "PID-5-1");
 *   def second as string init hl7.get($m, "OBX(2)-5");
 */
export func get(m as Message, path as string) {
    def p as Path init pathOf($path);
    def at as int init -1;
    def seen as int init 0;
    for (def i in 0..len($m.segments)) {
        if ($at < 0 and len($m.segments[$i].fields) > 0 and $m.segments[$i].fields[0] == $p.id) {
            $seen = $seen + 1;
            if ($seen == $p.occurrence) {
                $at = $i;
            }
        }
    }
    if ($at < 0) {
        return "";
    }
    def s as Segment init $m.segments[$at];
    if (isDefinition($s, $p.field) and $p.rep == 1 and $p.component == 0) {
        return raw($s, $p.field);
    }
    if ($p.component == 0) {
        if (not $p.explicitRep) {
            return field($s, $p.field);
        }
        def text as string init repetitionOf($s, $p.field, $p.rep);
        if (strings.contains($text, $s.delimiters.component) or
            strings.contains($text, $s.delimiters.subcomponent)) {
            fail(shown($path) + " has components: name one");
        }
        return unescaped($text, $s.delimiters);
    }
    if ($p.sub == 0) {
        return component($s, $p.field, $p.rep, $p.component);
    }
    return subcomponent($s, $p.field, $p.rep, $p.component, $p.sub);
}

/**
 * Set the value at a path, escaping it. The segment must exist; repetitions,
 * components and subcomponents before the one set are added empty.
 *
 * @param m {Message} the message
 * @param path {string} such as `PID-5-1`, `OBX(2)-5`, `MSH-10`
 * @param value {string} the value
 * @return {Message} the message with the value set
 * @throws {Error} kind "hl7" when the path is not valid, names MSH-1 or MSH-2, or its segment is absent
 * @example
 *   $m = hl7.set($m, "PID-5-2", "Jane");
 */
export func set(m as Message, path as string, value as string) {
    def p as Path init pathOf($path);
    def at as int init -1;
    def seen as int init 0;
    for (def i in 0..len($m.segments)) {
        if ($at < 0 and len($m.segments[$i].fields) > 0 and $m.segments[$i].fields[0] == $p.id) {
            $seen = $seen + 1;
            if ($seen == $p.occurrence) {
                $at = $i;
            }
        }
    }
    if ($at < 0) {
        fail(io.sprintf("the message has no %s(%d) segment", $p.id, $p.occurrence));
    }
    def s as Segment init $m.segments[$at];
    if ($p.component == 0 and not $p.explicitRep) {
        $s = setField($s, $p.field, $value);
    } elseif ($p.component == 0) {
        checkNotDefinition($s, $p.field);
        def text as string init replacePart(
            raw($s, $p.field),
            $s.delimiters.repetition,
            $p.rep,
            escaped($value, $s.delimiters));
        $s = put($s, $p.field, $text);
    } else {
        $s = setPart($s, $p.field, $p.rep, $p.component, $p.sub, $value);
    }
    $m.segments[$at] = $s;
    return $m;
}
