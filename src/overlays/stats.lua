-- overlays/stats.lua — the Stats screen (Options -> Stats). Its six
-- high-score rows (Best Hand, Furthest Round, Furthest Ante, Most Played
-- Hand, Most Money, Best Win Streak) are static label + floating DynaText
-- value — pure renders the mirror can't see, so the screen read as just the
-- progress box and buttons. Detected by its Card Stats button
-- (config.button 'usage'). Score rows first, each read as one line, then
-- the mirror's items (progress box, Card Stats, Back) in tree order.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Proxy = require("ui.proxies").Proxy
local Mirror = require("overlays.menu_mirror")

local M = { id = "stats" }

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

local function has_usage_button(n, depth)
    if type(n) ~= "table" or (depth or 0) > 20 then return false end
    if n.config and n.config.button == "usage" then return true end
    for _, ch in ipairs(kids_of(n)) do
        if has_usage_button(ch, (depth or 0) + 1) then return true end
    end
    return false
end

local function count_dynas(n, depth)
    if type(n) ~= "table" or (depth or 0) > 8 then return 0 end
    local c = n.config
    local total = 0
    if c and n.UIT == G.UIT.O and type(c.object) == "table" and c.object.strings then
        total = 1
    end
    for _, ch in ipairs(kids_of(n)) do
        total = total + count_dynas(ch, (depth or 0) + 1)
    end
    return total
end

local function has_control_or_bar(n, depth)
    if type(n) ~= "table" or (depth or 0) > 8 then return false end
    if n.config and n.config.progress_bar then return true end
    local ok, is = pcall(Proxy.node_is_control, n)
    if ok and is then return true end
    for _, ch in ipairs(kids_of(n)) do
        if has_control_or_bar(ch, (depth or 0) + 1) then return true end
    end
    return false
end

-- A high-score row: an R with EXACTLY ONE DynaText value (the container
-- around all six has many) plus no control/progress bar in it.
local function collect_scores(n, out, depth)
    if type(n) ~= "table" or (depth or 0) > 12 then return end
    if G.UIT and n.UIT == G.UIT.R and not has_control_or_bar(n)
        and count_dynas(n) == 1 then
        out[#out + 1] = n
        return
    end
    for _, ch in ipairs(kids_of(n)) do
        collect_scores(ch, out, (depth or 0) + 1)
    end
end

function M:handler()
    local r = root()
    if not (r and has_usage_button(r)) then return "inactive" end
    return "active"
end

function M:sub_identity()
    return tostring(G.OVERLAY_MENU)
end

function M:build(b)
    b:capture_input()

    local scores = {}
    collect_scores(root(), scores, 0)
    for i, row in ipairs(scores) do
        b:add_label(Id.referenced(row, "sc:" .. i), function(ctx)
            local ok, text = pcall(Proxy.all_text, row)
            if ok and type(text) == "string" and text ~= "" then
                ctx.message:fragment(Message.raw(text))
            end
        end)
    end

    -- Progress box, Card Stats button, Back — the mirror reads these fine.
    local i = 0
    for _, n in ipairs(Mirror.gather({ G.OVERLAY_MENU })) do
        i = i + 1
        b:add_item(Id.referenced(n, "r:" .. i), Mirror.vtable_for(n))
    end
end

return M
