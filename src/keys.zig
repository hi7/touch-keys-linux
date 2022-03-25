const std = @import("std");
const term = @import("term.zig");
const testing = std.testing;
const fs = std.fs;
const mem = std.mem;
const log = std.log;
const math = std.math;
const File = fs.File;
const assert = std.debug.assert;
const expect = std.testing.expect;

pub const Key = struct {
    label: []const u8,
    char: u8,
};
const rows: usize = 6;
const cols: usize = 15;
pub const col_width = 7;
pub const width = cols * col_width;
pub const height = rows;
var de = [rows][cols]Key{
    .{
        Key{.label="Esc", .char='?'}, Key{.label="F1", .char='?'}, Key{.label="F2", .char='?'}, Key{.label="F3", .char='?'}, 
        Key{.label="F4", .char='?'}, Key{.label="F5", .char='?'}, Key{.label="F6", .char='?'}, Key{.label="F7", .char='?'}, 
        Key{.label="F8", .char='?'}, Key{.label="F9", .char='?'}, Key{.label="F10", .char='?'}, Key{.label="F11", .char='?'}, 
        Key{.label="F12", .char='?'}, Key{.label="Druck", .char='?'}, Key{.label="Rollen", .char='?'},
    }, .{
        Key{.label="^", .char='^'}, Key{.label="1", .char='1'}, Key{.label="2", .char='2'}, Key{.label="3", .char='3'}, 
        Key{.label="4", .char='4'}, Key{.label="5", .char='5'}, Key{.label="6", .char='6'}, Key{.label="7", .char='7'}, 
        Key{.label="8", .char='8'}, Key{.label="9", .char='9'}, Key{.label="0", .char='0'}, Key{.label="?", .char='1'}, 
        Key{.label="´", .char='´'}, Key{.label="<-", .char='?'}, Key{.label="Einfg", .char='?'},
    }, .{
        Key{.label="->", .char='?'}, Key{.label="Q", .char='q'}, Key{.label="W", .char='w'}, Key{.label="E", .char='e'}, 
        Key{.label="R", .char='r'}, Key{.label="T", .char='t'}, Key{.label="Z", .char='z'}, Key{.label="U", .char='u'}, 
        Key{.label="I", .char='i'}, Key{.label="O", .char='o'}, Key{.label="P", .char='p'}, Key{.label="Ü", .char='ü'}, 
        Key{.label="*", .char='*'}, Key{.label="Enter", .char='?'}, Key{.label="Entf", .char='?'},
    }, .{
        Key{.label="Fest", .char='?'}, Key{.label="A", .char='a'}, Key{.label="S", .char='s'}, Key{.label="D", .char='d'}, 
        Key{.label="F", .char='f'}, Key{.label="G", .char='g'}, Key{.label="H", .char='h'}, Key{.label="J", .char='j'}, 
        Key{.label="K", .char='k'}, Key{.label="L", .char='l'}, Key{.label="Ö", .char='ö'}, Key{.label="Ä", .char='ä'}, 
        Key{.label="#", .char='#'}, Key{.label="Enter", .char='?'}, Key{.label="Bild auf", .char='?'},
    }, .{
        Key{.label="Umsch", .char='?'}, Key{.label=">", .char='>'}, Key{.label="Y", .char='y'}, Key{.label="X", .char='x'}, 
        Key{.label="C", .char='c'}, Key{.label="V", .char='v'}, Key{.label="B", .char='b'}, Key{.label="N", .char='n'}, 
        Key{.label="M", .char='m'}, Key{.label=",", .char=','}, Key{.label=".", .char='.'}, Key{.label="-", .char='-'}, 
        Key{.label="Umsch", .char='?'}, Key{.label="Hoch", .char='?'}, Key{.label="Rechts", .char='?'},
    }, .{
        Key{.label="Strg", .char='M'}, Key{.label="Symbol", .char='?'}, Key{.label="Alt", .char='A'}, Key{.label="Pos 1", .char='?'}, 
        Key{.label="Space", .char=' '}, Key{.label="Ende", .char='?'}, Key{.label="Space", .char=' '}, Key{.label="Space", .char=' '}, 
        Key{.label="Space", .char=' '}, Key{.label="Alt Gr", .char='?'}, Key{.label="Symbol", .char='?'}, Key{.label="Menü", .char='?'}, 
        Key{.label="Strg", .char='M'}, Key{.label="Links", .char='?'}, Key{.label="Runter", .char='?'}
    }
};

pub fn toColumn(comptime T: type, x: T) T {
    const dx = @divTrunc(x, 3) * 2;
    return x * col_width + dx + 1;
}

pub fn write() anyerror!void {
    for (de) | row, y | {
        for (row) | col, x | {
            try term.writeAt(toColumn(usize, x), y + 1, "{s}", .{col.label});
        }
    }
}