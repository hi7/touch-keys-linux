const root = @import("root");
const std = @import("std");
const fmt = std.fmt;
const io = std.io;
const os = std.os;
const system = os.system;
const assert = std.debug.assert;
const expect = std.testing.expect;
const print = std.debug.print;

const tcflag = system.tcflag_t;
const Allocator = *std.mem.Allocator;

pub const ESC: u8 = '\x1B';
pub const SEQ: u8 = '[';
pub const CLEAR_SCREEN = "\x1b[2J";
pub const CURSOR_HOME = "\x1b[H";
pub const CURSOR_HIDE = "\x1b[?25l";
pub const CURSOR_SHOW = "\x1b[?25h";
pub const RESET_MODE = "\x1b[0m";
pub const BRIGHT_MODE = "\x1b[1m";
pub const DIM_MODE = "\x1b[2m";
pub const UNDERSCORE_MODE = "\x1b[4m";
pub const BLINK_MODE = "\x1b[5m";
pub const REVERSE_MODE = "\x1b[7m";
pub const HIDDEN_MODE = "\x1b[8m";
pub const RESET_WRAP_MODE = "\x1b[?7l";

// Errors
const OOM = "Out of memory error";
const BO = "Buffer overflow error";

pub const Position = struct {
    x: usize, y: usize,
};

pub fn setCursor(x: usize, y: usize) anyerror!void {
    var buf: [12]u8 = undefined;
    const goto = try fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y, x});
    try write(goto);
}
pub fn write(data: []const u8) anyerror!void {
    _ = try io.getStdOut().writer().write(data);
}
pub fn writeAt(x: usize, y: usize, comptime format: []const u8, args: anytype) anyerror!void {
    try setCursor(x, y);
    var buf: [255]u8 = undefined;
    const goto = try fmt.bufPrint(&buf, format, args);
    try write(goto);
}

var orig_mode: system.termios = undefined;
/// timeout for read(): x/10 seconds, null means wait forever for input
pub fn rawMode(timeout: ?u8) void {
    orig_mode = os.tcgetattr(os.STDIN_FILENO) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("tcgetattr failed!");
    };
    var raw = orig_mode;
    assert(&raw != &orig_mode); // ensure raw is a copy    
    raw.iflag &= ~(@as(tcflag, system.BRKINT) | @as(tcflag, system.ICRNL) | @as(tcflag, system.INPCK)
         | @as(tcflag, system.ISTRIP) | @as(tcflag, system.IXON));
    //raw.oflag &= ~(@as(tcflag, system.OPOST)); // turn of \n => \n\r
    raw.cflag |= (@as(tcflag, system.CS8));
    raw.lflag &= ~(@as(tcflag, system.ECHO) | @as(tcflag, system.ICANON) | @as(tcflag, system.IEXTEN) | @as(tcflag, system.ISIG));
    if(timeout != null) {
        raw.cc[system.VMIN] = 0; // add timeout for read()
        raw.cc[system.VTIME] = timeout.?;// x/10 seconds
    } 
    os.tcsetattr(os.STDIN_FILENO, .FLUSH, raw) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("tcsetattr failed!");
    };
}
pub fn cookedMode() void {
    os.tcsetattr(os.STDIN_FILENO, .FLUSH, orig_mode) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("tcsetattr failed!");
    };
}
fn getWindowSize(fd: std.fs.File) !os.winsize {
    while (true) {
        var size: os.winsize = undefined;
        switch (os.errno(system.ioctl(fd.handle, os.TIOCGWINSZ, @ptrToInt(&size)))) {
            0 => return size,
            os.EINTR => continue,
            os.EBADF => unreachable,
            os.EFAULT => unreachable,
            os.EINVAL => return error.Unsupported,
            os.ENOTTY => return error.Unsupported,
            else => |err| return os.unexpectedErrno(err),
        }
    }
}

const stdin = std.io.getStdIn();
pub fn readKey() [4]u8 {
    var buf: [4]u8 = undefined;
    _ = stdin.reader().read(&buf) catch |err| {
        print("StdIn read() failed! error: {s}", .{err});
        return buf; // len = 0
    };
    return buf; // len };
}

pub fn nonBlock() void {
    const fl = os.fcntl(os.STDIN_FILENO, os.F.GETFL, 0) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("fcntl(STDIN_FILENO, GETFL, 0) failed!");
    };
    _ = os.fcntl(os.STDIN_FILENO, os.F.SETFL, fl | os.O.NONBLOCK) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("fcntl(STDIN_FILENO, SETFL, fl | NONBLOCK) failed!");
    };
}
