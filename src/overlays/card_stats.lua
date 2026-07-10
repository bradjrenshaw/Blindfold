-- overlays/card_stats.lua — Card Stats (Stats -> Card Stats): six usage
-- tabs, each rendering a top-10 most-used histogram — a mini card, its use
-- count, and a bar per column. Detected by a tab whose definition function
-- is the game's create_UIBox_usage. Layout: the tab strip, the "Most used
-- X" caption, then ONE wrapped row of the ranked entries (matching the
-- visual columns) reading "3: Blueprint ... 42 uses" — counts come from the
-- same profile usage tables the game scales its bars with. Empty slots
-- (the game renders a dash) are skipped. Back last.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Factory = require("ui.factory")
local Proxy = require("ui.proxies").Proxy
local Mirror = require("overlays.menu_mirror")

local M = { id = "card_stats" }

local function root()
    local ov = G and G.OVERLAY_MENU
    return type(ov) == "table" and ov.UIRoot or nil
end

local function kids_of(n)
    local kids, maxn = {}, 0
    if type(n.children) ~= "table" then return kids end
    for k in pairs(n.children) do
        if type(k) == "number" and k > maxn then maxn = k end
    end
    for k = 1, maxn do
        if n.children[k] ~= nil then kids[#kids + 1] = n.children[k] end
    end
    for k, v in pairs(n.children) do
        if type(k) ~= "number" then kids[#kids + 1] = v end
    end
    return kids
end

-- Walk collecting via a predicate, descending embedded UIBoxes (the tab
-- content lives behind a UIT.O object).
local function collect(n, pred, out, depth, seen)
    if type(n) ~= "table" or (depth or 0) > 24 then return out end
    seen = seen or {}
    if seen[n] then return out end
    seen[n] = true
    if n.states and n.states.visible == false then return out end
    if pred(n) then out[#out + 1] = n end
    local o = n.config and n.config.object
    if type(o) == "table" and o.is and UIBox and o:is(UIBox) then
        collect(o.UIRoot, pred, out, (depth or 0) + 1, seen)
    end
    for _, ch in ipairs(kids_of(n)) do
        collect(ch, pred, out, (depth or 0) + 1, seen)
    end
    return out
end

-- The usage tab buttons (their def function is the game's own).
local function usage_tab_nodes()
    local r = root()
    if not r or type(create_UIBox_usage) ~= "function" then return {} end
    return collect(r, function(n)
        local c = n.config
        return c and c.button == "change_tab" and type(c.ref_table) == "table"
            and c.ref_table.tab_definition_function == create_UIBox_usage
    end, {})
end

-- {type_key, set} of the chosen tab, e.g. {'joker_usage'} / {'consumeable_usage','Tarot'}.
local function chosen_args()
    for _, t in ipairs(usage_tab_nodes()) do
        if t.config.chosen then
            local args = t.config.ref_table.tab_definition_function_args
            if type(args) == "table" then return args[1], args[2] end
        end
    end
    return nil, nil
end

local CAPTIONS = {
    joker_usage = "ph_stat_joker",
    consumeable_usage = "ph_stat_consumable",
    voucher_usage = "ph_stat_voucher",
}

-- The mini one-card areas of the histogram columns, in rank order.
local function stat_cards()
    local r = root()
    if not r then return {} end
    local hits = collect(r, function(n)
        local o = n.config and n.config.object
        return type(o) == "table" and o.is and CardArea and o:is(CardArea)
            and type(o.cards) == "table" and o.cards[1] ~= nil
    end, {})
    local cards = {}
    for _, n in ipairs(hits) do
        for _, c in ipairs(n.config.object.cards) do cards[#cards + 1] = c end
    end
    return cards
end

local function use_count(card, type_key)
    local ok, count = pcall(function()
        local key = card.config.center.key
        local tab = G.PROFILES[G.SETTINGS.profile][type_key]
        return tab and tab[key] and tab[key].count or nil
    end)
    return ok and count or nil
end

function M:handler()
    if not (G and type(G.OVERLAY_MENU) == "table") then return "inactive" end
    if not usage_tab_nodes()[1] then return "inactive" end
    return "active"
end

function M:sub_identity()
    return tostring(G.OVERLAY_MENU)
end

function M:build(b)
    b:capture_input()

    -- Tab strip (one control, left/right switches sets).
    local strip = collect(root(), function(n)
        local fa = n.config and n.config.focus_args
        return fa and fa.type == "tab"
    end, {})[1]
    if strip then
        b:add_item(Id.referenced(strip, "tabs"), Mirror.vtable_for(strip))
    end

    -- "Most used X" caption.
    local type_key, _set = chosen_args()
    if type_key and CAPTIONS[type_key] then
        b:add_label(Id.structural("caption"), function(ctx)
            local ok, s = pcall(localize, CAPTIONS[type_key])
            if ok and type(s) == "string" and s ~= "" then
                ctx.message:fragment(Message.raw(s))
            end
        end)
    end

    -- The ranked entries as one wrapped row (the visual columns).
    local cards = stat_cards()
    local shown_areas = {}
    if cards[1] then
        b:start_row("ranks", nil, { wrap = true })
        for i, card in ipairs(cards) do
            shown_areas[card.area or false] = true
            b:add_item(Id.for_object(card), {
                label = function(ctx)
                    ctx.message:fragment(Message.raw(i .. ": "))
                    local proxy = Factory.create(card)
                    local m = proxy and proxy:get_focus_message()
                    if m then ctx.message:fragment(m) end
                    local count = type_key and use_count(card, type_key)
                    if count then
                        ctx.message:fragment(Message.localized("STATS.USES", { count = count }))
                    end
                end,
                deferred = function()
                    if not Proxy.announce_enabled("description") then return nil end
                    local d = Proxy.card_description(card)
                    return d and Message.raw(d) or nil
                end,
            })
        end
        b:end_row()
    end

    -- Back (and anything else), minus what the row already shows.
    local i = 0
    for _, n in ipairs(Mirror.gather({ G.OVERLAY_MENU })) do
        local is_shown_card = n.is and Card and n:is(Card) and n.area and shown_areas[n.area]
        if n ~= strip and not is_shown_card then
            i = i + 1
            b:add_item(Id.referenced(n, "r:" .. i), Mirror.vtable_for(n))
        end
    end
end

return M
