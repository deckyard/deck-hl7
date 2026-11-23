# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# hl7 - white-box tests for the mllp topic. Spliced into hl7_test.j via
# include.
#
# A peer is a script run in a spawned task on a raw socket: `w <text>`
# writes the text framed (0x0B ... 0x1C 0x0D), `x <text>` writes it as is,
# `r` reads one frame into the log, `s <ms>` sleeps, `c` closes, `a` aborts
# (closes with a reset). The log is
# the frames read, CRs shown as `/`, joined by `;`.

/**
 * Options with short timers.
 *
 * @return {Options} the options
 */
func quick() {
    def o as Options init options();
    $o.timeoutMs = 300;
    $o.retries = 0;
    return $o;
}

/**
 * Text as an MLLP frame.
 *
 * @param text {string} the message
 * @return {bytes} the frame
 */
func frameText(text as string) {
    def out as bytes;
    $out[] = SB;
    $out = binary.concat($out, encoding.encode("iso-8859-1", $text));
    $out[] = EB;
    $out[] = CR;
    return $out;
}

/**
 * Run a peer script on a socket.
 *
 * @param conn {net.Conn} the socket
 * @param steps {list of string} the steps
 * @return {string} the log
 */
func play(conn as net.Conn, steps as list of string) {
    def log as list of string init [];
    def c as Connection init connectionOf($conn, quick());
    $c.options.timeoutMs = 2000;
    for (def step in $steps) {
        def verb as string init $step[..1];
        def rest as string init "";
        if (len($step) > 2) {
            $rest = $step[2..];
        }
        if ($verb == "w") {
            net.writeBytes($conn, frameText($rest));
        } elseif ($verb == "x") {
            net.writeBytes($conn, encoding.encode("iso-8859-1", $rest));
        } elseif ($verb == "r") {
            def got as list of bytes init readFrame($c, 2000);
            if (len($got) == 0) {
                $log[] = "<none>";
            } else {
                $log[] = strings.replace(encoding.decode("iso-8859-1", $got[0]), "\r", "/");
            }
        } elseif ($verb == "s") {
            time.sleep(time.fromMilliseconds(convert.toInt($rest)));
        } elseif ($verb == "a") {
            net.abort($conn);
        } else {
            net.close($conn);
        }
    }
    return strings.join($log, ";");
}

/**
 * A peer that accepts one connection on a listener and plays a script on
 * it.
 *
 * @param listener {net.Listener} the listener
 * @param steps {list of string} the steps
 * @return {task of string} the peer, whose value is the log
 */
func serverPeer(listener as net.Listener, steps as list of string) {
    return spawn {
        return play(net.accept($listener), $steps);
    };
}

# an acknowledgement of ORU
def const ORU_ACK as string init "MSH|^~\\&|EHR|HOSP|LAB|HOSP|20260312094501||ACK^R01^ACK|A1|P|2.5.1\rMSA|AA|MSG00001\r";

func testSendWaitsForItsAcknowledgement() {
    def server as net.Listener init net.listen("127.0.0.1:0");
    def p as task of string init serverPeer($server, ["r", "w " + ORU_ACK]);
    def c as Connection init connect(net.address($server), quick());
    def reply as Message init send($c, parse(ORU));
    testing.assertEqual(get($reply, "MSA-1"), "AA");
    testing.assertEqual(task.wait($p), strings.replace(ORU, "\r", "/"));
    close($c);
    close($c);
    net.close($server);
}

func testSendSendsAgainWithoutAnAcknowledgement() {
    def server as net.Listener init net.listen("127.0.0.1:0");
    def p as task of string init serverPeer($server, ["r", "r", "w " + ORU_ACK]);
    def o as Options init quick();
    $o.retries = 1;
    def c as Connection init connect(net.address($server), $o);
    testing.assertEqual(get(send($c, parse(ORU)), "MSA-2"), "MSG00001");
    testing.assertEqual(len(strings.split(task.wait($p), ";")), 2);
    def q as task of string init serverPeer($server, ["r", "s 600"]);
    def d as Connection init connect(net.address($server), quick());
    try {
        send($d, parse(ORU));
        missed("silence");
    } catch (e) {
        testing.assertEqual($e.kind, "timeout");
        testing.assertEqual($e.message, "hl7: no acknowledgement within 300 ms, 1 times");
    }
    task.wait($q);
    net.close($server);
}

