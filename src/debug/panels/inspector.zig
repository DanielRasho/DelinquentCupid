const std = @import("std");
const zgui = @import("zgui");
const rl = @import("raylib");
const ecs = @import("ecs");

const Scene = ecs.scene.Scene;
const EntityID = ecs.entity.EntityID;
const reflect = ecs.reflect;

/// The Inspector reads and writes components it has no `type` for. Component
/// identity in storage is an erased `@typeName` string and a `type` can't be
/// recovered from a string at runtime -- but it doesn't have to be: every
/// column carries a `reflect.TypeDescriptor` captured at the moment it was
/// created, while its component type was still known (see ecs/reflect.zig).
/// `EntityDB.componentsOf()` hands over that descriptor plus the live bytes of
/// the entity's row, which is everything needed to draw real widgets.
///
/// So there's nothing to register: a component is editable here purely by
/// virtue of having been `setComponent`'d, no matter which file declares it.
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
/// entity actually has.
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

    var it = scn.entities.componentsOf(id) orelse return;
    while (it.next()) |view| {
        // Scope every widget below by the *full* @typeName. Two components
        // with the same short name from different modules therefore get
        // distinct ImGui ids, and each renders its own fields -- matching on
        // the short name instead would have collapsed them into one.
        zgui.pushStrId(view.name);
        defer zgui.popId();

        renderStruct(view.desc.short_name, view.desc, view.bytes);
    }
}

/// One collapsible component (or nested struct field): a tree node with a row
/// per field. Mutually recursive with `renderField` via `.@"struct"` fields,
/// which terminates because descriptors only nest by value.
fn renderStruct(label: [:0]const u8, desc: *const reflect.TypeDescriptor, bytes: []u8) void {
    if (!zgui.treeNode(label)) return;
    defer zgui.treePop();

    if (desc.fields.len == 0) {
        if (desc.unwalkable) |reason| {
            zgui.text("(not editable: {s})", .{@tagName(reason)});
        } else {
            // A tag component -- no fields is the whole point of it.
            zgui.textUnformatted("(no fields)");
        }
        return;
    }

    if (tryColorEdit(desc, bytes)) return;

    for (desc.fields) |field| renderField(field, bytes);
}

fn renderField(field: reflect.FieldDesc, component_bytes: []u8) void {
    const bytes = field.bytes(component_bytes);

    // Field names are already sentinel-terminated, and pushStrId gives each
    // widget a unique id without hand-built "##" label suffixes.
    zgui.pushStrId(field.name);
    defer zgui.popId();

    switch (field.kind) {
        .bool => |access| {
            var v = access.load(bytes);
            if (zgui.checkbox(field.name, .{ .v = &v })) access.store(bytes, v);
        },
        .float => |access| if (access.bits == 32) {
            // Keep f32 on dragFloat so the widget feels exactly as it did
            // before, rather than detouring through the f64 carrier.
            var v: f32 = @floatCast(access.load(bytes));
            if (zgui.dragFloat(field.name, .{ .v = &v })) access.store(bytes, v);
        } else {
            var v = access.load(bytes);
            if (zgui.dragScalar(field.name, f64, .{ .v = &v })) access.store(bytes, v);
        },
        // Limits come from the field's real type, so a u8 clamps at 0..255
        // and can't be dragged into a wrapped value.
        .int => |access| {
            var v = access.load(bytes);
            if (zgui.dragScalar(field.name, i64, .{ .v = &v, .min = access.min, .max = access.max })) {
                access.store(bytes, v);
            }
        },
        .uint => |access| {
            var v = access.load(bytes);
            if (zgui.dragScalar(field.name, u64, .{ .v = &v, .min = access.min, .max = access.max })) {
                access.store(bytes, v);
            }
        },
        .@"enum" => |access| renderEnum(field, access, bytes),
        .@"struct" => |nested| renderStruct(field.name, nested, bytes),
        .unsupported => |info| renderReadOnly(field, info, bytes),
    }
}

/// A dropdown of the enum's own tag names. `store` ignores anything that
/// isn't one of them, so this can't write an invalid tag.
fn renderEnum(field: reflect.FieldDesc, access: reflect.EnumAccess, bytes: []u8) void {
    const current = access.load(bytes);
    const preview = access.nameOf(current) orelse "(invalid)";

    if (!zgui.beginCombo(field.name, .{ .preview_value = preview })) return;
    defer zgui.endCombo();

    for (access.values) |value| {
        if (zgui.selectable(value.name, .{ .selected = value.value == current })) {
            access.store(bytes, value.value);
        }
    }
}

/// Fields with no widget: shown via the descriptor's `{any}` formatter, or as
/// raw bytes for the few types that can't be formatted at all.
fn renderReadOnly(field: reflect.FieldDesc, info: reflect.Unsupported, bytes: []const u8) void {
    var buf: [128]u8 = undefined;

    if (info.format) |format| {
        zgui.text("{s}: {s}", .{ field.name, format(bytes, &buf) });
    } else {
        zgui.text("{s}: 0x{s} ({s})", .{ field.name, hexDump(bytes, &buf), @tagName(info.reason) });
    }
}

fn hexDump(bytes: []const u8, buf: []u8) []const u8 {
    var len: usize = 0;
    for (bytes) |byte| {
        const written = std.fmt.bufPrint(buf[len..], "{x:0>2}", .{byte}) catch break;
        len += written.len;
    }
    return buf[0..len];
}

/// Collapses a `{ r, g, b, a }` byte struct into a single colour swatch.
/// Recognised by shape rather than by name, so it covers raylib's Color and
/// anything else shaped like it without this file knowing either type.
fn tryColorEdit(desc: *const reflect.TypeDescriptor, bytes: []u8) bool {
    if (desc.fields.len != 4) return false;

    const channels = [_][]const u8{ "r", "g", "b", "a" };
    for (desc.fields, channels) |field, expected| {
        if (!std.mem.eql(u8, field.name, expected)) return false;
        switch (field.kind) {
            .uint => |access| if (access.max != 255) return false,
            else => return false,
        }
    }

    var rgba: [4]f32 = undefined;
    for (desc.fields, 0..) |field, i| {
        const raw = field.kind.uint.load(field.bytesConst(bytes));
        rgba[i] = @as(f32, @floatFromInt(raw)) / 255.0;
    }

    if (zgui.colorEdit4("color", .{ .col = &rgba })) {
        for (desc.fields, 0..) |field, i| {
            const scaled = @round(std.math.clamp(rgba[i], 0.0, 1.0) * 255.0);
            field.kind.uint.store(field.bytes(bytes), @intFromFloat(scaled));
        }
    }
    return true;
}
