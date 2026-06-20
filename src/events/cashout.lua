-- events/cashout.lua — accumulate the end-of-round money breakdown. The cash-out
-- screen builds each money row by calling add_round_eval_row(config) (one per
-- source: blind reward, remaining hands/discards, jokers, tags, interest, then a
-- 'bottom' row with the total). We wrap that (see core.lua) and record each row
-- with enough context (counts, the joker card / tag object) that ProxyCashOut
-- can render a browsable, drill-down breakdown in the Cash Out buffer. Nothing
-- here speaks; it's read on demand.
local require = ...
local Message = require("ui.message")

local M = { rows = {}, total = nil }

-- Joker / tag rows carry their own name; resolved at record time while
-- config.card / config.tag are live.
local function item_name(config)
    local n = config.name or ""
    if n:find("joker") and config.card then
        local c = config.card.config and config.card.config.center
        local ok, name = pcall(localize, { type = "name_text", set = c and c.set, key = c and c.key })
        if ok and type(name) == "string" and name ~= "" then return name end
        return Message.localized("CASHOUT.JOKER"):resolve()
    elseif n:find("tag") then
        local tag = config.tag
        if type(tag) == "table" and tag.key then
            local ok, name = pcall(localize, { type = "name_text", set = "Tag", key = tag.key })
            if ok and type(name) == "string" and name ~= "" then return name end
        end
        if type(config.condition) == "string" and config.condition ~= "" then return config.condition end
        return Message.localized("CASHOUT.TAG"):resolve()
    end
    return nil
end

-- Called for every round-eval row as it is added. 'blind1' is always first (so
-- it resets a fresh breakdown); 'bottom' carries the total.
function M.on_row(config)
    if type(config) ~= "table" then return end
    if config.name == "blind1" then M.rows = {}; M.total = nil end
    if config.name == "bottom" then M.total = config.dollars; return end
    local n = config.name or ""
    local d = config.dollars
    -- Keep blind1 even at $0 (the Mr. Bones save); every other source needs a
    -- nonzero amount to be worth a line.
    if n == "blind1" then
        if (type(d) ~= "number" or d == 0) and not config.saved then return end
    elseif type(d) ~= "number" or d == 0 then
        return
    end
    M.rows[#M.rows + 1] = {
        name = n, dollars = d, disp = config.disp, saved = config.saved,
        card = config.card, tag = config.tag, item = item_name(config),
    }
end

-- One-line summary for a breakdown row (the browsable buffer item). Counts /
-- rates included where the game shows them; jokers/tags read by name.
function M.summary(row)
    local n = row.name
    if n == "blind1" then
        if row.saved then return Message.localized("CASHOUT.SAVED"):resolve() end
        return Message.localized("CASHOUT.BLIND_ROW", { dollars = row.dollars }):resolve()
    elseif n == "hands" then
        return Message.localized("CASHOUT.HANDS_ROW", { count = row.disp or 0, dollars = row.dollars }):resolve()
    elseif n == "discards" then
        return Message.localized("CASHOUT.DISCARDS_ROW", { count = row.disp or 0, dollars = row.dollars }):resolve()
    elseif n == "interest" then
        local rate = (G and G.GAME and G.GAME.interest_amount) or 1
        local cap = (G and G.GAME and G.GAME.interest_cap) or 25
        local max = math.floor(rate * (cap / 5))
        return Message.localized("CASHOUT.INTEREST_ROW", { dollars = row.dollars, rate = rate, max = max }):resolve()
    end
    return Message.localized("CASHOUT.ROW", { label = row.item or n, dollars = row.dollars }):resolve()
end

return M
