-- overlay/graph.lua — graph nodes + the builder overlays declare controls into
-- (port of Tanglebeep's GraphNode/GraphBuilder, from Factorio Access menu.lua).
--
-- A NODE is { id, vtable, trans = { up/down/left/right -> transition } }; a
-- TRANSITION is { to = <structural key>, label = fn(ctx)? } (the label speaks
-- only while crossing that edge — used for row/lane announcements). A VTABLE is
-- a plain table of behaviors: label (required; fn(ctx) appending speech to
-- ctx.message) plus optional on_click(ctx, mods), on_horizontal_adjust(ctx,
-- sign, large), and future action slots (on_read_info, ...).
--
-- Two construction styles, never mixed in one build:
--   RAW GRAPH  add_node/connect/set_start — arbitrary nodes + directional edges.
--   MENU SUGAR start_row/add_item/add_label/add_clickable/end_row — rows give
--     2-D navigation (left/right within a row, up/down between rows). Two rows
--     sharing a non-nil row key get COLUMN navigation: up/down preserves the
--     position within the row instead of snapping to the first item.
--     Extensions over the C# original: start_row takes an optional row LABEL
--     fn(ctx), spoken as the transition label when vertical navigation ENTERS
--     the row from a different row (the container/lane announcement), and an
--     optional opts table ({ wrap = true } wraps left/right around the ends).
--
-- build() returns a render { nodes = { [key] = node }, start_key,
-- force_capture } or nil when empty (the engine treats that as closed).
local Builder = {}
Builder.__index = Builder

function Builder.new()
    return setmetatable({
        rows = {},          -- menu mode: { { items = {entry...}, key = ?, label = fn? } ... }
        current_row = nil,
        raw_order = {},     -- raw mode: declared ids in order
        raw_nodes = {},     -- [key] = { id, vtable }
        raw_edges = {},     -- { from = id, dir = d, to = id }
        start_id = nil,
        force_capture = false,
    }, Builder)
end

local function check_vtable(vtable)
    assert(type(vtable) == "table" and type(vtable.label) == "function",
        "a control must have a label function")
end

-- --- Raw graph API -----------------------------------------------------------

function Builder:add_node(id, vtable)
    check_vtable(vtable)
    assert(self.raw_nodes[id.key] == nil, "duplicate control id")
    self.raw_order[#self.raw_order + 1] = id
    self.raw_nodes[id.key] = { id = id, vtable = vtable }
    return self
end

-- In raw mode: a directional edge between declared nodes. In MENU mode: an
-- edge OVERRIDE applied after the rows are lowered — set a custom transition,
-- or pass to = nil to REMOVE the lowered edge (e.g. a column with nothing
-- beneath it stops instead of falling to another column).
function Builder:connect(from, dir, to)
    self.raw_edges[#self.raw_edges + 1] = { from = from, dir = dir, to = to }
    return self
end

-- Focus lands here when there is no prior position; defaults to the first node.
function Builder:set_start(id)
    self.start_id = id
    return self
end

-- --- Menu sugar --------------------------------------------------------------

-- row_opts: { wrap = true } makes left/right wrap around the row's ends;
-- { enter = i } makes vertical navigation arriving from a DIFFERENTLY-keyed
-- row land on item i instead of the first item (e.g. the current blind).
function Builder:start_row(row_key, row_label, row_opts)
    assert(self.current_row == nil, "cannot start a row while another is open")
    self.current_row = { items = {}, key = row_key, label = row_label,
        wrap = row_opts and row_opts.wrap,
        enter = row_opts and row_opts.enter }
    return self
end

function Builder:end_row()
    assert(self.current_row ~= nil, "no row to end")
    assert(#self.current_row.items > 0, "row cannot be empty")
    self.rows[#self.rows + 1] = self.current_row
    self.current_row = nil
    return self
end

-- Add a control to the current row (or as its own single-item row).
function Builder:add_item(id, vtable)
    check_vtable(vtable)
    local entry = { id = id, vtable = vtable }
    if self.current_row then
        self.current_row.items[#self.current_row.items + 1] = entry
    else
        self.rows[#self.rows + 1] = { items = { entry } }
    end
    return self
end

-- A read-only control that just speaks its label.
function Builder:add_label(id, label)
    return self:add_item(id, { label = label })
end

-- A control that speaks a label and runs on_click on activation.
function Builder:add_clickable(id, label, on_click)
    return self:add_item(id, { label = label, on_click = on_click })
end

-- Declare that this overlay owns keyboard input (a declared property, not
-- inferred from node count). Non-capturing overlays leave input to the game.
function Builder:capture_input()
    self.force_capture = true
    return self
end

-- --- Lowering ----------------------------------------------------------------

-- Where vertical navigation from position `pos` in row `from` lands in row
-- `to`: the same position when the rows share a key (column nav); else the
-- row's declared enter item, else the first item.
local function vertical_target(from, to, pos)
    if from.key ~= nil and to.key ~= nil and from.key == to.key and pos <= #to.items then
        return to.items[pos].id
    end
    if to.enter and to.items[to.enter] then return to.items[to.enter].id end
    return to.items[1].id
end

local function build_menu(self)
    assert(self.current_row == nil, "unclosed row - call end_row()")
    if #self.rows == 0 then return nil end

    local render = { nodes = {} }
    for _, row in ipairs(self.rows) do
        for _, item in ipairs(row.items) do
            assert(render.nodes[item.id.key] == nil, "duplicate control id")
            render.nodes[item.id.key] = { id = item.id, vtable = item.vtable, trans = {} }
        end
    end

    -- Honor an explicit set_start naming a real node; else first item, first row.
    render.start_key = (self.start_id and render.nodes[self.start_id.key])
        and self.start_id.key or self.rows[1].items[1].id.key

    for row_idx, row in ipairs(self.rows) do
        for pos, item in ipairs(row.items) do
            local node = render.nodes[item.id.key]
            if row_idx > 1 then
                local above = self.rows[row_idx - 1]
                node.trans.up = { to = vertical_target(row, above, pos).key, label = above.label }
            end
            if row_idx < #self.rows then
                local below = self.rows[row_idx + 1]
                node.trans.down = { to = vertical_target(row, below, pos).key, label = below.label }
            end
            if pos > 1 then node.trans.left = { to = row.items[pos - 1].id.key }
            elseif row.wrap and #row.items > 1 then node.trans.left = { to = row.items[#row.items].id.key } end
            if pos < #row.items then node.trans.right = { to = row.items[pos + 1].id.key }
            elseif row.wrap and #row.items > 1 then node.trans.right = { to = row.items[1].id.key } end
        end
    end

    -- Apply explicit edge overrides on top of the lowered rows (see connect).
    for _, e in ipairs(self.raw_edges) do
        local from = render.nodes[e.from.key]
        if from then
            if e.to == nil then
                from.trans[e.dir] = nil
            elseif render.nodes[e.to.key] then
                from.trans[e.dir] = { to = e.to.key }
            end
        end
    end
    return render
end

local function build_raw(self)
    local render = { nodes = {} }
    for _, id in ipairs(self.raw_order) do
        local e = self.raw_nodes[id.key]
        render.nodes[id.key] = { id = e.id, vtable = e.vtable, trans = {} }
    end
    for _, edge in ipairs(self.raw_edges) do
        -- Skip edges to/from controls that were never declared (and nil-to
        -- removals, which are only meaningful as menu-mode overrides).
        if edge.to and render.nodes[edge.from.key] and render.nodes[edge.to.key] then
            render.nodes[edge.from.key].trans[edge.dir] = { to = edge.to.key }
        end
    end
    render.start_key = self.start_id and self.start_id.key or self.raw_order[1].key
    return render
end

function Builder:build()
    local has_raw = next(self.raw_nodes) ~= nil
    local has_menu = #self.rows > 0 or self.current_row ~= nil
    assert(not (has_raw and has_menu),
        "cannot mix raw graph (add_node/connect) with menu rows in one build")
    local render = has_raw and build_raw(self) or build_menu(self)
    if render then render.force_capture = self.force_capture end
    return render
end

return Builder
