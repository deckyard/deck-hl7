# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# hl7 - mllp: the Minimal Lower Layer Protocol over TCP. Each message is
# framed as 0x0B, the message, 0x1C 0x0D. A client sends and waits for the
# acknowledgement; a listener receives and replies, one task per connection
# in `serve`. Spliced into hl7.j via include.

/** How long to wait for an acknowledgement, or for a whole message once it began, in milliseconds: 30 s. */
export def const DEFAULT_TIMEOUT_MS as int init 30000;

/** The largest message read or sent, in bytes: 1 MiB. */
export def const DEFAULT_MAX_BYTES as int init 1048576;

# the MLLP frame: start block, end block, carriage return
def const SB as int init 11;
def const EB as int init 28;
def const CR as int init 13;

# how many bytes one read takes
def const CHUNK as int init 65536;

# how long `serve` pauses after an accept error other than the listener
# closing, in ms
def const ACCEPT_PAUSE_MS as int init 100;

/**
 * How a connection behaves. `options()` gives the defaults; set a field to
 * change one.
 *
 * @field charset {string} the codec when MSH-18 is empty: `ascii` (HL7's default), `iso-8859-1`, `utf-8`, ...
 * @field timeoutMs {int} how long to wait for an acknowledgement, and for a whole message once its first byte came: 1 to 86400000, 30000 by default
 * @field retries {int} how often `send` sends again when no acknowledgement comes: 0 to 100, 3 by default
 * @field maxBytes {int} the largest message: 1024 to 67108864 bytes, 1 MiB by default
 * @field idleMs {int} how long `serve` keeps a connection that sends nothing: 1 to 86400000, one hour by default
 */
export def struct Options {
    charset as string,
    timeoutMs as int,
    retries as int,
    maxBytes as int,
    idleMs as int
};

/**
 * An MLLP connection, from `connect` or `accept`. `close` ends it.
 *
 * @field conn {net.Conn} the socket
 * @field options {Options} how it behaves
 * @field pending {channel of bytes} bytes read past the last message, for the next one
 * @field sent {channel of string} the control ID `send` sent last, so a late acknowledgement of it is skipped
 */
export def struct Connection {
    conn as net.Conn,
    options as Options,
    pending as channel of bytes,
    sent as channel of string
};

/**
 * The default options.
 *
 * @return {Options} ASCII, 30 s, 3 retries, 1 MiB, one hour idle
 * @example
 *   def o as hl7.Options init hl7.options();
 *   $o.charset = "iso-8859-1";
 */
export func options() {
    return Options{
        charset: "ascii",
        timeoutMs: DEFAULT_TIMEOUT_MS,
        retries: 3,
        maxBytes: DEFAULT_MAX_BYTES,
        idleMs: 3600000
    };
}

/**
 * Refuse options out of range or an unknown character set.
 *
 * @param o {Options} the options
 */
func checkOptions(o as Options) {
    checkRange($o.timeoutMs, 1, 86400000, "the timeout");
    checkRange($o.retries, 0, 100, "the retries");
    checkRange($o.maxBytes, 1024, 67108864, "the largest message");
    checkRange($o.idleMs, 1, 86400000, "the idle time");
    checkCodec($o.charset);
}

/**
 * A connection on a socket.
 *
 * @param conn {net.Conn} the socket
 * @param o {Options} the options
 * @return {Connection} the connection
 */
func connectionOf(conn as net.Conn, o as Options) {
    return Connection{conn: $conn, options: $o, pending: channel.make(1), sent: channel.make(1)};
}

/**
 * Connect to an MLLP listener, as a client.
 *
 * @param address {string} `host:port`
 * @param o {Options} the options
 * @return {Connection} the connection
 * @throws {Error} kind "hl7" when the options are invalid or the address is malformed; kind "timeout" when it cannot be reached within the timeout
 * @throws {net.NetError} kind "net" when the network fails (refused, unreachable, DNS)
 * @example
 *   def c as hl7.Connection init hl7.connect("10.0.0.30:2575", hl7.options());
 */
