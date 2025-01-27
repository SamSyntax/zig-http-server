const std = @import("std");
const net = std.net;
const flags = @import("flags");
const fs = std.fs;

const Header = struct {
    name: []const u8,
    value: []const u8,
    content_type: []const u8,
    content_length: usize,
    accept_encoding: []const u8,
};
const HttpResponse = struct {
    method: []const u8,
    status_code: u32,
    path: []const u8,
    version: []const u8,
    body: []const u8,
    host: []const u8,
    user_agent: []const u8,
    headers: Header,
};

const Options = struct {
    directory: ?[]const u8 = null,
};

const ParseError = error{
    MissingValueForDirectory,
    ErrorParsing,
};

fn parseFlags() !Options {
    var opts = Options{ .directory = null };
    var arg_iter = std.process.args();
    _ = arg_iter.next();

    while (true) {
        const arg = arg_iter.next();
        if (arg == null) {
            break;
        }

        if (std.mem.eql(u8, arg.?, "--directory")) {
            const next_arg = arg_iter.next() orelse return ParseError.MissingValueForDirectory;
            opts.directory = next_arg;
        } else {
            return ParseError.ErrorParsing;
        }
    }

    return opts;
}
pub fn bytesToHex(data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const bytes_per_line = 8;
    const hex_chars_per_byte = 2;
    const spaces_per_line = bytes_per_line - 1;
    const newline_char = 1;
    const total_lines = (data.len + bytes_per_line - 1) / bytes_per_line;
    const total_length = (data.len * hex_chars_per_byte) + (total_lines * spaces_per_line) + (total_lines * newline_char);

    var hex = try allocator.alloc(u8, total_length);
    var index: usize = 0;
    for (data, 0..) |byte, i| {
        if (i > 0 and i % bytes_per_line != 0) {
            hex[index] = ' ';
            index += 1;
        }
        _ = try std.fmt.bufPrint(hex[index .. index + 2], "{x:0>2}", .{byte});
        index += 2;
        if ((i + 1) % bytes_per_line == 0 and i + 1 != data.len) {
            hex[index] = '\n';
            index += 1;
        }
    }

    std.debug.print("Output from parseToHex: {s}\n", .{hex}); // Debug: Print output
    return hex;
}
pub fn zipVal(body: []const u8, alloc: std.mem.Allocator) ![]u8 {
    var compressed = std.ArrayList(u8).init(alloc);
    defer compressed.deinit();

    var gzip = try std.compress.gzip.compressor(compressed.writer(), .{});
    try gzip.writer().writeAll(body);
    try gzip.finish();

    const res = compressed.toOwnedSlice();

    return res;
}

pub fn parseToHex(body: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const bytes_per_line = 8;
    const hex_chars_per_byte = 2;
    const spaces_per_line = bytes_per_line - 1;
    const newline_char = 1;
    const total_lines = (body.len + bytes_per_line - 1) / bytes_per_line;
    const total_length = (body.len * hex_chars_per_byte) + (total_lines * spaces_per_line) + (total_lines * newline_char);

    var hex = try alloc.alloc(u8, total_length);
    var index: usize = 0;
    for (body, 0..) |byte, i| {
        if (i > 0 and i % bytes_per_line != 0) {
            hex[index] = ' ';
            index += 1;
        }
        _ = try std.fmt.bufPrint(hex[index .. index + 2], "{x:0>2}", .{byte});
        index += 2;
        if ((i + 1) % bytes_per_line == 0 and i + 1 != body.len) {
            hex[index] = '\n';
            index += 1;
        }
    }
    std.debug.print("test: {any}\n", .{hex});
    return hex;
}

