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
    if (self.server) |*s| {
        s.deinit();
        self.server = null;
    }
    std.fs.deleteFileAbsolute(self.path) catch {};
    self.allocator.free(self.path);
    self.path = &.{};
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