export func connect(address as string, o as Options) {
    checkOptions($o);
    try {
        return connectionOf(
            net.connectWith($address, net.ConnectOptions{timeoutMs: $o.timeoutMs}),
            $o);
    } catch (e) {
        if (isGeneric($e.kind)) {
            throw $e;
        }
        fail("cannot reach " + shown($address) + ": " + $e.message);
    }
}

/**
 * Listen for MLLP clients.
 *
 * @param address {string} `host:port`, `:2575` for every address
 * @return {net.Listener} the listener, for `accept` or `serve`; `net.close` stops it
 * @throws {Error} kind "hl7" when the address cannot be bound
 * @throws {net.NetError} kind "net" when the network refuses it
 */
export func listen(address as string) {
    try {
        return net.listen($address);
    } catch (e) {
        if (isGeneric($e.kind)) {
            throw $e;
        }
        fail("cannot listen on " + shown($address) + ": " + $e.message);
    }
}

/**
 * Wait for a client to connect.
 *
 * @param listener {net.Listener} from `listen`
 * @param o {Options} the options
 * @return {Connection} the connection
 * @throws {Error} kind "hl7" when the options are invalid or the listener fails; kind "closed" when it is closed
 * @throws {net.NetError} kind "net" when the network fails
 */
export func accept(listener as net.Listener, o as Options) {
    checkOptions($o);
    try {
        return connectionOf(net.accept($listener), $o);
    } catch (e) {
        if (isGeneric($e.kind)) {
            throw $e;
        }
        fail("accept: " + $e.message);
    }
}

/**
 * Close a connection. Closing one that is already closed does nothing.
 *
 * @param c {Connection} the connection
 */
export func close(c as Connection) {
    try {
        net.close($c.conn);
    } catch (e) {
        return null;
    }
}

/**
 * A message framed for MLLP.
 *
 * @param m {Message} the message
 * @param o {Options} the options
 * @return {bytes} 0x0B, the message, 0x1C 0x0D
 */
func framed(m as Message, o as Options) {
    def body as bytes init encodeBytes($m, $o.charset);
    if (len($body) > $o.maxBytes) {
        fail(io.sprintf("the message is larger than %d bytes", $o.maxBytes));
    }
    def out as bytes;
    $out[] = SB;
    $out = binary.concat($out, $body);
    $out[] = EB;
    $out[] = CR;
    return $out;
}

/**
 * Write bytes, within the timeout.
 *
 * @param c {Connection} the connection
 * @param data {bytes} the bytes
 */
func write(c as Connection, data as bytes) {
    try {
        net.setWriteDeadline($c.conn, $c.options.timeoutMs);
        net.writeBytes($c.conn, $data);
    } catch (e) {
        if (isGeneric($e.kind)) {
            throw $e;
        }
        fail("cannot send: " + $e.message);
    }
}

/**
 * Read what the socket has, waiting at most a number of milliseconds.
 *
 * @param c {Connection} the connection
 * @param ms {int} how long to wait
 * @return {list of bytes} the bytes, or nothing when none came in time
 * @throws {Error} kind "closed" when the connection closed; kind "hl7" when it failed otherwise
 * @throws {net.NetError} kind "net" when the network fails (a reset)
 */
func readSome(c as Connection, ms as int) {
    def out as list of bytes init [];
    def chunk as bytes;
    try {
        net.setReadDeadline($c.conn, $ms);
        $chunk = net.readBytes($c.conn, CHUNK);
        net.setReadDeadline($c.conn, 0);
    } catch (e) {
        if ($e.kind == "timeout") {
            return $out;
        }
        if (isGeneric($e.kind)) {
            throw $e;
        }
        fail("the connection failed: " + $e.message);
    }
    if (len($chunk) == 0) {
        failClosed("the connection closed");
    }
    $out[] = $chunk;
    return $out;
}

