const std = @import("std");
const str = []const u8;

const stdout_file = std.io.getStdOut().writer();
const stderr_file = std.io.getStdErr().writer();

const defaultIcon: str = " ";
const fileIcon: str = " ";
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
    switch (m) {
        0 => return "☰",
        1 => return "☴",
        2 => return "☲",
        3 => return "☶",
        4 => return "☱",
        5 => return "☵",
        6 => return "☳",
        7 => return "☷",
        else => return "",
    }
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
        switch (err) {
            error.NoSpaceLeft => {
                try stderr.print("fdutil: no space left for '{s}'\n", .{fpath});
            },
            error.FileNotFound => {
                try stderr.print("fdutil: path not found for '{s}'\n", .{fpath});
            },
            error.FileTooBig => {
                try stderr.print("fdutil: file too big for '{s}'\n", .{fpath});
            },
            error.AccessDenied => {
                try stderr.print("fdutil: access denied for '{s}'\n", .{fpath});
            },
            error.DeviceBusy => {
                try stderr.print("fdutil: device busy for '{s}'\n", .{fpath});
            },
            error.NameTooLong => {
                try stderr.print("fdutil: name too long for '{s}'\n", .{fpath});
            },
            else => {
                try stderr.print("fdutil: cannot open '{s}'\n", .{fpath});
            },
        }
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
                size = std.fmt.bufPrint(&buf, "{s:.2}", .{std.fmt.fmtIntSizeBin(stat.size)}) catch |err| {
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
                size = std.fmt.bufPrint(&buf, "{s:.2}", .{std.fmt.fmtIntSizeBin(stat.size)}) catch |err| {
                    try stderr.print("fdutil: not enough memory for string conversion: {}\n", .{err});
                    continue;
                };
                mask = displayMask(stat.mode);
                icon = folderIcon;
            },
            else => {
                size = "";
                mask = "";
                icon = defaultIcon;
            },
        }
        try stdout.print("{s:<1}{s:15} {s}\n", .{ icon, size, it.name });
    }
}
