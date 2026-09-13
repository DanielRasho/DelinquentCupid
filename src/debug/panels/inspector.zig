const std = @import("std");
const zgui = @import("zgui");
const rl = @import("raylib");
const ecs = @import("ecs");
const known = @import("../known_components.zig");

const Scene = ecs.scene.Scene;
const EntityID = ecs.entity.EntityID;

/// One entry in the Inspector's *editable*-component registry: a friendly
/// display name paired with the concrete type, so the Inspector can go
/// straight to `entities.getComponent(id, entry.T)` and `@field()` into a
/// live pointer. This is narrower than "every component that exists" --
/// see the note on `known_components` below for why a type is required
/// here at all, and what happens to components that aren't in it.
const ComponentEntry = struct { name: [:0]const u8, T: type };

/// The component types the Inspector can render *editable* widgets for --
/// built from `known_components.zig`'s hand-written, explicit list of bare
/// types (which can come from anywhere; nothing here cares which file
/// declared them), with a display name derived from each type's own
/// `@typeName`. Sorted alphabetically by name -- the order the
/// "Selected Entity" panel lists a component's fields in.
///
/// This is *not* what makes a component visible to the Inspector at all --
/// `EntityDB.getComponentNames()` lists an entity's components straight
/// from live ECS storage, no matter where the component type is declared,
/// since component identity there is just an erased `@typeName` string
/// (there's no way to recover a `type` from that at runtime -- Zig's
/// `type` only exists at compile time, and mutable state can't survive
/// between separate comptime evaluations to be accumulated as
/// `setComponent()` gets called across the program either -- Zig rejects
/// that outright, which is exactly why this has to be an explicit list).
/// A component missing from this list still shows up by name in both the
/// Entities list and the Selected Entity panel; it just can't be expanded
/// into editable fields.
const known_components = blk: {
    var entries: [known.all.len]ComponentEntry = undefined;
    for (known.all, 0..) |T, i| {
        entries[i] = .{ .name = shortTypeName(T), .T = T };
    }
    var result = entries;
    // std.mem.sort's block/pdq algorithm does an internal @memcpy that
    // Zig's comptime aliasing check rejects for this array (works fine at
    // runtime; comptime evaluation is stricter). insertion sort has no
    // such merge step and this list is a handful of entries, so it costs
    // nothing.
    std.sort.insertion(ComponentEntry, &result, {}, lessThanName);
    break :blk result;
};

fn lessThanName(_: void, a: ComponentEntry, b: ComponentEntry) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

/// Strips the module-path prefix off a type's own @typeName, e.g.
/// `shortTypeName(comps.Position)` -> "Position". Used only for building
/// `known_components` above; see `shortName` below for the equivalent used
/// on names read back from live ECS storage (a plain, non-sentinel-
/// terminated `[]const u8` there, unlike `@typeName`).
fn shortTypeName(comptime T: type) [:0]const u8 {
    const full = @typeName(T);
    if (std.mem.lastIndexOfScalar(u8, full, '.')) |i| return full[i + 1 ..];
    return full;
}

pub const State = struct {
    selected: ?EntityID = null,
};

pub fn render(state: *State, dt: f32, scn: *Scene) void {
    zgui.setNextWindowPos(.{ .x = 10.0, .y = 10.0, .cond = .first_use_ever });

    if (zgui.begin("Inspector", .{})) {
        renderFrame(dt);
        renderEntities(state, scn);
        renderSelected(state, scn);
    }
    zgui.end();
}

fn renderFrame(dt: f32) void {
    if (zgui.collapsingHeader("Frame", .{})) {
        zgui.text("FPS: {d}", .{rl.getFPS()});
        zgui.text("Delta time: {d:.4} s", .{dt});
    }
}