# A peer that resets the connection instead of answering: the net.NetError
# reaches the caller unchanged, with its fields.
func testANetworkFailurePassesOnUnchanged() {
    def server as net.Listener init net.listen("127.0.0.1:0");
    def p as task of string init serverPeer($server, ["r", "a"]);
    def c as Connection init connect(net.address($server), quick());
    try {
        send($c, parse(ORU));
        missed("a reset");
    } catch (e) {
        testing.assertEqual($e.kind, "net");
        testing.assertEqual($e.reason, "reset");
        testing.assertEqual($e.op, "read");
        testing.assertFalse(strings.startsWith($e.message, "hl7: "));
    }
    task.wait($p);
    close($c);
    net.close($server);
}

func testSendRefusesAReplyToAnotherMessage() {
    def server as net.Listener init net.listen("127.0.0.1:0");
    def other as string init strings.replace(ORU_ACK, "MSA|AA|MSG00001", "MSA|AA|MSG00002");
    def p as task of string init serverPeer($server, ["r", "w " + $other, "r", "w " + ORU]);
    def c as Connection init connect(net.address($server), quick());
    try {
        send($c, parse(ORU));
        missed("another ID");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "hl7: the reply acknowledges \"MSG00002\", not \"MSG00001\"");
    }
    try {
        send($c, parse(ORU));
        missed("not an ACK");
    } catch (e) {
        testing.assertContains($e.message, "the reply is not an acknowledgement");
    }
    task.wait($p);
    net.close($server);
}

func testReceiveTakesFramesOneByOne() {
    def server as net.Listener init net.listen("127.0.0.1:0");
    def address as string init net.address($server);
    def p as task of string init spawn {
        def raw as net.Conn init net.connect($address, 2000);
        net.writeBytes($raw, binary.concat(frameText(ORU), frameText(ORU_ACK)));
        return play($raw, ["r", "s 500"]);
    };
    def c as Connection init accept($server, quick());
    def first as list of Message init receive($c, 2000);
    def second as list of Message init receive($c, 2000);
    testing.assertEqual(get($first[0], "MSH-10"), "MSG00001");
    testing.assertEqual(get($second[0], "MSA-1"), "AA");
    reply($c, ack($first[0], "AA", "", "ACK1"));
    testing.assertContains(task.wait($p), "MSA|AA|MSG00001");
    testing.assertEqual(len(receive($c, 50)), 0);
    close($c);
    net.close($server);
}

func testReceiveRefusesBrokenFraming() {
    def server as net.Listener init net.listen("127.0.0.1:0");
    def address as string init net.address($server);
    # the peer's step, the message, the kind and how long the peer then
    # stays: past the 300 ms timeout for the half message, briefly otherwise
    def cases as list of list of string init [
        ["x junk", "a byte 0x6A came where a message starts", "hl7", "s 50"],
        [
            "x " + convert.fromCodepoint(11) + "MSH|^~\\&|A\r",
            "a message did not arrive whole within 300 ms",
            "timeout",
            "s 600"
        ],
        ["c", "the connection closed", "closed", "s 50"],
        ["w MSH|^~\\&|A\nB\r", "control character", "hl7", "s 50"],
        ["w " + strings.replicate("x", 2000), "a message starts with MSH", "hl7", "s 50"]
    ];
    for (def k in $cases) {
        def p as task of string init spawn {
            def raw as net.Conn init net.connect($address, 2000);
            return play($raw, [$k[0], $k[3]]);
        };
        def c as Connection init accept($server, quick());
        try {
            receive($c, 1000);
            missed($k[1]);
        } catch (e) {
            testing.assertContains($e.message, $k[1]);
            testing.assertEqual($e.kind, $k[2]);
        }
        close($c);
        task.wait($p);
    }
    def big as Options init quick();
    $big.maxBytes = 1024;
    def p as task of string init spawn {
        def raw as net.Conn init net.connect($address, 2000);
        return play($raw, ["w MSH|^~\\&|" + strings.replicate("x", 3000) + "\r", "s 300"]);
    };
    def c as Connection init accept($server, $big);
    try {
        receive($c, 1000);
        missed("too big");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertEqual($e.message, "hl7: a message larger than 1024 bytes");
    }
    task.wait($p);
    try {
        send($c, parse("MSH|^~\\&|" + strings.replicate("x", 3000) + "|||||||C1\r"));
        missed("too big to send");
    } catch (e) {
        testing.assertEqual($e.kind, "hl7");
        testing.assertEqual($e.message, "hl7: the message is larger than 1024 bytes");
    }
    close($c);
    net.close($server);
}

