//! kghostty: per-entry font styles for font family configuration values.
//!
//! A font family entry (`font-family*`, and the font in `font-codepoint-map`)
//! may end with `:style=<name>`, e.g. `Hiragino Sans:style=W3`. The style then
//! applies only to that entry and overrides the matching `font-style*`
//! option. This makes it possible to combine fonts whose style names differ,
//! e.g. a Latin font with a "Light" style and a CJK font with "W0".."W9".
//!
//! Only a trailing `:style=` is recognized, so other `:` in a value (such as
//! a fontconfig pattern) are left untouched.
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Entry = struct {
    family: [:0]const u8,
    style: ?[:0]const u8 = null,
};

const marker = ":style=";
const whitespace = " \t";

/// Parse a font family entry. If there is no `:style=` suffix, the returned
/// family is `value` itself and nothing is allocated. Otherwise the family
/// and style are allocated with `alloc`.
pub fn parse(alloc: Allocator, value: [:0]const u8) Allocator.Error!Entry {
    const idx = std.mem.lastIndexOf(u8, value, marker) orelse
        return .{ .family = value };

    const style = std.mem.trim(u8, value[idx + marker.len ..], whitespace);
    // The style must be the last component and non-empty.
    if (style.len == 0 or std.mem.indexOfScalar(u8, style, ':') != null)
        return .{ .family = value };

    const family = std.mem.trim(u8, value[0..idx], whitespace);
    if (family.len == 0) return .{ .family = value };

    return .{
        .family = try alloc.dupeSentinel(u8, family, 0),
        .style = try alloc.dupeSentinel(u8, style, 0),
    };
}

test "parse without style" {
    const testing = std.testing;
    const e = try parse(testing.failing_allocator, "JetBrains Mono");
    try testing.expectEqualStrings("JetBrains Mono", e.family);
    try testing.expect(e.style == null);
}

test "parse with style" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const e = try parse(arena.allocator(), "Hiragino Sans :style= W3 ");
    try testing.expectEqualStrings("Hiragino Sans", e.family);
    try testing.expectEqualStrings("W3", e.style.?);
}

test "parse with style containing spaces" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const e = try parse(arena.allocator(), "JetBrains Mono:style=ExtraLight Italic");
    try testing.expectEqualStrings("JetBrains Mono", e.family);
    try testing.expectEqualStrings("ExtraLight Italic", e.style.?);
}

test "parse leaves other patterns alone" {
    const testing = std.testing;
    const alloc = testing.failing_allocator;
    for ([_][:0]const u8{
        "Fira Code-14:bold",
        "Foo:style=Bold:weight=200",
        "Foo:style=",
        ":style=Bold",
    }) |v| {
        const e = try parse(alloc, v);
        try testing.expectEqualStrings(v, e.family);
        try testing.expect(e.style == null);
    }
}
