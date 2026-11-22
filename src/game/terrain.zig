//! The stage's background map as pure data and rules (no raylib, unit
//! tested): which cells are grass and which soil, the new row that comes in
//! on top every turn, and the grass autotiling.
//!
//! Every cell has soil underneath (drawn first, everywhere); grass cells
//! then draw a tile from the 16-tile grass sheet picked by which of their
//! four side neighbours are grass too, so touching patches join up.
const std = @import("std");
const constants = @import("constants.zig");

pub const COLS = constants.MAP_COLS;
/// Rows kept beyond the stage so every visible cell's autotile sees real
/// neighbours, even mid-scroll: one above (the next row in, already
/// generated, so the top row knows what's north of it) and two below (the
/// bottom one is still sliding out of view during a descent, and the one
/// under it is its south neighbour).
pub const ROWS_ABOVE = 1;
pub const ROWS_BELOW = 2;
pub const ROWS = ROWS_ABOVE + constants.MAP_VISIBLE_ROWS + ROWS_BELOW;

/// Tiles per row (and per column) in the grass and soil sheets.
pub const SHEET_TILES = 4;

pub const Cell = struct {
    grass: bool = false,
    /// Which tile of the soil sheet this cell shows; it travels with the
    /// cell as the map scrolls, so the soil never reshuffles.
    soil: u4 = 0,
};
pub const Row = [COLS]Cell;
/// Row 0 is the topmost one (hidden above the stage, see `ROWS_ABOVE`).
pub const Map = [ROWS]Row;

/// A fresh row: the `MAP_GRASS_BORDER_COLS` outermost columns on each side
/// are always grass, any other cell is grass `grass_chance`% of the time.
pub fn newRow(rand: std.Random, grass_chance: u32) Row {
    var row: Row = undefined;
    for (&row, 0..) |*cell, col| {
        const border = col < constants.MAP_GRASS_BORDER_COLS or col >= COLS - constants.MAP_GRASS_BORDER_COLS;
        cell.* = .{
            .grass = border or rand.uintLessThan(u32, 100) < grass_chance,
            .soil = rand.int(u4),
        };
    }
    return row;
}

pub fn generate(rand: std.Random, grass_chance: u32) Map {
    var map: Map = undefined;
    for (&map) |*row| row.* = newRow(rand, grass_chance);
    return map;
}

/// Moves every row one down (the bottom one drops off) and brings a fresh
/// row in on top.
pub fn scroll(map: *Map, rand: std.Random, grass_chance: u32) void {
    var row: usize = ROWS - 1;
    while (row > 0) : (row -= 1) map[row] = map[row - 1];
    map[0] = newRow(rand, grass_chance);
}

// Neighbour bits of a grass cell's autotile mask.
pub const NORTH: u4 = 1;
pub const EAST: u4 = 2;
pub const SOUTH: u4 = 4;
pub const WEST: u4 = 8;

/// Which of the four side neighbours of (`row`, `col`) are grass too, as
/// `NORTH | EAST | SOUTH | WEST` bits. Off the map counts as grass, so the
/// map's edges never draw a border.
pub fn grassMask(map: *const Map, row: usize, col: usize) u4 {
    var mask: u4 = 0;
    if (row == 0 or map[row - 1][col].grass) mask |= NORTH;
    if (col == COLS - 1 or map[row][col + 1].grass) mask |= EAST;
    if (row == ROWS - 1 or map[row + 1][col].grass) mask |= SOUTH;
    if (col == 0 or map[row][col - 1].grass) mask |= WEST;
    return mask;
}

pub const SheetTile = struct { col: u8, row: u8 };

/// Where the tile for a `grassMask` sits in the grass sheet. Its layout: a
/// vertical strip in column 0 (rows 0-2), a 3x3 patch in columns 1-3
/// (rows 0-2), a lone tile at (0, 3) and a horizontal strip in columns 1-3
/// of row 3; each tile has a border on the sides with no grass neighbour.
pub fn grassTile(mask: u4) SheetTile {
    return GRASS_TILES[mask];
}

