//! The kinds of spirit sphere: how each looks, how likely the shop is to
//! roll it, how often its effect goes off, and which cells that effect
//! strikes around the block the sphere hit. Pure rules, no `Scene`: the
//! ball system applies them and the effects system draws them.
const std = @import("std");
const rl = @import("raylib");
const constants = @import("constants.zig");
const comps = @import("components.zig");

const Kind = comps.SphereKind;
const GridCell = comps.GridCell;

pub const Info = struct {
    name: [:0]const u8,
    color: rl.Color,
    /// Chance (0-100) that the shop rolls this kind.
    chance: u32,
    /// The effect goes off on the first block hit and then every this many
    /// hits; 0 for a kind with no effect.
    every: u32,
};

pub fn info(kind: Kind) Info {
    return switch (kind) {
        .NORMAL => .{ .name = "Normal", .color = .white, .chance = constants.NORMAL_SPHERE_CHANCE, .every = 0 },
        .FIRE => .{ .name = "Fire", .color = .orange, .chance = constants.FIRE_SPHERE_CHANCE, .every = constants.FIRE_EVERY },
        .BOMB => .{ .name = "Bomb", .color = .red, .chance = constants.BOMB_SPHERE_CHANCE, .every = constants.BOMB_EVERY },
        .ROW_LASER => .{ .name = "Row Laser", .color = .sky_blue, .chance = constants.ROW_LASER_CHANCE, .every = constants.ROW_LASER_EVERY },
        .COLUMN_LASER => .{ .name = "Column Laser", .color = .lime, .chance = constants.COLUMN_LASER_CHANCE, .every = constants.COLUMN_LASER_EVERY },
        .CROSS_LASER => .{ .name = "Cross Laser", .color = .magenta, .chance = constants.CROSS_LASER_CHANCE, .every = constants.CROSS_LASER_EVERY },
    };
}

/// A random kind, weighted by each kind's chance.
pub fn roll() Kind {
    return kindForRoll(@intCast(rl.getRandomValue(0, 99)));
}

/// The kind a roll in [0, 100) lands on: the kinds' chances laid end to end.
fn kindForRoll(value: u32) Kind {
    var threshold: u32 = 0;
    for (std.enums.values(Kind)) |kind| {
        threshold += info(kind).chance;
        if (value < threshold) return kind;
    }
    return .NORMAL;
}

/// Whether the hit `sphere` is about to land sets off its effect.
pub fn goesOff(sphere: comps.Sphere) bool {
    const every = info(sphere.kind).every;
    return every != 0 and sphere.hits % every == 0;
}

/// What `kind`'s effect deals to each block it strikes, for a sphere that
/// hits for `sphere_damage`.
pub fn effectDamage(kind: Kind, sphere_damage: u32) u32 {
    return switch (kind) {
        .NORMAL => 0,
        .FIRE => constants.FIRE_DAMAGE,
        .BOMB, .ROW_LASER, .COLUMN_LASER, .CROSS_LASER => sphere_damage,
    };
}

/// A rectangle of grid cells. It may stick out of the grid (left of column
/// 0, say); `clipToGrid` cuts it down for drawing.
pub const Area = struct { col: i32, row: i32, cols: i32, rows: i32 };

/// The cells an effect strikes, as up to four rectangles.
pub const Areas = struct {
    items: [4]Area = undefined,
    len: usize = 0,

    pub fn slice(self: *const Areas) []const Area {
        return self.items[0..self.len];
    }

    /// Whether a block covering `block` has a cell in any of the areas.
    pub fn reach(self: *const Areas, block: GridCell) bool {
        for (self.slice()) |area| if (touches(area, block)) return true;
        return false;
    }

    fn add(self: *Areas, area: Area) void {
        self.items[self.len] = area;
        self.len += 1;
    }
};

/// The cells `kind`'s effect strikes when its sphere hits the block covering
/// `hit`. They're laid around the whole block, so a mini boss's fire spreads
/// all around it and its lasers sweep both of its rows / columns.
///   FIRE: the cells sharing a side with the block.  BOMB: the ring around
///   it (3 x 3 for a one-cell block).  Lasers: its row(s), its column(s), both.
pub fn effectAreas(kind: Kind, hit: GridCell) Areas {
    const col: i32 = hit.col;
    const row: i32 = hit.row;
    const cols: i32 = hit.cols;
    const rows: i32 = hit.rows;
    const row_band = Area{ .col = 0, .row = row, .cols = constants.GRID_COLS, .rows = rows };
    const column_band = Area{ .col = col, .row = 0, .cols = cols, .rows = constants.GRID_ROWS };

    var out: Areas = .{};
    switch (kind) {
        .NORMAL => {},
        .FIRE => {
            out.add(.{ .col = col - 1, .row = row, .cols = 1, .rows = rows });
            out.add(.{ .col = col + cols, .row = row, .cols = 1, .rows = rows });
            out.add(.{ .col = col, .row = row - 1, .cols = cols, .rows = 1 });
            out.add(.{ .col = col, .row = row + rows, .cols = cols, .rows = 1 });
        },
        .BOMB => out.add(.{ .col = col - 1, .row = row - 1, .cols = cols + 2, .rows = rows + 2 }),
        .ROW_LASER => out.add(row_band),
        .COLUMN_LASER => out.add(column_band),
        .CROSS_LASER => {
            out.add(row_band);
            out.add(column_band);
        },
    }
    return out;
}

