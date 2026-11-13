# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# hl7 - core: the error helper and small checks. Spliced into hl7.j via
# include.

# the segment terminator, as text
def const CR_TEXT as string init "\r";

# the encoding characters most senders use: component, repetition, escape,
# subcomponent
def const DEFAULT_ENCODING as string init '^~\&';

# control characters, which no segment holds
def const CONTROL as string init '[\x00-\x1f\x7f]';

# what an error message never shows: control characters and the bidi controls
# that reorder a terminal line
def const UNSHOWN as string init '[\x00-\x1f\x7f-\x9f\x{200e}\x{200f}\x{202a}-\x{202e}\x{2066}-\x{2069}]';

/**
 * Throw an hl7 error.
 *
 * @param message {string} what went wrong, without the `hl7: ` prefix
 * @throws {Error} kind "hl7", always
 */
func fail(message as string) {
    throw Error{kind: "hl7", message: "hl7: " + $message};
}

/**
 * Text quoted for an error message: at most 80 characters, control and bidi
 * characters as `?`.
 *
 * @param s {string} the text
 * @return {string} the text in double quotes
 */
func shown(s as string) {
    def text as string init $s;
    if (len($text) > 80) {
        $text = $text[..80] + "...";
    }
    return "\"" + regex.replace(UNSHOWN, $text, "?") + "\"";
}

/**
 * Refuse an int outside a range.
 *
 * @param value {int} the value
 * @param low {int} the smallest allowed
 * @param high {int} the largest allowed
 * @param what {string} what the value is, for the message
 * @throws {Error} kind "hl7" when the value is outside the range
 */
func checkRange(value as int, low as int, high as int, what as string) {
    if ($value < $low or $value > $high) {
        fail(io.sprintf("%s must be %d to %d, got %d", $what, $low, $high, $value));
    }
}

