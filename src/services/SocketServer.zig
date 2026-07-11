const Self = @This();
const std = @import("std");
const Config = @import("../config/Config.zig");

allocator: std.mem.Allocator,
config: *Config,
path: []u8,
server: ?std.net.Server,
should_stop: std.atomic.Value(bool),

pub fn init(allocator: std.mem.Allocator, config: *Config) !Self {
    const runtime_dir = std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR") catch
        try allocator.dupe(u8, "/tmp");
    defer allocator.free(runtime_dir);

    const path = try std.fmt.allocPrint(allocator, "{s}/fancy-cat.sock", .{runtime_dir});
    errdefer allocator.free(path);

    // Remove a stale socket file
    std.fs.deleteFileAbsolute(path) catch {};

    const address = try std.net.Address.initUnix(path);
    const server = try address.listen(.{ .reuse_address = true });

    return .{
        .allocator = allocator,
        .config = config,
        .path = path,
        .server = server,
        .should_stop = std.atomic.Value(bool).init(false),
    };
}

pub fn deinit(self: *Self) void {
    self.should_stop.store(true, .seq_cst);
    if (self.server) |*s| s.deinit();
    std.fs.deleteFileAbsolute(self.path) catch {};
    self.allocator.free(self.path);
}

pub fn listen(
    self: *Self,
    context: ?*anyopaque,
    callback: *const fn (context: ?*anyopaque) void,
) !void {
    while (!self.should_stop.load(.seq_cst)) {
        const conn = self.server.?.accept() catch {
            if (self.should_stop.load(.seq_cst)) return;
            continue;
        };
        defer conn.stream.close();

        var buf: [64]u8 = undefined;
        _ = conn.stream.read(&buf) catch continue;

        callback(context);
    }
}

/// Following is for polling at 200ms

// pub fn init(allocator: std.mem.Allocator, config: *Config) !Self {
//     const runtime_dir = std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR") catch
//         try allocator.dupe(u8, "/tmp");
//     defer allocator.free(runtime_dir);
//
//     const path = try std.fmt.allocPrint(allocator, "{s}/fancy-cat.sock", .{runtime_dir});
//     errdefer allocator.free(path);
//
//     std.fs.deleteFileAbsolute(path) catch {};
//
//     const address = try std.net.Address.initUnix(path);
//     var server = try address.listen(.{ .reuse_address = true });
//     errdefer server.deinit();
//
//     // Make the listening socket non-blocking so accept() returns
//     // immediately
//     const flags = try posix.fcntl(server.stream.handle, posix.F.GETFL, 0);
//     _ = try posix.fcntl(
//         server.stream.handle,
//         posix.F.SETFL,
//         flags | @as(u32, @bitCast(posix.O{ .NONBLOCK = true })),
//     );
//
//     return .{
//         .allocator = allocator,
//         .config = config,
//         .path = path,
//         .server = server,
//         .should_stop = std.atomic.Value(bool).init(false),
//     };
// }

// pub fn listen(
//     self: *Self,
//     context: ?*anyopaque,
//     callback: *const fn (context: ?*anyopaque) void,
// ) !void {
//     const timeout_ms = 200;
//
//     while (!self.should_stop.load(.seq_cst)) {
//         var poll_fds = [_]posix.pollfd{
//             .{ .fd = self.server.?.stream.handle, .events = posix.POLL.IN, .revents = 0 },
//         };
//
//         const n = posix.poll(&poll_fds, timeout_ms) catch continue;
//         if (n == 0) continue; // timed out, loop back and re-check should_stop
//
//         if (poll_fds[0].revents & posix.POLL.IN != 0) {
//             const conn = self.server.?.accept() catch |err| switch (err) {
//                 error.WouldBlock => continue,
//                 else => continue,
//             };
//             defer conn.stream.close();
//
//             var buf: [64]u8 = undefined;
//             _ = conn.stream.read(&buf) catch {};
//
//             callback(context);
//         }
//     }
// }
