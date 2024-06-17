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
const Permissions = struct {
    read: []const u8,
    write: []const u8,
    execute: []const u8,
};

fn formatSize(buf: []u8, stat: std.fs.File.Stat) error{NoSpaceLeft}!str {
    return try std.fmt.bufPrint(buf, "{s:.2}", .{std.fmt.fmtIntSizeBin(stat.size)});
}

fn checkPermissions(file_path: []const u8) !usize {
    const fs = std.fs;
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();

    const stat = try file.stat();
    const mode = stat.mode;

    return mode & 0o777;
}
fn filePermissions(mode: usize) Permissions {
    return Permissions{
        .read = if (mode & 0o400 != 0) "r" else "-",
        .write = if (mode & 0o200 != 0) "w" else "-",
        .execute = if (mode & 0o100 != 0) "x" else "-",
    };
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
    var mask: usize = undefined;
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
                mask = checkPermissions(it.name) catch |err| {
                    try stderr.print("fdutil: can't get permissions for file '{s}: {}'\n", .{ it.name, err });
                    continue;
                };
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
                icon = folderIcon;
            },
            else => {
                size = "";
                mask = 0;
                icon = defaultIcon;
            },
        }
        const permissions = filePermissions(mask);
        try stdout.print("{s:<1}{s:15} {s} {s}{s}{s}\n", .{ icon, size, it.name, permissions.read, permissions.write, permissions.execute });
    }
}
