-- ui/joker_display.lua — read the JokerDisplay mod's live readout under a
-- joker ("+15", "X1.5", "(1 in 6)", "(Face Cards)", the value it would add
-- to the selected hand). The readout is one of three UIBoxes JokerDisplay
-- attaches to the card (full / collapsed / debuffed); whichever is showing
-- is read. Nothing happens without JokerDisplay.
--
-- The readout's units are COLOUR alone (red mult, blue chips, the x-mult
-- colour), which a screen reader can't convey; runs in those colours are
-- spoken through the scoring formatter, so they follow the player's
-- verbosity settings ("+15 mult", "+15m", ...). Everything else reads as
-- drawn, with sign and number joined ("+ 15" -> "+15").
local require = ...

local M = {}

local function visible_box(card)
    local kids = card and card.children
    local vals = card and card.joker_display_values
    if not (kids and vals) or vals.disabled then return nil end
    local order = card.debuff and { "joker_display_debuff" }
        or vals.small and { "joker_display_small", "joker_display" }
        or { "joker_display", "joker_display_small" }
    for _, key in ipairs(order) do
        local box = kids[key]
        if box and box.UIRoot and not (box.states and box.states.visible == false) then return box end
    end
    return nil
end

-- Text segments in reading order: { text, colour }.
local function segments(root)
    local out = {}
    local function walk(n, depth)
        if type(n) ~= "table" or depth > 14 then return end
        if n.states and n.states.visible == false then return end
        local c = n.config
        if c and G.UIT and n.UIT == G.UIT.T then
            local t = c.text
            if t == nil and type(c.ref_table) == "table" and c.ref_value ~= nil then
                t = c.ref_table[c.ref_value]
            end
            if t ~= nil then
                t = tostring(t)
                if t:match("%S") then out[#out + 1] = { text = t, colour = c.colour } end
            end
        elseif c and G.UIT and n.UIT == G.UIT.O and type(c.object) == "table"
            and type(c.object.string) == "string" and c.object.string:match("%S") then
            out[#out + 1] = { text = c.object.string, colour = c.object.colours and c.object.colours[1] }
        end
        for _, ch in ipairs(n.children or {}) do walk(ch, depth + 1) end
    end
    walk(root, 0)
    return out
end

local function kind_of(colour)
    if not (G and G.C and colour) then return nil end
    if colour == G.C.MULT then return "mult" end
    if colour == G.C.CHIPS then return "chips" end
    if colour == G.C.JOKER_DISPLAY_XMULT_TEXT or colour == G.C.XMULT then return "xmult" end
    return nil
end

-- The spoken readout for a joker, or nil (no JokerDisplay, hidden, empty).
-- format_effect(kind, amount) renders a mult / chips / xmult run.
function M.text(card, format_effect)
    local box = visible_box(card)
    if not box then return nil end
    local segs = segments(box.UIRoot)
    if not segs[1] then return nil end
    -- Merge consecutive segments of the same colour into one run.
    local runs = {}
    for _, s in ipairs(segs) do
        local last = runs[#runs]
        if last and last.colour == s.colour then
            last.text = last.text .. s.text
        else
            runs[#runs + 1] = { text = s.text, colour = s.colour }
        end
    end
    local parts = {}
    for _, r in ipairs(runs) do
        local t = r.text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
        local kind = kind_of(r.colour)
        local spoken
        if kind and format_effect then
            local num = t:gsub("^[Xx]%s*", ""):gsub("%s", "")
            local n = tonumber(num)
            if n then
                local ok, s = pcall(format_effect, kind, n)
                if ok and type(s) == "string" and s ~= "" then spoken = s end
            end
        end
        spoken = spoken or t:gsub("([%+%-])%s+(%d)", "%1%2")
        if spoken ~= "" then parts[#parts + 1] = spoken end
    end
    if not parts[1] then return nil end
    -- Brackets drawn in another colour than their contents became their
    -- own runs: "( Face Cards )" -> "(Face Cards)".
    local s = table.concat(parts, " "):gsub("%(%s+", "("):gsub("%s+%)", ")")
    return s
end

return M