/// Whether a block covering `block` has a cell inside `area`.
fn touches(area: Area, block: GridCell) bool {
    const col: i32 = block.col;
    const row: i32 = block.row;
    return col < area.col + area.cols and area.col < col + block.cols and
        row < area.row + area.rows and area.row < row + block.rows;
}

/// The part of `area` on the grid, or null if there's none.
pub fn clipToGrid(area: Area) ?Area {
    const left = @max(area.col, 0);
    const top = @max(area.row, 0);
    const right = @min(area.col + area.cols, @as(i32, constants.GRID_COLS));
    const bottom = @min(area.row + area.rows, @as(i32, constants.GRID_ROWS));
    if (right <= left or bottom <= top) return null;
    return .{ .col = left, .row = top, .cols = right - left, .rows = bottom - top };
}

// ===================
// TESTS
// ===================
const testing = std.testing;

test "spheres - every roll lands on a kind, as often as its chance says" {
    var landed = std.enums.EnumArray(Kind, u32).initFill(0);
    for (0..100) |value| landed.getPtr(kindForRoll(@intCast(value))).* += 1;
    for (std.enums.values(Kind)) |kind| try testing.expectEqual(info(kind).chance, landed.get(kind));
}

test "spheres - effects go off on the first hit, then every few; normal never" {
    for (std.enums.values(Kind)) |kind| {
        const every = info(kind).every;
        for (0..10) |hits| {
            const expected = every != 0 and hits % every == 0;
            try testing.expectEqual(expected, goesOff(.{ .kind = kind, .hits = @intCast(hits) }));
        }
    }
    try testing.expect(goesOff(.{ .kind = .FIRE, .hits = 0 }));
}

test "spheres - fire reaches the sides, the bomb the whole ring" {
    const hit = GridCell{ .col = 2, .row = 3 };
    const fire = effectAreas(.FIRE, hit);
    const bomb = effectAreas(.BOMB, hit);

    const side = GridCell{ .col = 1, .row = 3 };
    const below = GridCell{ .col = 2, .row = 4 };
    const diagonal = GridCell{ .col = 3, .row = 4 };
    const two_away = GridCell{ .col = 4, .row = 3 };

    try testing.expect(fire.reach(side) and fire.reach(below));
    try testing.expect(!fire.reach(diagonal) and !fire.reach(two_away));
    try testing.expect(bomb.reach(side) and bomb.reach(below) and bomb.reach(diagonal));
    try testing.expect(!bomb.reach(two_away));
    try testing.expectEqual(@as(usize, 0), effectAreas(.NORMAL, hit).len);
}

test "spheres - lasers sweep the whole row / column, mini bosses included" {
    const hit = GridCell{ .col = 0, .row = 2 };
    // A boss covering rows 1-2, columns 4-5: in the hit's row, not its column.
    const boss = GridCell{ .col = 4, .row = 1, .cols = 2, .rows = 2 };
    const far_down = GridCell{ .col = 0, .row = constants.GRID_ROWS - 1 };

    try testing.expect(effectAreas(.ROW_LASER, hit).reach(boss));
    try testing.expect(!effectAreas(.ROW_LASER, hit).reach(far_down));
    try testing.expect(!effectAreas(.COLUMN_LASER, hit).reach(boss));
    try testing.expect(effectAreas(.COLUMN_LASER, hit).reach(far_down));
    try testing.expect(effectAreas(.CROSS_LASER, hit).reach(boss));
    try testing.expect(effectAreas(.CROSS_LASER, hit).reach(far_down));

    // A boss hit by a row laser sweeps both of its rows.
    const swept = effectAreas(.ROW_LASER, boss);
    try testing.expect(swept.reach(.{ .col = 0, .row = 1 }) and swept.reach(.{ .col = 0, .row = 2 }));
    try testing.expect(!swept.reach(.{ .col = 0, .row = 3 }));
}

test "spheres - areas are clipped to the grid" {
    const corner = effectAreas(.BOMB, .{ .col = 0, .row = 0 }).items[0];
    try testing.expectEqual(Area{ .col = 0, .row = 0, .cols = 2, .rows = 2 }, clipToGrid(corner).?);
    try testing.expectEqual(@as(?Area, null), clipToGrid(.{ .col = -1, .row = 0, .cols = 1, .rows = 1 }));
}