pub fn concatWithFormat(allocator: std.mem.Allocator, response: *HttpResponse) ![]u8 {
    try getValidEncoding("gzip", response);
    switch (response.status_code) {
        200 => {
            std.debug.print("Any: {s}\n", .{response.body});
            if (std.mem.startsWith(u8, response.path, "/echo")) {
                if (response.headers.accept_encoding.len == 0) {
                    std.debug.print("Enc: {s}, body: {s}\n", .{ response.headers.accept_encoding, response.body });
                    return try std.fmt.allocPrint(allocator, "{s} 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n\r\n{s}", .{
                        response.version,
                        response.headers.content_type,
                        response.headers.content_length,
                        response.body,
                    });
                } else if (std.mem.eql(u8, response.headers.accept_encoding, "gzip")) {
                    std.debug.print("Enc: {s}, body: {s}\n", .{ response.headers.accept_encoding, response.body });
                    return try std.fmt.allocPrint(allocator, "{s} 200 OK\r\nContent-Type: {s}\r\nContent-Encoding: {s}\r\nContent-Length: {d}\r\n\r\n{s}", .{
                        response.version,
                        response.headers.content_type,
                        response.headers.accept_encoding,
                        response.headers.content_length,
                        response.body,
                    });
                } else {
                    return try std.fmt.allocPrint(allocator, "{s} 200 OK\r\nContent-Type: {s}\r\nContent-Encoding: {s}\r\nContent-Length: {d}\r\n\r\n{s}", .{
                        response.version,
                        response.headers.content_type,
                        response.headers.accept_encoding,
                        response.headers.content_length,
                        response.body,
                    });
                }
            } else {
                return try std.fmt.allocPrint(allocator, "{s} 200 OK\r\nContent-Type: {s}\r\nContent-Encoding: {s}\r\nContent-Length: {d}\r\n\r\n{s}", .{
                    response.version,
                    response.headers.content_type,
                    response.headers.accept_encoding,
                    response.headers.content_length,
                    response.body,
                });
            }
        },
        404 => {
            const res = try std.fmt.allocPrint(allocator, "HTTP/1.1 404 Not Found\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n\r\n{s}", .{
                response.headers.content_type,
                response.headers.content_length,
                response.body,
            });
            return res;
        },
        201 => {
            const res = try std.fmt.allocPrint(allocator, "HTTP/1.1 {d} Created\r\n\r\n", .{
                response.status_code,
            });
            return res;
        },
        500 => {
            const res = try std.fmt.allocPrint(allocator, "HTTP/1.1 500 Internal Server Error\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n\r\n{s}", .{
                response.headers.content_type,
                response.headers.content_length,
                response.body,
            });
            return res;
        },
        else => {
            const res = try std.fmt.allocPrint(allocator, "HTTP/1.1 400 Bad Request\r\n\r\n", .{});
            return res;
        },
    }
}
pub fn WriteResponse(stream: net.Stream, response: *HttpResponse, allocator: std.mem.Allocator) !void {
    const res = try concatWithFormat(allocator, response);
    defer allocator.free(res);
    try stream.writeAll(res);
}
pub fn getValidEncoding(encoding: []const u8, encoding_header: *HttpResponse) !void {
    var encs = std.mem.splitScalar(u8, encoding_header.headers.accept_encoding, ',');
    var counter: u8 = 0;
    while (true) {
        const enc = encs.next();
        if (enc == null) {
            break;
        }
        if (std.mem.eql(u8, std.mem.trim(u8, enc.?, " "), encoding)) {
            encoding_header.headers.accept_encoding = std.mem.trim(u8, enc.?, " ");
            counter += 1;
        } else {
            continue;
        }
    }
    if (counter == 0) {
        encoding_header.headers.accept_encoding = "";
    }
    std.debug.print("Set encoding: {s}\n", .{encoding_header.headers.accept_encoding});
}

fn getHeaderValue(list: *const std.ArrayList(Header), header_name: []const u8) ?[]const u8 {
    for (list.items) |hdr| {
        if (std.mem.eql(u8, hdr.name, header_name)) {
            return hdr.value;
        }
    }

    return null;
}

pub fn copyDirEntry(alloc: std.mem.Allocator, dir: fs.Dir, entry: fs.Dir.Walker.Entry) !fs.Dir.Walker.Entry {
    const path = try alloc.dupeZ(u8, entry.path);
    const basename = try alloc.dupeZ(u8, entry.basename);
    return fs.Dir.Walker.Entry{
        .path = path,
        .basename = basename,
        .kind = entry.kind,
        .dir = dir,
    };
}

