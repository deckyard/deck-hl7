# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

/**
 * White-box tests: jennifer test src/hl7_test.j
 *
 * No test needs a hospital system. The MLLP tests run the deck against a
 * peer scripted in a spawned task over a TCP socket on 127.0.0.1. The topic
 * overlays are fragments spliced in here, not standalone suites.
 */
use testing;
use time;

include "topics/core_test.j";
include "topics/segments_test.j";
include "topics/paths_test.j";
include "topics/messages_test.j";
include "topics/mllp_test.j";