fn renderEntities(state: *State, scn: *Scene) void {
    if (!zgui.collapsingHeader("Entities", .{})) return;

    var ids: std.ArrayList(EntityID) = .empty;
    defer ids.deinit(scn.allocator);

    // query(.{}) with no component types matches every archetype but the
    // void one, i.e. every entity with at least one component -- there's
    // no dedicated "all entities" call needed.
    var it = scn.entities.query(.{});
    while (it.next()) |id| {
        ids.append(scn.allocator, id) catch |err| {
            std.log.err("inspector: failed to list entities: {}", .{err});
            return;
        };
    }
    std.mem.sort(EntityID, ids.items, {}, std.sort.asc(EntityID));

    for (ids.items) |id| {
        var buf: [256]u8 = undefined;
        const label = entityLabel(&buf, id, scn) catch continue;
        if (zgui.selectable(label, .{ .selected = state.selected != null and state.selected.? == id })) {
            state.selected = id;
        }
    }
}

/// Strips the module-path prefix off a @typeName, e.g.
/// "game.components.Position" -> "Position". Component identity is by the
/// full @typeName (see ecs/entity.zig); this is purely cosmetic, for UI
/// labels.
fn shortName(full_name: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, full_name, '.')) |i| return full_name[i + 1 ..];
    return full_name;
}

/// Builds "<id> : <comp1>, <comp2>, ..." for one entity. Names come from
/// `getComponentNames()`, straight off live storage -- every component the
/// entity actually has, not just the ones in `known_components`.
fn entityLabel(buf: []u8, id: EntityID, scn: *Scene) ![:0]const u8 {
    var len: usize = (try std.fmt.bufPrint(buf, "{d} : ", .{id})).len;
    const names = scn.entities.getComponentNames(id) orelse &[_][]const u8{};
    for (names, 0..) |full_name, i| {
        const sep: []const u8 = if (i == 0) "" else ", ";
        len += (try std.fmt.bufPrint(buf[len..], "{s}{s}", .{ sep, shortName(full_name) })).len;
    }
    buf[len] = 0;
    return buf[0..len :0];
}

fn renderSelected(state: *State, scn: *Scene) void {
    if (!zgui.collapsingHeader("Selected Entity", .{})) return;

    const id = state.selected orelse {
        zgui.textUnformatted("(select an entity in the Entities list above)");
        return;
    };
    zgui.text("Entity {d}", .{id});
    zgui.separator();

    const names = scn.entities.getComponentNames(id) orelse return;
    for (names) |full_name| {
        const short = shortName(full_name);

        var matched = false;
        inline for (known_components) |entry| {
            if (!matched and std.mem.eql(u8, short, entry.name)) {
                matched = true;
                if (scn.entities.getComponent(id, entry.T)) |ptr| {
                    renderComponent(entry.name, entry.T, ptr);
                }
            }
        }
        if (!matched) {
            zgui.text("{s} (no editor registered)", .{short});
        }
    }
}

fn renderComponent(comptime name: [:0]const u8, comptime T: type, ptr: *T) void {
    if (zgui.treeNode(name)) {
        inline for (std.meta.fields(T)) |field| {
            renderField(T, field, ptr, name);
        }
        zgui.treePop();
    }
}

/// Renders one field as an editable widget where the field's type maps
/// cleanly to an ImGui one (float32 -> drag float, any int width -> drag
/// int via a cast, bool -> checkbox); anything else (enums, nested structs,
/// strings, ...) falls back to read-only text for now.
fn renderField(comptime T: type, comptime field: std.builtin.Type.StructField, ptr: *T, comptime component_name: [:0]const u8) void {
    const field_ptr = &@field(ptr.*, field.name);

    var label_buf: [64]u8 = undefined;
    const label: [:0]const u8 = std.fmt.bufPrintZ(&label_buf, "{s}##{s}.{s}", .{ field.name, component_name, field.name }) catch "field";

    switch (@typeInfo(field.type)) {
        .float => |info| if (info.bits == 32) {
            _ = zgui.dragFloat(label, .{ .v = field_ptr });
        } else {
            zgui.text("{s}: {any} (unsupported float width)", .{ label, field_ptr.* });
        },
        .int => {
            var scratch: i32 = std.math.lossyCast(i32, field_ptr.*);
            if (zgui.dragInt(label, .{ .v = &scratch })) {
                field_ptr.* = std.math.lossyCast(field.type, scratch);
            }
        },
        .bool => _ = zgui.checkbox(label, .{ .v = field_ptr }),
        else => zgui.text("{s}: {any}", .{ label, field_ptr.* }),
    }
}
