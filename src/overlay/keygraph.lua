-- overlay/keygraph.lua — the flagship: a directed graph of controls with
-- up/down/left/right transitions (port of Tanglebeep's KeyGraph, from Factorio
-- Access's key-graph.lua). Everything is rebuilt from a render callback on each
-- operation (immediate mode); focus persists via an external STATE table:
--   state = { cur = <control id>, key_order = { key... }, suggested = <id>? }
--
-- Two invariants carried over from the original:
--
-- DOWN-RIGHT TOTAL ORDER (compute_order): starting at the start node, go right
-- until stuck, queueing each down; this visits a planar UI in reading order.
-- The constraint on overlays is that down+right must reach every node (up/left
-- may do anything). The order drives focus recovery (and later, search).
--
-- FOCUS RECOVERY ON REBUILD (reconcile): if the focused control vanished, land
-- on the nearest survivor rather than jumping to the start. Recovery tiers:
--   1. same backing object (id.ref, identity) — follows an object that MOVED;
--   2. same structural key — follows a control whose backing was REBUILT;
--   3. nearest survivor walking the previous order backward.
--
-- One KeyGraph wraps one render callback + state for a single operation; the
-- dispatcher constructs a fresh one each tick (state lives in its cache).
local KeyGraph = {}
KeyGraph.__index = KeyGraph

function KeyGraph.new(render_cb, state)
    local self = setmetatable({
        render_cb = render_cb,
        state = state,
        current = nil,       -- the most recent render, or nil
    }, KeyGraph)
    -- The controller callbacks receive in ctx (ctx.controller): a node action
    -- can close the overlay or ask for a silent focus move on the next render.
    self.controller = {
        closed = false,
        close = function(c) c.closed = true end,
        suggest_move = function(_, id) state.suggested = id end,
    }
    return self
end

-- The down-right total order: go right until stuck (recording each node),
-- queue every down for a later pass, repeat. Returns a list of keys.
function KeyGraph.compute_order(render)
    local order, seen, fringe = {}, {}, { render.start_key }
    local i = 1
    while i <= #fringe do
        local k = fringe[i]
        while not seen[k] do
            seen[k] = true
            order[#order + 1] = k
            local n = render.nodes[k]
            if not n then break end
            local d = n.trans.down
            if d then fringe[#fringe + 1] = d.to end
            local r = n.trans.right
            if not r then break end
            k = r.to
        end
        i = i + 1
    end
    return order
end

local function index_of(list, key)
    for i, k in ipairs(list) do
        if k == key then return i end
    end
    return nil
end

-- Move focus from the cached state.cur to a valid control in this render, then
-- recompute the traversal order.
function KeyGraph.reconcile(render, state)
    -- Honor a pending suggested move first, if its target still exists.
    if state.suggested then
        local n = render.nodes[state.suggested.key]
        if n then state.cur = n.id end
        state.suggested = nil
    end

    local old = state.cur
    local resolved = nil
    if old then
        -- Tier 1: the same backing object, even if its structural key changed.
        if old.ref ~= nil then
            for _, n in pairs(render.nodes) do
                if n.id.ref == old.ref then resolved = n.id; break end
            end
        end
        -- Tier 2: the same structural key, even if the backing was rebuilt.
        if not resolved then
            local n = render.nodes[old.key]
            if n then resolved = n.id end
        end
        -- Fallback: nearest survivor walking the previous order backward.
        if not resolved and state.key_order then
            local oi = index_of(state.key_order, old.key)
            if oi then
                for i = oi, 1, -1 do
                    local n = render.nodes[state.key_order[i]]
                    if n then resolved = n.id; break end
                end
            end
        end
    end
    -- Nothing matched (or first render): the start node.
    if not resolved then
        local start = render.nodes[render.start_key]
        resolved = start and start.id or nil
    end

    state.cur = resolved
    state.key_order = KeyGraph.compute_order(render)
end

-- Rebuild the render and reconcile focus into it. Returns false if the render
-- callback closed the graph or produced nothing (caller treats as closed).
-- The render callback only declares controls; it must not append speech.
function KeyGraph:rerender(ctx)
    ctx.controller = self.controller
    self.current = self.render_cb(ctx)
    if self.controller.closed or not self.current or next(self.current.nodes) == nil then
        self.current = nil
        return false
    end
    KeyGraph.reconcile(self.current, self.state)
    return true
end

local function read_label_of(self, key, ctx)
    local node = key and self.current.nodes[key]
    if node and node.vtable.label then node.vtable.label(ctx) end
end

-- Append the focused control's label to the message (re-renders first).
function KeyGraph:read_current_label(ctx)
    if not self:rerender(ctx) then return end
    read_label_of(self, self.state.cur and self.state.cur.key, ctx)
end

-- Move one step in dir. On a real move, speaks the transition label (if any)
-- then the destination label; at an edge, re-reads the current label.
-- Returns true on a real move.
function KeyGraph:move(ctx, dir)
    if not self:rerender(ctx) then return false end
    local node = self.state.cur and self.current.nodes[self.state.cur.key]
    if not node then return false end

    local t = node.trans[dir]
    local new_node = t and self.current.nodes[t.to]
    if not new_node or new_node == node then
        -- Edge: nothing to move to. Re-read the current label.
        read_label_of(self, self.state.cur.key, ctx)
        return false
    end

    if t.label then t.label(ctx) end
    if new_node.vtable.label then new_node.vtable.label(ctx) end
    self.state.cur = new_node.id
    return true
end

-- Home/End: the INNERMOST structure wins (Brad) — inside a multi-item row,
-- jump to its first/last item; anywhere else (vertical lists, single-item
-- rows, raw graphs) jump to the graph's first/last node in the down-right
-- order. Row membership comes from the builder's row_edges metadata, which
-- also makes wrapped rows unambiguous (their transitions form an edgeless
-- cycle that a directional walk could never terminate on meaningfully).
-- Speaks only the landing control; returns true if focus moved.
function KeyGraph:move_to_edge(ctx, dir)
    if not self:rerender(ctx) then return false end
    local cur = self.state.cur and self.state.cur.key
    local node = cur and self.current.nodes[cur]
    if not node then return false end
    local target
    if node.row_edges and node.row_edges.size > 1 then
        target = (dir == "left") and node.row_edges.first or node.row_edges.last
    else
        local order = self.state.key_order
        if not order or #order == 0 then order = KeyGraph.compute_order(self.current) end
        target = (dir == "left") and order[1] or order[#order]
    end
    local tnode = target and self.current.nodes[target]
    if not tnode then
        read_label_of(self, cur, ctx)
        return false
    end
    local moved = target ~= cur
    self.state.cur = tnode.id
    read_label_of(self, target, ctx)
    return moved
end

-- Activate the focused control; defaults to re-reading the label. Returns
-- true when a real on_click ran (false = label fallback), so the caller knows
-- whether the spoken text was the node's label.
function KeyGraph:click(ctx, mods)
    if not self:rerender(ctx) then return false end
    local node = self.state.cur and self.current.nodes[self.state.cur.key]
    if not node then return false end
    if node.vtable.on_click then
        node.vtable.on_click(ctx, mods or {})
        return true
    end
    if node.vtable.label then node.vtable.label(ctx) end
    return false
end

-- If the focused control declares on_horizontal_adjust (a value control such
-- as a slider), invoke it and return true; else return false so the caller
-- does a normal move. sign is -1 (left/decrease) or +1; large = coarse step.
function KeyGraph:try_horizontal_adjust(ctx, sign, large)
    if not self:rerender(ctx) then return false end
    local node = self.state.cur and self.current.nodes[self.state.cur.key]
    if not node or not node.vtable.on_horizontal_adjust then return false end
    node.vtable.on_horizontal_adjust(ctx, sign, large)
    return true
end

-- Invoke a named vtable action slot ("on_read_info", ...) on the focused
-- control; falls back to re-reading the label so the key never feels dropped.
-- Returns true when a real action ran (false = label fallback).
function KeyGraph:invoke_node_action(ctx, slot)
    if not self:rerender(ctx) then return false end
    local node = self.state.cur and self.current.nodes[self.state.cur.key]
    if not node then return false end
    local action = node.vtable[slot]
    if action then
        action(ctx)
        return true
    end
    if node.vtable.label then node.vtable.label(ctx) end
    return false
end

-- Tier-1 focus sync from the game: if a node's backing object is ref, move
-- focus there (silently). Returns true if focus changed.
function KeyGraph:focus_by_reference(ref)
    if ref == nil or not self.current then return false end
    for _, n in pairs(self.current.nodes) do
        if n.id.ref == ref then
            local changed = not self.state.cur or self.state.cur.key ~= n.id.key
            self.state.cur = n.id
            return changed
        end
    end
    return false
end

return KeyGraph