/**
 * The milliseconds since a moment.
 *
 * @param start {time.Time} the moment
 * @return {int} the milliseconds
 */
func since(start as time.Time) {
    return time.milliseconds(time.sub(time.now(), $start));
}

/**
 * The next MLLP frame's content. The whole frame must arrive within the
 * timeout once its first byte came, however it is split.
 *
 * @param c {Connection} the connection
 * @param waitMs {int} how long to wait for it to begin
 * @return {list of bytes} the message's bytes, or nothing when none began in time
 * @throws {Error} kind "hl7" when bytes come before the start block; kind "limit" when the message grows past `maxBytes`; kind "timeout" when it does not arrive whole within the timeout; kind "closed" when the connection closed
 * @throws {net.NetError} kind "net" when the network fails (a reset, say)
 */
func readFrame(c as Connection, waitMs as int) {
    def o as Options init $c.options;
    def none as list of bytes init [];
    def endMark as bytes;
    $endMark[] = EB;
    $endMark[] = CR;
    def parts as list of bytes init [];
    def total as int init 0;
    def last as int init -1;
    def begun as bool init false;
    def start as time.Time init time.now();
    def chunk as bytes;
    if (channel.len($c.pending) > 0) {
        $chunk = channel.recv($c.pending);
    }
    while (true) {
        if (len($chunk) == 0) {
            def ms as int init $waitMs;
            if ($begun) {
                $ms = $o.timeoutMs - since($start);
                if ($ms <= 0) {
                    failTimeout(io.sprintf(
                        "a message did not arrive whole within %d ms",
                        $o.timeoutMs));
                }
            }
            def got as list of bytes init readSome($c, $ms);
            if (len($got) == 0) {
                if (not $begun) {
                    return $none;
                }
                failTimeout(io.sprintf("a message did not arrive whole within %d ms", $o.timeoutMs));
            }
            $chunk = $got[0];
        }
        if (not $begun) {
            if ($chunk[0] != SB) {
                fail(io.sprintf(
                    "a byte 0x%s came where a message starts (0x0B)",
                    strings.upper(io.sprintf("%d|base=16|pad=2|fill=0", $chunk[0]))));
            }
            $begun = true;
            $start = time.now();
        }
        def end as int init binary.indexOf($chunk, $endMark);
        def split as bool init $last == EB and $chunk[0] == CR;
        if ($split or $end >= 0) {
            def rest as bytes;
            if ($split) {
                $rest = $chunk[1..];
                $total = $total - 1;
            } else {
                $parts[] = $chunk[..$end];
                $total = $total + $end;
                $rest = $chunk[$end + 2..];
            }
            if ($total > $o.maxBytes + 1) {
                failLimit(io.sprintf("a message larger than %d bytes", $o.maxBytes));
            }
            if (len($rest) > 0) {
                channel.send($c.pending, $rest);
            }
            def whole as bytes init binary.join($parts);
            return [$whole[1..$total]];
        }
        $total = $total + len($chunk);
        if ($total > $o.maxBytes + 3) {
            failLimit(io.sprintf("a message larger than %d bytes", $o.maxBytes));
        }
        $last = $chunk[len($chunk) - 1];
        $parts[] = $chunk;
        def empty as bytes;
        $chunk = $empty;
    }
}

/**
 * Send a message and wait for its acknowledgement. When none comes within
 * the timeout the message is sent again, up to `retries` times. The reply
 * must be an acknowledgement (one MSA) of this message's control ID; its
 * code (MSA-1: `AA`, `AE`, `AR`, ...) is the caller's to judge. A late or
 * repeated acknowledgement of the message sent before on this connection is
 * skipped, so a resend does not put the connection out of step.
 *
 * @param c {Connection} the connection
 * @param m {Message} the message, with a control ID in MSH-10
 * @return {Message} the acknowledgement
 * @throws {Error} kind "hl7" when the message has no control ID or does not encode, the reply is not an acknowledgement of this message, or the connection fails; kind "timeout" when no acknowledgement comes after the retries; kind "closed" when the peer closes
 * @throws {net.NetError} kind "net" when the network fails (a reset, say)
 * @example
 *   def reply as hl7.Message init hl7.send($c, $m);
 *   if (hl7.get($reply, "MSA-1") != "AA") {
 *       io.printf("refused: %s\n", hl7.get($reply, "MSA-3"));
 *   }
 */