const GRASS_TILES = blk: {
    const N = NORTH;
    const E = EAST;
    const S = SOUTH;
    const W = WEST;
    var tiles: [16]SheetTile = undefined;
    // Vertical strip and lone tile.
    tiles[S] = .{ .col = 0, .row = 0 };
    tiles[N | S] = .{ .col = 0, .row = 1 };
    tiles[N] = .{ .col = 0, .row = 2 };
    tiles[0] = .{ .col = 0, .row = 3 };
    // 3x3 patch.
    tiles[E | S] = .{ .col = 1, .row = 0 };
    tiles[E | S | W] = .{ .col = 2, .row = 0 };
    tiles[S | W] = .{ .col = 3, .row = 0 };
    tiles[N | E | S] = .{ .col = 1, .row = 1 };
    tiles[N | E | S | W] = .{ .col = 2, .row = 1 };
    tiles[N | S | W] = .{ .col = 3, .row = 1 };
    tiles[N | E] = .{ .col = 1, .row = 2 };
    tiles[N | E | W] = .{ .col = 2, .row = 2 };
    tiles[N | W] = .{ .col = 3, .row = 2 };
    // Horizontal strip.
    tiles[E] = .{ .col = 1, .row = 3 };
    tiles[E | W] = .{ .col = 2, .row = 3 };
    tiles[W] = .{ .col = 3, .row = 3 };
    break :blk tiles;
};

/// Where a soil tile sits in the soil sheet (no autotiling: any tile fits).
pub fn soilTile(soil: u4) SheetTile {
    return .{ .col = soil % SHEET_TILES, .row = soil / SHEET_TILES };
}

// ===================
// TESTS
// ===================

fn allSoil() Map {
    return @splat(@splat(.{}));
}

test "every grass mask has its own tile in the sheet" {
    var used: [SHEET_TILES][SHEET_TILES]bool = @splat(@splat(false));
    for (0..16) |mask| {
        const tile = grassTile(@intCast(mask));
        try std.testing.expect(tile.col < SHEET_TILES and tile.row < SHEET_TILES);
        try std.testing.expect(!used[tile.row][tile.col]);
        used[tile.row][tile.col] = true;
    }
}

test "grass mask reads the four side neighbours" {
    var map = allSoil();
    // A lone patch, then a horizontal pair, away from the map's edges.
    map[3][5].grass = true;
    try std.testing.expectEqual(@as(u4, 0), grassMask(&map, 3, 5));
    map[3][6].grass = true;
    try std.testing.expectEqual(EAST, grassMask(&map, 3, 5));
    try std.testing.expectEqual(WEST, grassMask(&map, 3, 6));
    // A cell under it; diagonals don't count.
    map[4][5].grass = true;
    try std.testing.expectEqual(EAST | SOUTH, grassMask(&map, 3, 5));
    try std.testing.expectEqual(NORTH, grassMask(&map, 4, 5));
    try std.testing.expectEqual(WEST, grassMask(&map, 3, 6));
}

test "off the map counts as grass" {
    var map = allSoil();
    map[0][0].grass = true;
    try std.testing.expectEqual(NORTH | WEST, grassMask(&map, 0, 0));
    map[ROWS - 1][COLS - 1].grass = true;
    try std.testing.expectEqual(EAST | SOUTH, grassMask(&map, ROWS - 1, COLS - 1));
}

test "new rows: the border columns are always grass, the rest follow the chance" {
    var prng = std.Random.DefaultPrng.init(42);
    const border = constants.MAP_GRASS_BORDER_COLS;
    for (0..20) |_| {
        for (newRow(prng.random(), 0), 0..) |cell, col| {
            const is_border = col < border or col >= COLS - border;
            try std.testing.expectEqual(is_border, cell.grass);
        }
        for (newRow(prng.random(), 100)) |cell| try std.testing.expect(cell.grass);
    }
}

test "scrolling moves every row one down and brings a new one on top" {
    var prng = std.Random.DefaultPrng.init(7);
    var map = generate(prng.random(), 0);
    map[0][5] = .{ .grass = true, .soil = 9 };
    map[ROWS - 2][5] = .{ .grass = true, .soil = 3 };
    scroll(&map, prng.random(), 0);
    try std.testing.expectEqual(Cell{ .grass = true, .soil = 9 }, map[1][5]);
    try std.testing.expectEqual(Cell{ .grass = true, .soil = 3 }, map[ROWS - 1][5]);
    // The fresh top row follows the rules (chance 0: only the borders).
    try std.testing.expect(!map[0][5].grass);
    try std.testing.expect(map[0][0].grass);
}
