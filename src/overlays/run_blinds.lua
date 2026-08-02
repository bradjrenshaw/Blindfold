-- overlays/run_blinds.lua — the run info Blinds tab as a row of three text
-- items (Small / Big / Boss). The game's three panels are pure renders (state
-- chip, name, boss effect, score, reward, skip tag) with no focusable
-- controls, so the mirror surfaced only the tab strip and Back. Each panel
-- becomes ONE item speaking the panel's rendered content; the tab strip /
-- Back around the row still come from the mirror's discovery.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Mirror = require("overlays.menu_mirror")
local Proxy = require("ui.proxies").Proxy

local M = { id = "run_blinds" }

local function each_child(children, visit)
    local maxn = 0
    for k in pairs(children) do
        if type(k) == "number" and k > maxn then maxn = k end
    end
    for i = 1, maxn do
        if children[i] ~= nil then visit(children[i]) end
    end
    for k, v in pairs(children) do
        if type(k) ~= "number" then visit(v) end
    end
end

-- A run-info blind panel: the panel root carries blind_choice_handler with
-- ref_table.run_info set (UI_definitions.lua:1556). The blind-select screen's
-- panels have run_info = false — and live outside OVERLAY_MENU anyway.
local function is_blind_panel(node)
    local c = node and node.config
    return (c and c.func == "blind_choice_handler"
        and type(c.ref_table) == "table" and c.ref_table.run_info) and true or false
end