export func send(c as Connection, m as Message) {
    def id as string init get($m, "MSH-10");
    if ($id == "") {
        fail("the message has no control ID (MSH-10)");
    }
    def previous as string init "";
    if (channel.len($c.sent) > 0) {
        $previous = channel.recv($c.sent);
    }
    channel.send($c.sent, $id);
    def frame as bytes init framed($m, $c.options);
    def attempts as int init 0;
    while (true) {
        write($c, $frame);
        $attempts = $attempts + 1;
        def start as time.Time init time.now();
        def left as int init $c.options.timeoutMs;
        while ($left > 0) {
            def got as list of bytes init readFrame($c, $left);
            if (len($got) == 0) {
                $left = 0;
            } else {
                def reply as Message init parseBytes($got[0], $c.options.charset);
                if ($previous == "" or $previous == $id or not isAckOf($reply, $previous)) {
                    return acknowledgementOf($reply, $id);
                }
                $left = $c.options.timeoutMs - since($start);
            }
        }
        if ($attempts > $c.options.retries) {
            failTimeout(io.sprintf(
                "no acknowledgement within %d ms, %d times",
                $c.options.timeoutMs,
                $attempts));
        }
    }
}

/**
 * Whether a reply is an acknowledgement of a control ID.
 *
 * @param reply {Message} the reply
 * @param id {string} the control ID
 * @return {bool} true when it has one MSA whose MSA-2 is the ID
 */
func isAckOf(reply as Message, id as string) {
    return count($reply, "MSA") == 1 and get($reply, "MSA-2") == $id;
}

/**
 * Check that a reply acknowledges a message.
 *
 * @param reply {Message} the reply
 * @param id {string} the message's control ID
 * @return {Message} the reply
 */
func acknowledgementOf(reply as Message, id as string) {
    if (count($reply, "MSA") != 1) {
        fail("the reply is not an acknowledgement: it has no single MSA");
    }
    if (get($reply, "MSA-2") != $id) {
        fail("the reply acknowledges " + shown(get($reply, "MSA-2")) + ", not " + shown($id));
    }
    return $reply;
}

/**
 * Receive the next message.
 *
 * @param c {Connection} the connection
 * @param waitMs {int} how long to wait for one to begin: 1 to 86400000 ms
 * @return {list of Message} the message, or nothing when none began in time
 * @throws {Error} kind "hl7" when the framing is broken or the message does not parse; kind "limit" when it is over `maxBytes`; kind "timeout" when it does not arrive whole within the timeout; kind "closed" when the connection closed
 * @throws {net.NetError} kind "net" when the network fails (a reset, say)
 * @example
 *   for (def m in hl7.receive($c, 60000)) {
 *       hl7.reply($c, hl7.ack($m, "AA", "", "ACK1"));
 *   }
 */
export func receive(c as Connection, waitMs as int) {
    checkRange($waitMs, 1, 86400000, "the wait");
    def out as list of Message init [];
    def got as list of bytes init readFrame($c, $waitMs);
    if (len($got) > 0) {
        $out[] = parseBytes($got[0], $c.options.charset);
    }
    return $out;
}

/**
 * Send a reply, such as an acknowledgement, without waiting for anything.
 *
 * @param c {Connection} the connection
 * @param m {Message} the reply
 * @throws {Error} kind "hl7" when it does not encode or the connection fails
 * @throws {net.NetError} kind "net" when the network fails (a reset, say)
 */
export func reply(c as Connection, m as Message) {
    write($c, framed($m, $c.options));
}

