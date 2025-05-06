const std = @import("std");
const stdout = std.io.getStdOut().writer();
const handlers = @import("handlers.zig");
const types = @import("types.zig");
const net = std.net;

const Config = types.Config;
const Request = types.Request;
const Response = types.Response;

pub fn main() !void {
    const config = Config.parse();
    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_alloc.allocator();
    defer {
        if (gpa_alloc.deinit() == std.heap.Check.leak) {
            std.debug.print("Memory leak", .{});
        }
    }
    const buf = try gpa.alloc(u8, 1024);
    defer gpa.free(buf);
    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = gpa, .n_jobs = 8 });
    defer pool.deinit();
    while (true) {
        const conn = try listener.accept();
        try stdout.print("client {} connected!\n", .{conn.address.in.sa.port});
        try pool.spawn(handlers.handleConn, .{ gpa, config, conn });
    }
}