-- Panels in render order (Small, Big, Boss — a 'Hide' state omits its panel
-- from the tree, and therefore from us). Descends embedded UIBoxes: tab
-- contents live behind UIT.O (the deck-view lesson).
local function collect_panels(node, depth, out)
    if type(node) ~= "table" or depth > 30 then return end
    if is_blind_panel(node) then out[#out + 1] = node; return end
    local obj = node.config and node.config.object
    if obj and obj.is and UIBox and obj:is(UIBox) and obj.UIRoot then
        collect_panels(obj.UIRoot, depth + 1, out)
    end
    if node.children then
        each_child(node.children, function(ch) collect_panels(ch, depth + 1, out) end)
    end
end

local function inside_panel(node)
    local n, up = node, 0
    while type(n) == "table" and up < 12 do
        if is_blind_panel(n) then return true end
        n = n.parent
        up = up + 1
    end
    return false
end

-- The mirror's fallback for a control-less tab surfaces the WHOLE tab's text
-- as one item (menu_mirror "information panel"); on this tab that item is the
-- tab root CONTAINING the panels — redundant next to the row.
local function contains_panel(node)
    local out = {}
    pcall(collect_panels, node, 0, out)
    return #out > 0
end

function M:handler()
    local ov = G and G.OVERLAY_MENU
    if type(ov) ~= "table" or not ov.UIRoot then return "inactive" end
    local out = {}
    local ok = pcall(collect_panels, ov.UIRoot, 0, out)
    return (ok and #out > 0) and "active" or "inactive"
end

-- The OVERLAY_MENU instance: tab round-trips within the same overlay keep the
-- cursor; a fresh open resets it.
function M:sub_identity()
    return tostring(G and G.OVERLAY_MENU)
end

local function game_loc(key, cat)
    local ok, s = pcall(localize, key, cat)
    return (ok and type(s) == "string" and s ~= "" and s ~= "ERROR") and s or nil
end

-- The tag_container row inside a panel carries the skip Tag object in its
-- ref_table (UI_definitions.lua:1468). Small/Big only; the boss has none.
local function panel_tag(node, depth)
    if type(node) ~= "table" or depth > 12 then return nil end
    local c = node.config
    if c and c.id == "tag_container" and type(c.ref_table) == "table" then
        return c.ref_table
    end
    local found
    if node.children then
        each_child(node.children, function(ch)
            found = found or panel_tag(ch, depth + 1)
        end)
    end
    return found
end

-- One panel's rendered content: name, state, boss effect, score requirement,
-- reward (omitted under no_blind_reward, matching the render), then the skip
-- tag ("or Skip Reward: <tag>", description behind the description toggle).
local function panel_text(panel)
    local ty = panel.config and panel.config.id
    local rr = G and G.GAME and G.GAME.round_resets
    local key = ty and rr and rr.blind_choices and rr.blind_choices[ty]
    local cfg = key and G.P_BLINDS and G.P_BLINDS[key] or nil
    local parts = {}
    parts[#parts + 1] = Proxy.blind_name(cfg) or tostring(ty)
    local st = ty and rr and rr.blind_states and rr.blind_states[ty]
    if st == "Select" then st = "Current" end   -- the game's own render mapping
    local sw = st and game_loc(st, "blind_states")
    if sw then parts[#parts + 1] = sw end
    local eff = Proxy.blind_effect(cfg)
    if eff then parts[#parts + 1] = eff end
    local req = Proxy.blind_requirement(cfg)
    if req then parts[#parts + 1] = req end
    local mods = G and G.GAME and G.GAME.modifiers
    local no_reward = ty and mods and mods.no_blind_reward and mods.no_blind_reward[ty]
    if not no_reward and cfg and type(cfg.dollars) == "number" and cfg.dollars > 0 then
        parts[#parts + 1] = Message.localized("BLIND.REWARD", { dollars = tostring(cfg.dollars) }):resolve()
    end
    local tag = panel_tag(panel, 0)
    if tag then
        local tname
        if tag.key then
            local ok, n = pcall(localize, { type = "name_text", key = tag.key, set = "Tag" })
            if ok and type(n) == "string" and n ~= "" then tname = n end
        end
        local lead = (game_loc("k_or") or "or") .. " " .. (game_loc("b_skip_reward") or "Skip Reward")
        parts[#parts + 1] = tname and (lead .. ": " .. tname) or lead
        if tname and Proxy.announce_enabled("description") then
            local desc = Proxy.tag_description(tag)
            if desc then parts[#parts + 1] = desc end
        end
    end
    return table.concat(parts, ", ")
end

function M:build(b)
    b:capture_input()
    local ov = G and G.OVERLAY_MENU
    if not ov then return end

    local panels = {}
    pcall(collect_panels, ov.UIRoot, 0, panels)

    -- Everything else on the screen (tab strip, Back), via the mirror's
    -- discovery — minus anything inside the panels the row replaces.
    local others = {}
    local ok, gathered = pcall(Mirror.gather, { ov })
    if ok then
        for _, n in ipairs(gathered) do
            local drop = type(n) == "table" and n.UIT
                and (inside_panel(n) or contains_panel(n))
            if not drop then others[#others + 1] = n end
        end
    end
    local other_ids = {}
    for i, n in ipairs(others) do
        other_ids[i] = Id.referenced(n, "o:" .. i)
        b:add_node(other_ids[i], Mirror.vtable_for(n))
    end

    -- The row: one item per rendered panel, left/right across it.
    local ids = {}
    for i, p in ipairs(panels) do
        local ty = (p.config and p.config.id) or ("p" .. i)
        ids[i] = Id.structural("b:" .. tostring(ty))
        b:add_node(ids[i], { label = function(ctx)
            ctx.message:fragment(Message.raw(panel_text(p)))
        end })
        if i > 1 then
            b:connect(ids[i - 1], "right", ids[i])
            b:connect(ids[i], "left", ids[i - 1])
        end
    end

    -- Stitch: the tab strip sits above the row, the rest (Back) below.
    local top, below = other_ids[1], other_ids[2]
    if #ids > 0 then
        if top then
            b:connect(top, "down", ids[1])
            for _, id in ipairs(ids) do b:connect(id, "up", top) end
        end
        if below then
            b:connect(below, "up", ids[1])
            for _, id in ipairs(ids) do b:connect(id, "down", below) end
        end
    end
    for i = 2, #other_ids - 1 do
        b:connect(other_ids[i], "down", other_ids[i + 1])
        b:connect(other_ids[i + 1], "up", other_ids[i])
    end

    -- Land on the tab strip, like every tabbed menu.
    local tab_strip
    for i, n in ipairs(others) do
        local fa = n.config and n.config.focus_args
        if fa and fa.type == "tab" then tab_strip = other_ids[i]; break end
    end
    if tab_strip then
        b:set_start(tab_strip)
    elseif ids[1] then
        b:set_start(ids[1])
    elseif other_ids[1] then
        b:set_start(other_ids[1])
    end
end

return M
