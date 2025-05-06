const std = @import("std");
const stdout = std.io.getStdOut().writer();
const net = std.net;
const types = @import("types.zig");

const Config = types.Config;
const Request = types.Request;
const Response = types.Response;

pub fn handleConn(allocator: std.mem.Allocator, config: Config, conn: net.Server.Connection) void {
    defer conn.stream.close();
    const writer = conn.stream.writer();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();

    while (true) {
        var tmp_buf: [1024]u8 = undefined;
        const read = conn.stream.read(&tmp_buf) catch |err| {
            std.debug.print("Read error: {}\n", .{err});
            return;
        };
        if (read == 0) break;
        buf.appendSlice(tmp_buf[0..read]) catch return;

        while (true) {
            const req_len = findRequestLength(buf.items) orelse break;
            if (buf.items.len < req_len) break;

            const req = Request.parse(buf.items[0..req_len]);
            const keep_alive = handleSingleRequest(allocator, req, config, writer);
            buf.replaceRange(0, req_len, &.{}) catch unreachable;
            if (!keep_alive) {
                return;
            }
        }
    }
}

pub fn handlePost(allocator: std.mem.Allocator, config: Config, writer: net.Stream.Writer, req: Request) void {
    var res = Response.init(allocator, writer);
    defer res.deinit();
    const target = req.target() orelse return res.handleErr();

    if (std.mem.startsWith(u8, target, "/files/")) {
        if (config.fileDir) |dir| {
            const path = std.fs.path.join(allocator, &.{ dir, target[7..] }) catch return res.handleErr();
            defer allocator.free(path);
            if (std.fs.path.dirname(path)) |parent_dir| {
                std.fs.makeDirAbsolute(parent_dir) catch |err| {
                    if (err != error.PathAlreadyExists) return res.handleErr();
                };
            }
            const file = std.fs.createFileAbsolute(path, .{}) catch return res.handleErr();
            defer file.close();
            file.writeAll(req.body) catch return res.handleErr();
            res.set_status("201 Created");
        } else return res.notFound();
    } else return res.notFound();
    res.write(writer);
}

pub fn handleGet(allocator: std.mem.Allocator, config: Config, writer: net.Stream.Writer, req: Request) void {
    var res = Response.init(allocator, writer);
    defer res.deinit();

    if (std.mem.containsAtLeast(u8, req.get_header("Accept-Encoding"), 1, "gzip")) {
        res.add_header("Content-Encoding", "gzip");
        res.compressGzip = true;
    }

    const t = req.target();
    if (t == null) return res.handleErr();
    const target = t.?;

    res.keep_alive = !std.mem.eql(u8, req.get_header("Connection"), "close");
    if (!res.keep_alive) {
        res.add_header("Connection", req.get_header("Connection"));
    }
    if (std.mem.eql(u8, target, "/")) {
        res.set_status("200 OK");
    } else if (std.mem.startsWith(u8, target, "/echo/")) {
        res.set_status("200 OK");
        res.add_header("Content-Type", "text/plain");
        const str = target[6..];
        res.set_body(str);
    } else if (std.mem.eql(u8, target, "/user-agent")) {
        res.set_status("200 OK");
        res.add_header("Content-Type", "text/plain");
        const str = req.get_header("User-Agent");
        res.set_body(str);
    } else if (std.mem.startsWith(u8, target, "/files/")) {
        if (config.fileDir) |dir| {
            const path = std.fs.path.join(allocator, &.{ dir, target[7..] }) catch return res.handleErr();
            defer allocator.free(path);
            const file = std.fs.openFileAbsolute(path, .{}) catch |err| return {
                if (err == error.FileNotFound) {
                    return res.notFound();
                } else {
                    return res.handleErr();
                }
            };
            res.set_status("200 OK");
            res.add_header("Content-Type", "application/octet-stream");
            const str = file.readToEndAlloc(allocator, 4096) catch return res.handleErr();
            res.set_body(str);
        } else return res.notFound();
    } else return res.notFound();
    res.write(writer);
}

pub inline fn handleSingleRequest(alloc: std.mem.Allocator, req: Request, config: Config, writer: net.Stream.Writer) bool {
    var res = Response.init(alloc, writer);
    defer res.deinit();
    res.keep_alive = !std.mem.eql(u8, req.get_header("Connection"), "close");
    if (!res.keep_alive) {
        res.add_header("Connection", req.get_header("Connection"));
    }

    if (std.mem.eql(u8, req.method(), "GET")) {
        handleGet(alloc, config, writer, req);
    } else if (std.mem.eql(u8, req.method(), "POST")) {
        handlePost(alloc, config, writer, req);
    } else {
        res.set_status("405 Method Not Allowed");
        writer.writeAll("HTTP/1.1 405 Method Not Allowed\r\n\r\n") catch res.handleErr();
        res.write(writer);
    }

    return res.keep_alive;
}

pub inline fn findRequestLength(data: []const u8) ?usize {
    const headers_end = std.mem.indexOf(u8, data, "\r\n\r\n") orelse return null;
    const headers = data[0..headers_end];

    var content_length: usize = 0;
    var headers_iter = std.mem.splitSequence(u8, headers, "\r\n");
    while (headers_iter.next()) |header| {
        if (std.mem.startsWith(u8, header, "Content-Length: ")) {
            const content_length_str = header["Content-Length: ".len..];
            content_length = std.fmt.parseInt(usize, content_length_str, 10) catch 0;
            break;
        }
    }
    const total_length = headers_end + 4 + content_length;
    return if (data.len >= total_length) total_length else null;
}