pub fn WriteFile(content: []const u8, file_name: []const u8, directory: []const u8, alloc: std.mem.Allocator) !void {
    const cwd = fs.cwd();
    const file = try std.fs.Dir.createFile(cwd, try fs.path.join(alloc, &[_][]const u8{ directory, file_name }), .{});
    defer file.close();
    try file.writeAll(content);
}

pub fn fetchFile(file_name: []const u8, alloc: std.mem.Allocator, directory: []const u8) ![]u8 {
    var content = std.ArrayList(u8).init(alloc);
    defer content.deinit();
    const full_path = try fs.path.join(alloc, &[_][]const u8{ directory, file_name });
    defer alloc.free(full_path);

    const file = fs.cwd().openFile(full_path, .{}) catch |err| {
        if (err == fs.File.OpenError.FileNotFound) {
            return error.FileNotFound;
        }
        return err;
    };
    defer file.close();
    const reader = file.reader();
    try reader.readAllArrayList(&content, std.math.maxInt(usize));

    const file_content = try content.toOwnedSlice();
    return file_content;
}

pub fn handleConn(conn: net.Stream, opts: Options) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    defer conn.close();

    const stdout = std.io.getStdOut().writer();
    var buf: [1024]u8 = undefined;
    const n = try conn.read(buf[0..]);

    if (n == 0) {
        return;
    }
    const request_data = buf[0..n];

    const maybe_newline_index = std.mem.indexOfScalar(u8, request_data, '\n');
    const end_index = if (maybe_newline_index) |idx| idx else n;

    var request_line: []const u8 = buf[0..end_index];
    if (request_line.len > 0 and request_line[request_line.len - 1] == '\r') {
        request_line = request_line[0 .. request_line.len - 1];
    }

    var cursor = end_index + 1;
    var tokens_iter = std.mem.tokenizeScalar(u8, request_line, ' ');

    const method_opt = tokens_iter.next();
    const path_opt = tokens_iter.next();
    const version_opt = tokens_iter.next();

    if (method_opt == null or path_opt == null or version_opt == null) {
        var bad_request = HttpResponse{
            .status_code = 400,
            .method = "",
            .path = "",
            .version = "",
            .body = "Bad Request",
            .host = "",
            .user_agent = "",
            .headers = Header{
                .name = "",
                .value = "",
                .content_type = "text/plain",
                .accept_encoding = "",
                .content_length = "Bad Request".len,
            },
        };
        try WriteResponse(conn, &bad_request, alloc);
        return;
    }

    const method = method_opt.?;
    const path = path_opt.?;
    const version = version_opt.?;

    var response = HttpResponse{
        .status_code = 200,
        .version = version,
        .host = "localhost",
        .user_agent = "curl",
        .path = path,
        .body = "",
        .method = method,
        .headers = Header{
            .content_type = "text/plain",
            .content_length = 0,
            .accept_encoding = "",
            .value = "",
            .name = "",
        },
    };

    if (std.mem.eql(u8, path, "/")) {
        response.status_code = 200;
    } else if (std.mem.startsWith(u8, path, "/echo")) {
        const echo_content = path["/echo/".len..];
        const compressed_body = try zipVal(echo_content, alloc);
        defer alloc.free(compressed_body);

        const hex_body = try bytesToHex(compressed_body, alloc);
        defer alloc.free(hex_body);

        response.body = try alloc.dupe(u8, compressed_body);
        response.headers.content_length = compressed_body.len;
    } else if (std.mem.eql(u8, path, "/user-agent")) {
        response.body = response.user_agent;
        response.headers.content_length = response.user_agent.len;
    } else if (std.mem.startsWith(u8, path, "/files") and std.mem.eql(u8, method, "GET")) {
        const filename = path["/files/".len..];
        if (opts.directory) |dir| {
            const content = fetchFile(filename, alloc, dir) catch |err| {
                if (err == error.FileNotFound) {
                    response.status_code = 404;
                    response.body = "File not found";
                    response.headers.content_length = "File not found".len;
                } else {
                    response.status_code = 500;
                    response.body = "Internal Server Error";
                    response.headers.content_length = "Internal Server Error".len;
                }
                try WriteResponse(conn, &response, alloc);
                return;
            };
            defer alloc.free(content);
            response.body = try alloc.dupe(u8, content);
            response.status_code = 200;
            response.headers.content_type = "application/octet-stream";
            response.headers.content_length = content.len;
        } else {
            response.status_code = 400;
            response.body = "Directory not specified";
            response.headers.content_length = "Directory not specified".len;
        }
    } else if (std.mem.eql(u8, method, "POST") and std.mem.startsWith(u8, path, "/files")) {
        const filename = path["/files/".len..];
        response.status_code = 201;
        response.headers.content_type = "application/octet-stream\r\n\r\n";
        const body_start = std.mem.indexOf(u8, buf[0..n], "\r\n\r\n");
        response.body = buf[body_start.? + "\r\n\r\n".len .. n];
        try WriteFile(response.body, filename, opts.directory.?, alloc);
        std.debug.print("Req body:{s}\n", .{response.body});
        try WriteResponse(conn, &response, alloc);
    } else {
        response.status_code = 404;
        response.body = "Not Found";
        response.headers.content_length = "Not Found".len;
    }

    var headers_list = std.ArrayList(Header).init(std.heap.page_allocator);
    defer headers_list.deinit();

    while (cursor < request_data.len) {
        if (request_data.len == 0) {
            break;
        }
        const maybe_newline_end = std.mem.indexOfScalar(u8, request_data[cursor..], '\n');
        if (maybe_newline_end == null) {
            break;
        }
        const line_end = cursor + maybe_newline_end.?;

        var header_line: []u8 = request_data[cursor..line_end];
        if (header_line.len > 0 and header_line[header_line.len - 1] == '\r') {
            header_line = header_line[0 .. header_line.len - 1];
        }
        cursor = line_end + 1;

        if (header_line.len == 0) {
            break;
        }
        const maybe_colon_index = std.mem.indexOfScalar(u8, header_line, ':');
        if (maybe_colon_index == null) {
            continue;
        }
        const colon_pos = maybe_colon_index.?;

        const name_slice: []u8 = header_line[0..colon_pos];
        const value_slice: []u8 = header_line[colon_pos + 1 ..];

        const trimmed_name_slice = std.mem.trim(u8, name_slice, " ");
        const trimmed_value_slice = std.mem.trim(u8, value_slice, " ");

        try headers_list.append(Header{
            .content_length = response.headers.content_length,
            .content_type = response.headers.content_type,
            .name = trimmed_name_slice,
            .value = trimmed_value_slice,
            .accept_encoding = response.headers.accept_encoding,
        });
    }

    for (headers_list.items) |hdr| {
        try stdout.print("Header {s} => {s}\n", .{ hdr.name, hdr.value });
    }

    const ua = getHeaderValue(&headers_list, "User-Agent");
    if (ua) |agent| {
        response.user_agent = agent;
    }

    const encoding = getHeaderValue(&headers_list, "Accept-Encoding");
    if (encoding) |enc| {
        std.debug.print("Found encoding: {s}\n", .{enc});
        response.headers.accept_encoding = enc;
    }
    if (std.mem.startsWith(u8, response.path, "/user-agent")) {
        response.body = response.user_agent;
        response.headers.content_length = response.user_agent.len;
    }

    try WriteResponse(conn, &response, alloc);
    try stdout.print("Responded with status code: {d}\nPath: {s}\n", .{ response.status_code, response.path });
}
pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Logs from your program will appear here!\n", .{});
    const opts = try parseFlags();

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    while (true) {
        const conn = try listener.accept();
        var t = try std.Thread.spawn(.{}, handleConn, .{ conn.stream, opts });
        t.detach();
    }
}