/**
 * Serve MLLP clients until the listener is closed: each connection gets its
 * own task, which passes every message to the handler and sends back what
 * the handler returns. A handler that throws, or returns no message, is
 * answered with an `AE` acknowledgement carrying the error. A connection
 * whose input breaks the framing or does not parse, sends a message without
 * a control ID, or stays silent for `idleMs` (an hour) is closed. When the listener is
 * closed, `serve` closes every connection still open and returns once their
 * tasks ended. Other accept errors (such as running out of file
 * descriptors) pause it for 100 ms and it goes on.
 *
 * @param listener {net.Listener} from `listen`; `net.close` from another task stops `serve`
 * @param o {Options} the options
 * @param handler {func} `func(m as Message)` returning the reply `Message`, usually from `ack`
 * @throws {Error} kind "hl7" when the options are invalid
 * @example
 *   func onMessage(m as hl7.Message) {
 *       return hl7.ack($m, "AA", "", "ACK" + hl7.get($m, "MSH-10"));
 *   }
 *   hl7.serve(hl7.listen(":2575"), hl7.options(), onMessage);
 */
export func serve(listener as net.Listener, o as Options, handler as func) {
    checkOptions($o);
    def open as list of Connection init [];
    def workers as list of task of null init [];
    def serving as bool init true;
    while ($serving) {
        def conn as net.Conn init net.Conn{};
        def accepted as bool init false;
        try {
            $conn = net.accept($listener);
            $accepted = true;
        } catch (e) {
            if ($e.kind == "closed") {
                $serving = false;
            } else {
                time.sleep(time.fromMilliseconds(ACCEPT_PAUSE_MS));
            }
        }
        if ($accepted) {
            def c as Connection init connectionOf($conn, $o);
            def keep as list of int init live($workers);
            def stillOpen as list of Connection init [];
            def stillWorking as list of task of null init [];
            for (def i in $keep) {
                $stillOpen[] = $open[$i];
                $stillWorking[] = $workers[$i];
            }
            $open = $stillOpen;
            $workers = $stillWorking;
            $open[] = $c;
            $workers[] = spawn {
                return serveConnection($c, $handler);
            };
        }
    }
    for (def c in $open) {
        close($c);
    }
    for (def w in $workers) {
        try {
            task.waitTimeout($w, DEFAULT_TIMEOUT_MS);
        } catch (e) {
            task.discard($w);
        }
    }
    return null;
}

/**
 * The indexes of the tasks still running.
 *
 * @param workers {list of task of null} the tasks
 * @return {list of int} the indexes of those not done
 */
func live(workers as list of task of null) {
    def out as list of int init [];
    for (def i in 0..len($workers)) {
        if (not task.poll($workers[$i])) {
            $out[] = $i;
        }
    }
    return $out;
}

/**
 * Serve one connection until it closes, breaks or stays silent for
 * `idleMs`.
 *
 * @param c {Connection} the connection
 * @param handler {func} the handler
 * @return {null} when the connection ended
 */
func serveConnection(c as Connection, handler as func) {
    def open as bool init true;
    while ($open) {
        try {
            def got as list of Message init receive($c, $c.options.idleMs);
            $open = len($got) > 0;
            for (def m in $got) {
                reply($c, answer($m, $handler));
            }
        } catch (e) {
            $open = false;
        }
    }
    close($c);
    return null;
}

/**
 * The handler's reply to a message, or an `AE` acknowledgement when it
 * throws or returns something other than a message.
 *
 * @param m {Message} the message
 * @param handler {func} the handler
 * @return {Message} the reply
 * @throws {Error} kind "hl7" when the handler failed and the message has no control ID to acknowledge
 */
func answer(m as Message, handler as func) {
    try {
        def r as Message init $handler($m);
        return $r;
    } catch (e) {
        def id as string init strings.replace(uuid.v4(), "-", "")[..20];
        return ack($m, "AE", $e.message, $id);
    }
}
