-- overlays/credits.lua — the Credits screen: tabbed walls of decorative
-- text (plus optional external-link buttons) that the mirror read as
-- buttons only. Nothing structural identifies the screen (anonymous tab
-- closures, raw-string tab labels), so core tags the overlay when
-- G.FUNCS.show_credits opens it. Layout: the tab strip, then the chosen
-- tab's text flattened to one line per rendered row (control subtrees
-- excluded — their buttons are presented as controls afterward), then the
-- buttons and Back via the mirror.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Proxy = require("ui.proxies").Proxy
local Mirror = require("overlays.menu_mirror")

local M = { id = "credits" }

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

local function is_control(n)
    local ok, is = pcall(Proxy.node_is_control, n)
    return ok and is or false
end

local function has_text(n, depth)
    if type(n) ~= "table" or (depth or 0) > 8 or is_control(n) then return false end
    local c = n.config
    if c and n.UIT == G.UIT.T
        and (type(c.text) == "string" or type(c.text) == "number") then
        return true
    end
    if c and type(c.object) == "table" and type(c.object.string) == "string" then
        return true
    end
    for _, ch in ipairs(kids_of(n)) do
        if has_text(ch, (depth or 0) + 1) then return true end
    end
    return false
end

local function has_deeper_text_row(n, depth)
    if type(n) ~= "table" or (depth or 0) > 8 then return false end
    for _, ch in ipairs(kids_of(n)) do
        if type(ch) == "table" and not is_control(ch) then
            if ch.UIT == G.UIT.R and has_text(ch) then return true end
            if has_deeper_text_row(ch, (depth or 0) + 1) then return true end
        end
    end
    return false
end

local function collect_lines(node, out, depth)
    if type(node) ~= "table" or (depth or 0) > 8 or is_control(node) then return end
    if not has_deeper_text_row(node) then
        if has_text(node) then
            local ok, t = pcall(Proxy.all_text, node)
            if ok and type(t) == "string" and t ~= "" then out[#out + 1] = t end
        end
        return
    end
    for _, ch in ipairs(kids_of(node)) do
        collect_lines(ch, out, (depth or 0) + 1)
    end
end

-- The chosen tab's content box (embedded UIBox behind a UIT.O node).
local function content_boxes()
    local r = root()
    if not r then return {} end
    local out = {}
    local function walk(n, depth, seen)
        if type(n) ~= "table" or depth > 20 or seen[n] then return end
        seen[n] = true
        if n.states and n.states.visible == false then return end
        local o = n.config and n.config.object
        if type(o) == "table" and o.is and UIBox and o:is(UIBox) and o.UIRoot then
            out[#out + 1] = o
            return
        end
        for _, ch in ipairs(kids_of(n)) do walk(ch, depth + 1, seen) end
    end
    walk(r, 0, {})
    return out
end

function M:handler()
    local ov = G and G.OVERLAY_MENU
    if not (type(ov) == "table" and ov.blindfold_credits) then return "inactive" end
    return "active"
end

function M:sub_identity()
    return tostring(G.OVERLAY_MENU)
end

function M:build(b)
    b:capture_input()

    local strip
    local r = root()
    if r then
        local function find_strip(n, depth)
            if type(n) ~= "table" or depth > 20 or strip then return end
            local fa = n.config and n.config.focus_args
            if fa and fa.type == "tab" then strip = n; return end
            for _, ch in ipairs(kids_of(n)) do find_strip(ch, depth + 1) end
        end
        find_strip(r, 0)
    end
    if strip then
        b:add_item(Id.referenced(strip, "tabs"), Mirror.vtable_for(strip))
    end

    -- The tab's text, one item per rendered line.
    local li = 0
    for _, box in ipairs(content_boxes()) do
        local lines = {}
        collect_lines(box.UIRoot, lines, 0)
        for _, line in ipairs(lines) do
            li = li + 1
            b:add_label(Id.structural("t:" .. li), function(ctx)
                ctx.message:fragment(Message.raw(line))
            end)
        end
    end

    -- Link buttons + Back.
    local i = 0
    for _, n in ipairs(Mirror.gather({ G.OVERLAY_MENU })) do
        if n ~= strip then
            i = i + 1
            b:add_item(Id.referenced(n, "r:" .. i), Mirror.vtable_for(n))
        end
    end
end

return M
