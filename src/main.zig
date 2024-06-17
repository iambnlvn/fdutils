const std = @import("std");
const str = []const u8;

const stdout_file = std.io.getStdOut().writer();
const stderr_file = std.io.getStdErr().writer();

const defaultIcon: str = " ";
const fileIcon: str = "📄";
const folderIcon: str = "🗀";
fn getFilePath(allocator: std.mem.Allocator) ![*:0]u8 {
    if (std.os.argv.len > 1) {
        return std.os.argv[1];
    } else {
        const cwd = try std.process.getEnvVarOwned(allocator, "PWD");
        defer allocator.free(cwd);
        return try allocator.dupeZ(u8, cwd);
    }
}
fn displayMask(m: std.fs.File.Mode) str {
    const masks = [_]str{ "☰", "☴", "☲", "☶", "☱", "☵", "☳", "☷" };
    if (m < masks.len) {
        return masks[m];
    } else {
        return "not supported";
    }
}

fn getPermission(m: std.fs.File.Mode) str {
    m = m & 0o777;
    const perms = [_]str{
        "---", "--x", "-w-", "-wx",
        "r--", "r-x", "rw-", "rwx",
    };
    return perms[m];
}

fn formatSize(buf: []u8, stat: std.fs.File.Stat) error{NoSpaceLeft}!str {
    return try std.fmt.bufPrint(buf, "{s:.2}", .{std.fmt.fmtIntSizeBin(stat.size)});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var sw = std.io.bufferedWriter(stdout_file);
    var ew = std.io.bufferedWriter(stderr_file);
    const stderr = ew.writer();
    const stdout = sw.writer();
    defer ew.flush() catch unreachable;
    defer sw.flush() catch unreachable;

    const fpath: [*:0]u8 = try getFilePath(allocator);

    var dir = std.fs.openDirAbsoluteZ(fpath, .{ .iterate = true }) catch |err| {
        const errMessage = switch (err) {
            error.NoSpaceLeft => "no space left",
            error.FileNotFound => "path not found",
            error.FileTooBig => "file too big",
            error.AccessDenied => "access denied",
            error.DeviceBusy => "device busy",
            error.NameTooLong => "name too long",
            else => "cannot open",
        };
        try stderr.print("fdutil: {s} for '{s}'\n", .{ errMessage, fpath });
        return;
    };
    var iterator = dir.iterate();
    var buf: [1024]u8 = undefined;
    var size: str = "";
    var mask: str = "";
    var icon: str = "";

    while (try iterator.next()) |it| {
        switch (it.kind) {
            std.fs.File.Kind.file => {
                const stat = std.fs.Dir.statFile(dir, it.name) catch |err| {
                    try stderr.print("fdutil: can't stat file '{s}: {}'\n", .{ it.name, err });
                    continue;
                };

                size = formatSize(&buf, stat) catch |err| {
                    try stderr.print("fdutil: not enough memory for string conversion: {}\n", .{err});
                    continue;
                };
                mask = displayMask(stat.mode);
                icon = fileIcon;
            },
            std.fs.File.Kind.directory => {
                const stat = std.fs.Dir.statFile(dir, it.name) catch |err| {
                    try stderr.print("fdutil: can't stat file '{s}: {}'\n", .{ it.name, err });
                    continue;
                };
                size = formatSize(&buf, stat) catch |err| {
                    try stderr.print("fdutil: not enough memory for string conversion: {}\n", .{err});
                    continue;
                };
                mask = displayMask(stat.mode);
                icon = folderIcon;
            },
            else => {
                size = "";
                mask = ""; // mask is currently not working
                icon = defaultIcon;
            },
        }
        try stdout.print("{s:<1}{s:15} {s} {s}\n", .{ icon, size, it.name, mask });
    }
}
