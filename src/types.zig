const std = @import("std");
const net = std.net;

pub const Request = struct {
    request_line: []const u8,

    headers: []const u8,

    body: []const u8,

    const Self = @This();

    pub inline fn parse(input: []const u8) Request {
        var iter = std.mem.splitSequence(u8, input, "\r\n\r\n");
        const rl_headers = iter.next().?;
        const body = iter.rest();
        var rl_headers_iter = std.mem.splitSequence(u8, rl_headers, "\r\n");
        return Request{
            .request_line = rl_headers_iter.first(),
            .headers = rl_headers_iter.rest(),
            .body = body,
        };
    }

    pub inline fn method(self: Self) []const u8 {
        var iter = std.mem.splitScalar(u8, self.request_line, ' ');

        return iter.first();
    }

    pub inline fn target(self: Self) ?[]const u8 {
        var iter = std.mem.splitScalar(u8, self.request_line, ' ');

        _ = iter.first();

        return iter.next();
    }

    pub inline fn get_header(self: Self, needle: []const u8) []const u8 {
        var iter = std.mem.splitSequence(u8, self.headers, "\r\n");

        while (iter.next()) |header| {
            var headerSplit = std.mem.splitSequence(u8, header, ": ");

            if (std.mem.eql(u8, headerSplit.first(), needle)) {
                return headerSplit.rest();
            }
        }

        return "";
    }
};

pub const Response = struct {
    status: []const u8,
    headers: []const u8,
    body: []const u8,
    compressGzip: bool,
    writer: net.Stream.Writer,
    allocator: std.mem.Allocator,
    keep_alive: bool,
    const Self = @This();
    pub inline fn init(a: std.mem.Allocator, w: net.Stream.Writer) Response {
        return Response{
            .status = "",
            .headers = "",
            .body = "",
            .compressGzip = false,
            .writer = w,
            .allocator = a,
            .keep_alive = true,
        };
    }
    pub inline fn deinit(self: *Self) void {
        if (self.headers.len > 0) self.allocator.free(self.headers);
        if (self.body.len > 0 and self.compressGzip) self.allocator.free(self.body);
    }
    pub inline fn set_status(self: *Self, str: []const u8) void {
        self.status = str;
    }
    pub inline fn add_header(self: *Self, name: []const u8, val: []const u8) void {
        const new_header = std.fmt.allocPrint(self.allocator, "{s}{s}: {s}\r\n", .{ self.headers, name, val }) catch return self.handleErr();
        if (self.headers.len > 0) self.allocator.free(self.headers);
        self.headers = new_header;
    }
    pub inline fn set_body(self: *Self, str: []const u8) void {
        if (self.compressGzip) {
            var buf = std.ArrayList(u8).init(self.allocator);
            var strBuf = std.io.fixedBufferStream(str);
            std.compress.gzip.compress(strBuf.reader(), buf.writer(), .{}) catch return self.handleErr();
            self.body = buf.toOwnedSlice() catch return self.handleErr();
        } else {
            self.body = str;
        }
        const iStr = std.fmt.allocPrint(self.allocator, "{d}", .{self.body.len}) catch return self.handleErr();
        defer self.allocator.free(iStr);
        self.add_header("Content-Length", iStr);
    }

    pub inline fn write(self: *Self, writer: net.Stream.Writer) void {
        if (!self.keep_alive) {
            self.add_header("Connection", "close");
        }
        std.fmt.format(writer, "HTTP/1.1 {s}\r\n{s}\r\n{s}", .{ self.status, self.headers, self.body }) catch return self.handleErr();
    }

    pub inline fn notFound(self: Self) void {
        self.writer.writeAll("HTTP/1.1 404 Not Found\r\n\r\n") catch return self.handleErr();
    }

    pub inline fn handleErr(self: Self) void {
        self.writer.writeAll("HTTP/1.1 500 Internal Server Error\r\n\r\n") catch return;
    }
};

pub const Config = struct {
    fileDir: ?[]const u8,
    pub inline fn parse() Config {
        var fileDir: ?[]const u8 = null;
        var args = std.process.args();
        const alloc = std.heap.page_allocator;
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--directory")) {
                if (args.next()) |dir| {
                    fileDir = std.fs.cwd().realpathAlloc(alloc, dir) catch unreachable;
                }
            }
        }
        return Config{
            .fileDir = fileDir,
        };
    }
};