/**
 * A handler for the serve test: acknowledges, or throws for control ID
 * `BAD`.
 *
 * @param m {Message} the message
 * @return {Message} the acknowledgement
 */
func acceptAll(m as Message) {
    if (get($m, "MSH-10") == "BAD") {
        throw Error{kind: "app", message: "cannot store"};
    }
    return ack($m, "AA", "", "ACK" + get($m, "MSH-10"));
}

func testServeAnswersEveryConnection() {
    def server as net.Listener init listen("127.0.0.1:0");
    def address as string init net.address($server);
    def o as Options init quick();
    def loop as task of null init spawn {
        serve($server, $o, acceptAll);
        return null;
    };
    def a as Connection init connect($address, $o);
    def b as Connection init connect($address, $o);
    testing.assertEqual(get(send($a, parse(ORU)), "MSH-10"), "ACKMSG00001");
    def bad as Message init set(parse(ORU), "MSH-10", "BAD");
    def refused as Message init send($b, $bad);
    testing.assertEqual(get($refused, "MSA-1"), "AE");
    testing.assertEqual(get($refused, "MSA-3"), "cannot store");
    testing.assertEqual(get(send($a, parse(ORU)), "MSA-1"), "AA");
    close($a);
    close($b);
    net.close($server);
    task.waitTimeout($loop, 2000);
}

func testOptionsAndAddressesAreChecked() {
    def bad as list of Options init [];
    def o as Options init options();
    $o.timeoutMs = 0;
    $bad[] = $o;
    $o = options();
    $o.retries = 101;
    $bad[] = $o;
    $o = options();
    $o.maxBytes = 10;
    $bad[] = $o;
    $o = options();
    $o.charset = "klingon";
    $bad[] = $o;
    for (def b in $bad) {
        try {
            connect("127.0.0.1:1", $b);
            missed("bad options");
        } catch (e) {
            testing.assertEqual($e.kind, "hl7");
        }
    }
    try {
        connect("127.0.0.1:1", quick());
        missed("nobody listening");
    } catch (e) {
        testing.assertEqual($e.kind, "net");
        testing.assertEqual($e.reason, "refused");
        testing.assertEqual($e.op, "connect");
    }
    try {
        listen("127.0.0.1:99999");
        missed("port 99999");
    } catch (e) {
        testing.assertContains($e.message, "hl7: cannot listen on");
    }
    def server as net.Listener init listen("127.0.0.1:0");
    net.close($server);
    try {
        accept($server, quick());
        missed("closed listener");
    } catch (e) {
        testing.assertEqual($e.kind, "closed");
    }
    try {
        receive(connectionOf(net.Conn{}, quick()), 0);
        missed("wait 0");
    } catch (e) {
        testing.assertContains($e.message, "the wait must be 1 to 86400000");
    }
}

