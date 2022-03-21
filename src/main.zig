const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const mem = std.mem;
const log = std.log;
const File = fs.File;

var debug: u8 = 1;
var events: File = undefined;

// cat /proc/bus/input/devices
pub fn main() anyerror!void {
    const device = try readDevice();
    var pathbuf: [255]u8 = undefined;
    const path = try std.fmt.bufPrint(&pathbuf, "/dev/input/{s}", .{device});
    if (debug > 0) {
        log.info("Events: {s}", .{path});
    }
    events = try fs.openFileAbsolute(path, .{ .read = true });
    log.info("Read input events...", .{});
    try readEvent();
    events.close();
}

test "basic test" {
    try fs.accessAbsolute("/dev/input/event23", .{ .read = true });
}

const Type = enum(u16) {EV_KEY = 1, EV_ABS = 3};
const Code = enum(u16) {ABS_X = 0, ABS_Y = 1, ABS_PRESSURE = 24, 
    ABS_MT_SLOT = 47, ABS_MT_TOUCH_MAJOR = 48, ABS_MT_TOUCH_MINOR = 49, 
    ABS_MT_POSITION_X = 53, ABS_MT_POSITION_Y = 54, ABS_MT_TRACKING_ID = 57, ABS_MT_PRESSURE = 58,
    BTN_TOOL_FINGER = 325, BTN_TOUCH = 330
};
// ABS_MT_SLOT => multi events finger {value}

pub const InputEvent = extern struct {
    tv_sec: u64,
    tv_usec: u64,
    type: u16,
    code: u16,
    value: i32
};

fn readEvent() anyerror!void {
    while (true) {
        var event = try events.reader().readStruct(InputEvent);
        if (event.type == 0 and event.code == 0 and event.value == 0) {
            log.info("event: time {d}.{d}, SYN_REPORT", .{event.tv_sec, event.tv_usec});
        } else {
            log.info("event: time {d}.{d}, type {d}, code {d}, value {d}", .{event.tv_sec, event.tv_usec, event.type, event.code, event.value});
        }
    }
}


const ExtractPropertyError = error{
    NoStartIndex,
    MatchNotFound,
    LineDelimiterNotFound,
};

fn extractWithMatchToEOL(match: []const u8, text: []const u8, start_index: ?usize) anyerror![]const u8 {
    return extractToEOL(match, text, start_index, true);
}
fn extractWithoutMatchToEOL(match: []const u8, text: []const u8, start_index: ?usize) anyerror![]const u8 {
    return extractToEOL(match, text, start_index, false);
}

fn extractToEOL(match: []const u8, text: []const u8, start_index: ?usize, include_match: bool) anyerror![]const u8 {
    if (start_index == null) {
        return ExtractPropertyError.NoStartIndex;
    }
    var index1 = mem.indexOfPos(u8, text, start_index.?, match);
    if (index1 == null) {
        return ExtractPropertyError.NoStartIndex;
    }
    if (!include_match) {
        index1.? = index1.? + match.len;
    }
    if (text[index1.?] == '"') {
        index1.? += 1;
    }

    var index2 = mem.indexOfPos(u8, text, index1.?, "\n");
    if (index2 == null) {
        return ExtractPropertyError.NoStartIndex;
    }
    return text[(index1.?)..(index2.? - 1)];
}

fn previousEOL(text: []const u8, start_index: usize) ?usize {
    var i: usize = start_index;
    while (i > 0 and text[i] != '\n') {
        i -= 1;
    }
    return i;
}

const ReadDeviceError = error{
    DeviceNotFound,
};

fn readDevice() anyerror![]const u8 {
    var devices: File = try fs.openFileAbsolute("/proc/bus/input/devices", .{ .read = true });
    var buf: [10240]u8 = undefined;
    const bytes_read = try devices.readAll(&buf);
    devices.close();

    const devices_text = buf[0..bytes_read];
    const i = mem.lastIndexOf(u8, devices_text, "Trackpad");
    if (i != null) {
        if (debug > 0) {
            const name = extractWithoutMatchToEOL("Name=", devices_text, previousEOL(devices_text, i.?));
            if (debug > 1) {
                const handlers = extractWithoutMatchToEOL("Handlers=", devices_text, i.?);
                log.info("Trackpad: {s}, Handlers: {s}", .{name, handlers});
            } else {
                log.info("Trackpad: {s}", .{name});
            }
        }
        return extractWithMatchToEOL("event", devices_text, i.?);
    }
    log.err("Trackpad not found!", .{});
    return error.DeviceNotFound;
}
