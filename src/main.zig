const std = @import("std");
const signal = @import("signal.zig");
const term = @import("term.zig");
const touch = @import("touch.zig");
const testing = std.testing;
const fs = std.fs;
const mem = std.mem;
const log = std.log;
const math = std.math;
const File = fs.File;
const assert = std.debug.assert;
const expect = std.testing.expect;

pub fn main() anyerror!void {
    signal.listenFor(std.os.linux.SIG.INT, handle_sig);
    try term.write(term.CURSOR_HIDE);
    try term.clear();

    const device = touch.readDevice() catch | err | {
        std.debug.print("{s}!\n", .{err});
        return;
    };
    touch.events = try touch.openEvents(device);
    defer touch.events.close();
    log.info("Touch trackpad!", .{});
    try touch.readEvents();
}

fn handle_sig() void {
    touch.events.close();
    term.write(term.CURSOR_SHOW) catch @panic("Can not show cursor!");
    term.clear() catch @panic("Can not clear screen!");
    std.os.exit(0);
}
