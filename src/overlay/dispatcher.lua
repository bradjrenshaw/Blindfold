-- overlay/dispatcher.lua — drives the overlay system one tick at a time (port
-- of Tanglebeep's OverlayDispatcher).
--
-- Holds an ordered list of overlays (last registered = top of the stack) and,
-- per overlay id, an ephemeral focus cache (the KeyGraph state). Each tick it
-- polls overlays top-down for the first non-"inactive" verdict, builds the
-- winner's graph, reconciles focus, and either applies a player navigation
-- command (our own key handling) or speaks a focus change.
--
-- Overlay contract: { id = <string>, handler = fn(self) -> verdict,
-- build = fn(self, builder), sub_identity = fn(self) -> string? }. Verdicts:
--   "active"   — driving a screen: build and process.
--   "sleeping" — conceptually open but CEDING the screen for now (a game menu
--                on top of the play screen; a game-driven state the legacy
--                layer handles). Keeps the id's focus cache; the legacy
--                fallback may speak/drive meanwhile.
--   "pending"  — the screen is MINE but not ready yet (its content is still
--                materializing). Keeps the cache like sleeping, but reports
--                the dispatcher as engaged: the legacy layer stays quiet and
--                nav/confirm keys are swallowed instead of leaking to the
--                engine, so nothing announces or activates mid-construction.
--   "inactive" / nil — not driving; the id's cache is cleared.
--
-- sub_identity marks in-place content swaps: when it changes while the id
-- stays active, treat as a fresh open (reset focus to the start node, ignore a
-- same-frame nav command).
--
-- tick(command) returns nil or a result table:
--   { message = <string?>, focus_ref = <backing object?>, moved/clicked/entered }
-- The caller speaks the message and syncs whatever follows focus (buffers,
-- deferred descriptions). Not ported yet (unused so far): auxiliary overlays,
-- game-focus following for non-capturing overlays, per-action key registry
-- beyond NODE_ACTIONS.
local require = ...
local KeyGraph = require("overlay.keygraph")
local Builder = require("overlay.graph")
local MB = require("overlay.message_builder")

local D = {
    overlays = {},
    cache = {},        -- [id] = { state = KeyGraph state, overlay = overlay }
    subid = {},        -- [id] = last reported sub-identity
    active_last = nil, -- id active last tick (sleeping/pending count as active)
    last_spoken = nil, -- structural key last spoken via the no-command path
    _captures = false,
    _pending = false,
}

-- Command kinds that invoke a named vtable action slot on the focused control.
-- Adding an action key = a vtable slot + one entry here + an input binding.
local NODE_ACTIONS = {
    read_info = "on_read_info",
    sell = "on_sell",
    use = "on_use",
    grab = "on_grab",   -- pick up / place (reordering)
}

-- Register an overlay. The last one registered sits at the top of the stack.
function D.register(overlay)
    D.overlays[#D.overlays + 1] = overlay
end

-- True when the active overlay declared input ownership (builder:capture_input)
-- on its last build. The input layer reads this to route keys to us or leave
-- them to the game. One frame stale is fine for a persistent screen.
function D.captures()
    return D._captures
end

-- True while an overlay owns or is settling into the screen (captures, or
-- "pending"). The legacy focus-follower stays quiet and overlay-command keys
-- are swallowed rather than leaking to the engine.
function D.engaged()
    return D._captures or D._pending
end

local function find_active()
    for i = #D.overlays, 1, -1 do
        local o = D.overlays[i]
        local ok, verdict = pcall(o.handler, o)
        if ok and verdict and verdict ~= "inactive" then return o, verdict end
    end
    return nil, "inactive"
end

local function render_cb_for(overlay)
    return function(ctx)
        local b = Builder.new()
        overlay:build(b)
        return b:build()
    end
end

-- Results carry `spoke_label = true` whenever what was spoken is the focused
-- node's LABEL (a move, an edge re-read, a fallback re-read from confirm or an
-- action key, a follow announce) — the caller then appends the node's deferred
-- follow-up (description / position), so every label announcement reads the
-- same regardless of which key produced it.
local function apply_nav(graph, state, ctx, message, command)
    local kind = command.kind

    local slot = NODE_ACTIONS[kind]
    if slot then
        local acted = graph:invoke_node_action(ctx, slot)
        return { message = message:build(), focus_ref = state.cur and state.cur.ref,
            spoke_label = not acted }
    end

    if kind == "confirm" then
        local acted = graph:click(ctx, command.mods)
        D.last_spoken = state.cur and state.cur.key
        return { message = message:build(), focus_ref = state.cur and state.cur.ref,
            clicked = true, spoke_label = not acted }
    end

    -- A value control (a slider) intercepts horizontal input to adjust instead
    -- of moving focus; vertical input always navigates.
    local dir = command.dir
    if (dir == "left" or dir == "right")
        and graph:try_horizontal_adjust(ctx, dir == "right" and 1 or -1, kind == "move_to_edge") then
        return { message = message:build() }
    end

    local moved
    if kind == "move_to_edge" then
        moved = graph:move_to_edge(ctx, dir)
    else
        moved = graph:move(ctx, dir)
    end
    -- A move always speaks a label: the destination's, or the edge re-read.
    D.last_spoken = state.cur and state.cur.key
    return { message = message:build(), focus_ref = state.cur and state.cur.ref,
        moved = moved, spoke_label = true }
end

local function build_and_process(overlay, command)
    local entry = D.cache[overlay.id]
    if not entry then
        entry = { state = {}, overlay = overlay }
        D.cache[overlay.id] = entry
    end
    local state = entry.state

    -- Generation check: an in-place content swap behaves as a fresh open —
    -- focus resets to the start node and the new content wins over a
    -- same-frame keypress.
    if overlay.sub_identity then
        local now = overlay:sub_identity()
        local prev = D.subid[overlay.id]
        D.subid[overlay.id] = now
        if prev ~= nil and prev ~= now then
            state.cur = nil
            D.last_spoken = nil
            command = nil
        end
    end

    local message = MB.new()
    local ctx = { message = message, mods = (command and command.mods) or {} }
    local graph = KeyGraph.new(render_cb_for(overlay), state)

    if not graph:rerender(ctx) then
        -- The overlay built nothing this tick — treat as closed, drop its cache.
        D.cache[overlay.id] = nil
        D.subid[overlay.id] = nil
        D.active_last = nil
        D.last_spoken = nil
        D._captures = false
        return nil
    end

    D._captures = graph.current.force_capture and true or false

    if command then
        return apply_nav(graph, state, ctx, message, command)
    end

    -- No command: speak the focus label only when it changed (a fresh open, a
    -- reconcile jump after the focused control vanished, or a suggested move).
    local cur = state.cur
    if not cur or cur.key == D.last_spoken then return nil end
    D.last_spoken = cur.key
    local node = graph.current.nodes[cur.key]
    if node and node.vtable.label then node.vtable.label(ctx) end
    return { message = message:build(), focus_ref = cur.ref, entered = true, spoke_label = true }
end

-- Run one frame, optionally applying a player navigation command:
--   { kind = "move"|"move_to_edge"|"confirm"|<NODE_ACTIONS key>,
--     dir = "up"|"down"|"left"|"right" (moves only), mods = {ctrl,shift,alt}? }
-- Must run on the main thread (overlay callbacks read live game state).
function D.tick(command)
    local overlay, verdict = find_active()
    local active_id = overlay and overlay.id or nil

    -- Cache lifecycle: an id's cache lives while its OWN handler stays
    -- non-inactive — not merely while it is on top of the stack. So a run
    -- screen under an options overlay (reporting "sleeping") keeps the
    -- player's position through the menu round-trip, while a screen that
    -- actually closed (reporting "inactive") clears. This extends the C#
    -- original, which cleared whenever another id took over.
    for id, entry in pairs(D.cache) do
        if id ~= active_id then
            local ok, v = pcall(entry.overlay.handler, entry.overlay)
            if not ok or not v or v == "inactive" then
                D.cache[id] = nil
                D.subid[id] = nil
            end
        end
    end
    if D.active_last ~= active_id then D.last_spoken = nil end
    D.active_last = active_id

    D._pending = (verdict == "pending") or false
    if not overlay or verdict == "sleeping" or verdict == "pending" then
        D._captures = false
        return nil
    end

    return build_and_process(overlay, command)
end

-- Dev introspection (F8): the active overlay as the mod sees it — nodes in
-- traversal order with spoken labels, the cursor, and the directional links.
-- Read-only: builds a throwaway render, does not disturb the live cache.
function D.describe()
    local overlay, verdict = find_active()
    if not overlay then return "overlay: none" end
    if verdict == "sleeping" then return "overlay: " .. tostring(overlay.id) .. " (sleeping)" end

    local render = render_cb_for(overlay)({ message = MB.new(), mods = {} })
    if not render then return "overlay: " .. tostring(overlay.id) .. " (empty)" end

    local entry = D.cache[overlay.id]
    local cur = entry and entry.state.cur and entry.state.cur.key or render.start_key
    local function label_of(node)
        local m = MB.new()
        local ok = pcall(node.vtable.label, { message = m, mods = {} })
        return ok and (m:build() or "") or "<label error>"
    end

    local lines = { "overlay: " .. tostring(overlay.id)
        .. " (capture=" .. tostring(render.force_capture or false) .. ")" }
    for _, key in ipairs(KeyGraph.compute_order(render)) do
        local node = render.nodes[key]
        if node then
            local parts = { (key == cur) and "> \"" or "  \"", label_of(node), "\"" }
            for dir, t in pairs(node.trans) do
                local dest = render.nodes[t.to]
                parts[#parts + 1] = "  " .. dir .. "->\"" .. (dest and label_of(dest) or "?") .. "\""
            end
            lines[#lines + 1] = table.concat(parts)
        end
    end
    return table.concat(lines, "\n")
end

return D
