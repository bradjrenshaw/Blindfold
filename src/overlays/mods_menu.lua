-- overlays/mods_menu.lua — Steamodded's Mods menu (create_UIBox_mods_button),
-- the "Mods" tab's mod list. Each mod renders as a card (icon, name in a
-- scrolling DynaText, version / "(Lovely Mod)", "By: authors") whose click
-- opens the mod's page, an enable checkbox beside it, and for mods with a
-- config tab a gear button under the checkbox. The mirror read those as a
-- bare version ("3.6.1, button"), unnamed checkboxes and an empty control.
--
-- Here each mod is a ROW: the card (name, version or Lovely Mod, authors),
-- then its enable checkbox and its config button, both named for the mod;
-- left/right moves within the mod, up/down between mods. Everything else on
-- the screen (tabs, the heading — which opens the Mods folder — the page
-- cycle, Back) comes through the mirror in order. Inert without Steamodded.
--
-- The menu's Credits tab is claimed too: its text ("Mod Loader developed
-- by Steamo...", the bug-report line) sits around one button, and the
-- mirror reads controls only — here it reads in order, lines and button.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Factory = require("ui.factory")
local Mirror = require("overlays.menu_mirror")

local M = { id = "mods_menu" }

local PREFIX = "openModUI_"

local function game_loc(key)
    local ok, s = pcall(localize, key)
    return (ok and type(s) == "string" and s ~= "" and s ~= "ERROR") and s or nil
end

-- The mod id a control belongs to, and which part it is.
local function classify(n)
    local c = n.config or {}
    if type(c.button) == "string" and c.button:sub(1, #PREFIX) == PREFIX then
        return c.button:sub(#PREFIX + 1), (c.page == "config") and "config" or "card"
    end
    local rt = c.ref_table
    if c.button == "toggle_button" and type(rt) == "table" and type(rt.ref_table) == "table"
        and rt.ref_value == "should_enable" and rt.ref_table.id then
        return rt.ref_table.id, "toggle"
    end
    return nil
end

local function mod_info(id)
    return type(SMODS) == "table" and SMODS.Mods and SMODS.Mods[id] or nil
end

-- The name as the card shows it (a mod's localized name, else its name).
local function mod_name(id)
    local m = mod_info(id)
    if not m then return id end
    local ok, s = pcall(function()
        local descs = G.localization.descriptions.Mod or {}
        if descs[id] then return localize({ type = "name_text", set = "Mod", key = id }) end
    end)
    if ok and type(s) == "string" and s ~= "" and s ~= "ERROR" then return s end
    return m.name or id
end

-- The card's text lines, as rendered: name, then "(Lovely Mod)" or the
-- version, then "By: authors".
local function card_text(id)
    local m = mod_info(id) or {}
    local parts = { mod_name(id) }
    if m.lovely_only then
        parts[#parts + 1] = game_loc("b_lovely_mod")
    elseif m.version and m.version ~= "0.0.0" then
        parts[#parts + 1] = tostring(m.version)
    end
    if not m.lovely_only and m.author then
        -- (Steamodded's concatAuthors is local: a plain ", " join.)
        local ok, by = pcall(function()
            local a = type(m.author) == "table" and table.concat(m.author, ", ") or tostring(m.author)
            return localize("b_by") .. a
        end)
        if ok and type(by) == "string" and by ~= "" then parts[#parts + 1] = by end
    end
    return table.concat(parts, ", ")
end

-- The Credits tab's panel: the tab content root holding the GitHub button.
local function credits_root(items)
    for _, n in ipairs(items) do
        if n.config and n.config.button == "steamodded_github" then
            local p, up = n.parent, 0
            while p and up < 8 do
                if G.UIT and p.UIT == G.UIT.ROOT then return p end
                p, up = p.parent, up + 1
            end
        end
    end
    return nil
end

function M:handler()
    local ov = G and G.OVERLAY_MENU
    if type(SMODS) ~= "table" or type(ov) ~= "table" then return "inactive" end
    local ok, items = pcall(Mirror.gather, { ov })
    if not ok then return "inactive" end
    for _, n in ipairs(items) do
        local id, part = classify(n)
        if id and part == "toggle" then return "active" end
    end
    if credits_root(items) then return "active" end
    return "inactive"
end

local function build_credits(b, items, root)
    local panel = {}
    for _, e in ipairs(Mirror.panel_items(root)) do
        if e.node then panel[e.node] = true end
    end
    local placed = false
    local i = 0
    for _, n in ipairs(items) do
        if panel[n] then
            if not placed then
                placed = true
                for j, e in ipairs(Mirror.panel_items(root)) do
                    if e.node then
                        b:add_item(Id.referenced(e.node, "p:" .. j), Mirror.vtable_for(e.node))
                    else
                        local line = e.text
                        b:add_label(Id.structural("p:" .. j), function(ctx)
                            ctx.message:fragment(Message.raw(line))
                        end)
                    end
                end
            end
        else
            i = i + 1
            b:add_item(Id.referenced(n, "o:" .. i), Mirror.vtable_for(n))
        end
    end
end

function M:sub_identity()
    return tostring(G and G.OVERLAY_MENU)
end

function M:build(b)
    b:capture_input()
    local items = Mirror.gather({ G.OVERLAY_MENU })
    local croot = credits_root(items)
    if croot then return build_credits(b, items, croot) end

    -- Group the mod controls by mod, keeping first-appearance order; the
    -- rows go where the first mod control sat in the walk.
    local order, by_mod, slot = {}, {}, nil
    local others_before, others_after = {}, {}
    for _, n in ipairs(items) do
        local id, part = classify(n)
        if id then
            if not by_mod[id] then by_mod[id] = {}; order[#order + 1] = id end
            by_mod[id][part] = n
            slot = slot or true
        elseif slot then
            others_after[#others_after + 1] = n
        else
            others_before[#others_before + 1] = n
        end
    end

    for i, n in ipairs(others_before) do
        b:add_item(Id.referenced(n, "b:" .. i), Mirror.vtable_for(n))
    end

    for _, id in ipairs(order) do
        local parts = by_mod[id]
        b:start_row("mod:" .. id)
        if parts.card then
            local vt = Mirror.vtable_for(parts.card)
            vt.label = function(ctx)
                ctx.message:fragment(Message.raw(card_text(id)))
                ctx.message:fragment(Message.localized("TYPES.BUTTON"))
            end
            b:add_item(Id.referenced(parts.card, "card:" .. id), vt)
        end
        if parts.toggle then
            local vt = Mirror.vtable_for(parts.toggle)
            vt.label = function(ctx)
                ctx.message:fragment(Message.raw(mod_name(id)))
                local proxy = Factory.create(parts.toggle)
                local m = proxy and proxy:get_focus_message()
                if m then ctx.message:fragment(m) end
            end
            b:add_item(Id.referenced(parts.toggle, "toggle:" .. id), vt)
        end
        if parts.config then
            local vt = Mirror.vtable_for(parts.config)
            vt.label = function(ctx)
                ctx.message:fragment(Message.raw(mod_name(id)))
                local word = game_loc("b_config")
                if word then ctx.message:fragment(Message.raw(word)) end
                ctx.message:fragment(Message.localized("TYPES.BUTTON"))
            end
            b:add_item(Id.referenced(parts.config, "config:" .. id), vt)
        end
        b:end_row()
    end

    for i, n in ipairs(others_after) do
        b:add_item(Id.referenced(n, "a:" .. i), Mirror.vtable_for(n))
    end
end

return M