func testAMessageMustArriveWholeInTime() {
    def server as net.Listener init net.listen("127.0.0.1:0");
    def address as string init net.address($server);
    def steps as list of string init ["x " + convert.fromCodepoint(11) + "MSH|^~\\&|A"];
    for (def i in 0..20) {
        $steps[] = "s 50";
        $steps[] = "x |x";
    }
    def p as task of string init spawn {
        try {
            return play(net.connect($address, 2000), $steps);
        } catch (e) {
            return "closed";
        }
    };
    def c as Connection init accept($server, quick());
    def started as time.Time init time.now();
    try {
        receive($c, 1000);
        missed("a trickle");
    } catch (e) {
        testing.assertEqual($e.kind, "timeout");
        testing.assertEqual($e.message, "hl7: a message did not arrive whole within 300 ms");
    }
    testing.assertTrue(since($started) < 800);
    close($c);
    task.wait($p);
    net.close($server);
}

func testAFrameSplitAnywhereIsRead() {
    def server as net.Listener init net.listen("127.0.0.1:0");
    def address as string init net.address($server);
    def whole as string init convert.fromCodepoint(11) + ORU + convert.fromCodepoint(28) + "\r";
    def cut as int init len($whole) - 1;
    def p as task of string init spawn {
        return play(
            net.connect($address, 2000),
            ["x " + $whole[..$cut], "s 100", "x " + $whole[$cut..], "s 300"]);
    };
    def c as Connection init accept($server, quick());
    testing.assertEqual(encode(receive($c, 1000)[0]), ORU);
    close($c);
    task.wait($p);
    net.close($server);
}

func testALateAcknowledgementIsSkipped() {
    def server as net.Listener init net.listen("127.0.0.1:0");
    def second as string init strings.replace(ORU, "MSG00001", "MSG00002");
    def secondAck as string init strings.replace(ORU_ACK, "MSA|AA|MSG00001", "MSA|AA|MSG00002");
    def p as task of string init serverPeer(
        $server,
        ["r", "r", "w " + ORU_ACK, "w " + ORU_ACK, "r", "w " + $secondAck]);
    def o as Options init quick();
    $o.retries = 1;
    def c as Connection init connect(net.address($server), $o);
    testing.assertEqual(get(send($c, parse(ORU)), "MSA-2"), "MSG00001");
    testing.assertEqual(get(send($c, parse($second)), "MSA-2"), "MSG00002");
    task.wait($p);
    close($c);
    net.close($server);
}

/**
 * A handler that returns no message.
 *
 * @param m {Message} the message
 * @return {string} not a message
 */
func wrongReply(m as Message) {
    return "ok " + get($m, "MSH-10");
}

func testServeAnswersABadHandlerAndClosesIdleConnections() {
    def server as net.Listener init listen("127.0.0.1:0");
    def address as string init net.address($server);
    def o as Options init quick();
    $o.idleMs = 300;
    def loop as task of null init spawn {
        serve($server, $o, wrongReply);
        return null;
    };
    def a as Connection init connect($address, $o);
    testing.assertEqual(get(send($a, parse(ORU)), "MSA-1"), "AE");
    time.sleep(time.fromMilliseconds(600));
    try {
        send($a, parse(strings.replace(ORU, "MSG00001", "MSG00003")));
        missed("an idle connection kept open");
    } catch (e) {
        testing.assertEqual($e.kind, "closed");
    }
    close($a);
    net.close($server);
    task.waitTimeout($loop, 2000);
}

func testServeClosesItsConnectionsWhenStopped() {
    def server as net.Listener init listen("127.0.0.1:0");
    def address as string init net.address($server);
    def loop as task of null init spawn {
        serve($server, options(), acceptAll);
        return null;
    };
    def a as Connection init connect($address, quick());
    testing.assertEqual(get(send($a, parse(ORU)), "MSA-1"), "AA");
    net.close($server);
    task.waitTimeout($loop, 2000);
    try {
        send($a, parse(strings.replace(ORU, "MSG00001", "MSG00004")));
        missed("a connection outliving serve");
    } catch (e) {
        testing.assertEqual($e.kind, "closed");
    }
    close($a);
}
