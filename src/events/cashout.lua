-- events/cashout.lua — accumulate the end-of-round money breakdown. The cash-out
-- screen builds each money row by calling add_round_eval_row(config) (one per
-- source: blind reward, remaining hands/discards, jokers, tags, interest, then a
-- 'bottom' row with the total). We wrap that (see core.lua) and record each row
-- with enough context (counts, the joker card / tag object) that ProxyCashOut
-- and the cash-out overlay can render a browsable breakdown — AND each row is
-- spoken live as its payout animates: evaluate_round adds every row in one
-- frame, while the visuals (name text + per-dollar coin ticks) are events the
-- original queues on the sequential base queue. Our wrap runs before the
-- original, so a speech event queued here lands right as its row's coin
-- cascade begins (same pattern as events/scoring.lua).
local require = ...
local Message = require("ui.message")
local Num = require("ui.num")

local M = { rows = {}, total = nil, hidden_text = nil, say = nil }

-- Steamodded's compact cash-out draws only the first 7 rows (counting them in
-- the global total_cashout_rows, reset per round) and adds one "...and N more"
-- line. Rows it won't draw aren't spoken or listed; that line is, instead.
local COMPACT_ROWS = 7

local function speak_queued(line)
    if not (M.say and type(line) == "string" and line ~= "") then return end
    if G and G.E_MANAGER and Event then
        G.E_MANAGER:add_event(Event({
            trigger = "immediate",
            func = function() M.say(line); return true end,
        }))
    else
        M.say(line)
    end
end

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
    if config.name == "blind1" then M.rows = {}; M.total = nil; M.hidden_text = nil end
    local drawn = rawget(_G, "total_cashout_rows")
    if config.name == "bottom" then
        M.total = config.dollars
        -- (The game queues its "...and N more" line just before this row.)
        if type(drawn) == "number" and drawn > COMPACT_ROWS then
            local ok, s = pcall(localize, { type = "variable", key = "cashout_hidden",
                vars = { drawn - COMPACT_ROWS } })
            if ok and type(s) == "string" and s ~= "" and s ~= "ERROR" then
                M.hidden_text = s
                speak_queued(s)
            end
        end
        return
    end
    -- Our wrap runs before the original, which counts this row first.
    if type(drawn) == "number" and drawn + 1 > COMPACT_ROWS then return end
    local n = config.name or ""
    local d = config.dollars
    -- Keep blind1 even at $0 (the Mr. Bones save); every other source needs a
    -- nonzero amount to be worth a line.
    local amount = Num.to_n(d)
    if n == "blind1" then
        -- Always drawn, reward or not (a stake whose small blind pays
        -- nothing still shows the beaten blind's row): "Blind reward, 0
        -- dollars" — or Mr. Bones' save.
        if not amount and not config.saved then return end
    elseif not amount or amount == 0 then
        return
    end
    local row = {
        name = n, dollars = d, disp = config.disp, saved = config.saved,
        card = config.card, tag = config.tag, item = item_name(config),
    }
    M.rows[#M.rows + 1] = row

    -- Speak the row when it lands on screen (composed now, spoken from the
    -- event queue in step with the animation).
    local ok, line = pcall(M.summary, row)
    if ok then speak_queued(line) end
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
