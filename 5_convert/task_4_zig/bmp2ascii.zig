const std = @import("std");

const palette = "@%#*+=-:. ";

const Image = struct {
    width: usize,
    height: usize,
    bytes_per_pixel: usize,
    row_size: usize,
    top_down: bool,
    pixels: []const u8,

    fn brightness(self: Image, x: usize, y: usize) f32 {
        const row = if (self.top_down) y else self.height - 1 - y;
        const i = row * self.row_size + x * self.bytes_per_pixel;
        const b: f32 = @floatFromInt(self.pixels[i]);
        const g: f32 = @floatFromInt(self.pixels[i + 1]);
        const r: f32 = @floatFromInt(self.pixels[i + 2]);
        return 0.299 * r + 0.587 * g + 0.114 * b;
    }
};

fn readU16(d: []const u8, off: usize) u16 {
    return std.mem.readInt(u16, d[off..][0..2], .little);
}

fn readU32(d: []const u8, off: usize) u32 {
    return std.mem.readInt(u32, d[off..][0..4], .little);
}

fn readI32(d: []const u8, off: usize) i32 {
    return std.mem.readInt(i32, d[off..][0..4], .little);
}

fn parseBmp(data: []const u8) !Image {
    if (data.len < 54 or data[0] != 'B' or data[1] != 'M') return error.NotABmpFile;
    const offset: usize = readU32(data, 10);
    const w = readI32(data, 18);
    const h = readI32(data, 22);
    const bits = readU16(data, 28);
    const compression = readU32(data, 30);

    if (bits != 24 and bits != 32) return error.OnlyTrueColorSupported;
    if (compression != 0 and !(compression == 3 and bits == 32)) return error.CompressedBmpNotSupported;
    if (w <= 0 or h == 0) return error.BadDimensions;

    const width: usize = @intCast(w);
    const height: usize = @intCast(@abs(h));
    const row_size = ((@as(usize, bits) * width + 31) / 32) * 4;
    if (offset + row_size * height > data.len) return error.TruncatedFile;

    return .{
        .width = width,
        .height = height,
        .bytes_per_pixel = bits / 8,
        .row_size = row_size,
        .top_down = h < 0,
        .pixels = data[offset..],
    };
}

fn toAscii(gpa: std.mem.Allocator, img: Image, columns: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    const step = @max(1, (img.width + columns - 1) / columns);
    const y_step = step * 2;

    var y: usize = 0;
    while (y < img.height) : (y += y_step) {
        var x: usize = 0;
        while (x < img.width) : (x += step) {
            var sum: f32 = 0;
            var count: f32 = 0;
            var dy: usize = 0;
            while (dy < y_step and y + dy < img.height) : (dy += 1) {
                var dx: usize = 0;
                while (dx < step and x + dx < img.width) : (dx += 1) {
                    sum += img.brightness(x + dx, y + dy);
                    count += 1;
                }
            }
            const level = sum / count / 256.0 * @as(f32, @floatFromInt(palette.len));
            const index: usize = @min(palette.len - 1, @as(usize, @intFromFloat(level)));
            try out.append(gpa, palette[index]);
        }
        try out.append(gpa, '\n');
    }
    return out.toOwnedSlice(gpa);
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    const input = if (args.len > 1) args[1] else "image.bmp";
    const output = if (args.len > 2) args[2] else "ascii.txt";
    const columns = if (args.len > 3) try std.fmt.parseInt(usize, args[3], 10) else 80;

    const data = std.Io.Dir.cwd().readFileAlloc(io, input, arena, .limited(64 << 20)) catch |err| {
        std.debug.print("Cannot read {s}: {s}\n", .{ input, @errorName(err) });
        return;
    };
    const img = parseBmp(data) catch |err| {
        std.debug.print("Bad BMP {s}: {s}\n", .{ input, @errorName(err) });
        return;
    };

    const art = try toAscii(arena, img, columns);

    var buffer: [4096]u8 = undefined;
    var file_writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    const stdout = &file_writer.interface;
    try stdout.writeAll(art);
    try stdout.print("\n{s}: {d}x{d}, {d}-bit -> {s}\n", .{
        input, img.width, img.height, img.bytes_per_pixel * 8, output,
    });
    try stdout.flush();

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output, .data = art });
}
