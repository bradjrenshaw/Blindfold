-- overlays/run_stakes.lua — Run Info's Stake tab as Steamodded rebuilds it
-- (G.UIDEF.SMODS_current_stake; vanilla's tab is untouched). Its layout:
-- an "Applied stakes" title, the run's stake as a chip sprite beside its
-- description, then the stakes it includes in a scroll box (most recent
-- first) with a scrollbar. The stakes are sprites, the descriptions plain
-- text, so the menu mirror read one unnamed blob plus an unlabeled
-- scrollbar. Here: the title, then one item per stake — its name (the chip
-- art identifies it), with the description it shows as the deferred
-- follow-up — then Back. The scrollbar is skipped: every stake is listed.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Proxy = require("ui.proxies").Proxy
local Mirror = require("overlays.menu_mirror")

local M = { id = "run_stakes" }

local function kids_of(n)
    local kids, maxn = {}, 0
    for k in pairs(n.children or {}) do
        if type(k) == "number" and k > maxn then maxn = k end
    end
    for k = 1, maxn do
        if n.children[k] ~= nil then kids[#kids + 1] = n.children[k] end
    end
    return kids
end

-- The chosen Run Info tab is Steamodded's stake tab.
local function on_stake_tab()
    local ov = G and G.OVERLAY_MENU
    local def = G and G.UIDEF and G.UIDEF.SMODS_current_stake
    if type(ov) ~= "table" or not ov.UIRoot or type(def) ~= "function" then return false end
    local found = false
    local function walk(n, depth)
        if found or type(n) ~= "table" or depth > 20 then return end
        local c = n.config
        if c and c.button == "change_tab" and c.chosen and type(c.ref_table) == "table"
            and c.ref_table.tab_definition_function == def then
            found = true
            return
        end
        for _, ch in ipairs(kids_of(n)) do walk(ch, depth + 1) end
    end
    walk(ov.UIRoot, 0)
    return found
end

-- The run's stake chain in display order: the run's own stake first, then
-- the stakes it applies, most recent first (as SMODS_current_stake orders
-- them: the chain in pool order, own stake last, the rest reversed above).
local function stakes()
    local pool = G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake
    local own = pool and G.GAME and pool[G.GAME.stake]
    if not own then return {} end
    local chain = {}
    pcall(function() chain = SMODS.build_stake_chain(G.P_STAKES[own.key]) or {} end)
    local applied = {}
    for i, v in ipairs(pool) do
        if chain[i] and v.key ~= own.key then applied[#applied + 1] = v.key end
    end
    local out = { own.key }
    for i = #applied, 1, -1 do out[#out + 1] = applied[i] end
    return out
end

-- The description as the tab shows it: the stake's loc text with its
-- loc_vars, minus the last line ("Applies all previous Stakes") when it
-- applies others.
local function stake_desc(key)
    local center = G.P_STAKES and G.P_STAKES[key]
    if not center then return nil end
    return Proxy.with_built(function()
        local res = {}
        if type(center.loc_vars) == "function" then res = center:loc_vars({}) or {} end
        local nodes = {}
        localize({ type = "descriptions", key = res.key or center.key, set = res.set or center.set,
            nodes = nodes, vars = res.vars or {} })
        if center.applied_stakes and #center.applied_stakes > 0 then nodes[#nodes] = nil end
        return nodes
    end, function(nodes)
        if type(nodes) ~= "table" then return nil end
        local parts = {}
        Proxy.collect_def_text(nodes, parts)
        return #parts > 0 and table.concat(parts, " ") or nil
    end)
end

function M:handler()
    local ok, on = pcall(on_stake_tab)
    return (ok and on) and "active" or "inactive"
end

function M:sub_identity()
    return tostring(G and G.OVERLAY_MENU)
end

function M:build(b)
    b:capture_input()
    local items = Mirror.gather({ G.OVERLAY_MENU })

    -- Tab strip first.
    local strip
    for _, n in ipairs(items) do
        local fa = n.config and n.config.focus_args
        if fa and fa.type == "tab" then strip = n; break end
    end
    if strip then b:add_item(Id.referenced(strip, "tabs"), Mirror.vtable_for(strip)) end

    -- The tab's title (Steamodded renders it as a fixed English string).
    b:add_label(Id.structural("title"), function(ctx)
        ctx.message:fragment(Message.raw("Applied stakes"))
    end)

    for i, key in ipairs(stakes()) do
        b:add_item(Id.structural("stake:" .. key), {
            label = function(ctx)
                local ok, name = pcall(localize, { type = "name_text", set = "Stake", key = key })
                if ok and type(name) == "string" and name ~= "" and name ~= "ERROR" then
                    ctx.message:fragment(Message.raw(name))
                end
            end,
            deferred = function()
                if not Proxy.announce_enabled("description") then return nil end
                local d = stake_desc(key)
                return d and Message.raw(d) or nil
            end,
        })
    end

    -- Back (and anything else), minus the strip, the scroll box's text
    -- panel and its scrollbar.
    local r = 0
    for _, n in ipairs(items) do
        local c = n.config or {}
        local fa = c.focus_args
        local text_panel = G.UIT and n.UIT == G.UIT.ROOT and not (c.button or fa)
        if n ~= strip and not text_panel and not (fa and fa.type == "scrollbar") then
            r = r + 1
            b:add_item(Id.referenced(n, "r:" .. r), Mirror.vtable_for(n))
        end
    end
    if strip then b:set_start(Id.referenced(strip, "tabs")) end
end

return M
