-- events/cashout.lua — accumulate the end-of-round money breakdown. The cash-out
-- screen builds each money row by calling add_round_eval_row(config) (one per
-- source: blind reward, remaining hands/discards, jokers, tags, interest, then a
-- 'bottom' row with the total). We wrap that (see core.lua) and record each
-- row's source label + amount here, so ProxyCashOut can read the whole breakdown
-- when the Cash Out button takes focus. Nothing here speaks; it's read on demand.
local require = ...
local Message = require("ui.message")

local M = { rows = {}, total = nil }

-- Readable label for a row, resolved at record time (when config.card/tag are
-- live). Money sources keyed by config.name; jokers/tags use their own names.
local function row_label(config)
    local name = config.name or ""
    if name == "blind1" then return Message.localized("CASHOUT.BLIND"):resolve()
    elseif name == "hands" then return Message.localized("CASHOUT.HANDS"):resolve()
    elseif name == "discards" then return Message.localized("CASHOUT.DISCARDS"):resolve()
    elseif name == "interest" then return Message.localized("CASHOUT.INTEREST"):resolve()
    elseif name:find("joker") and config.card then
        local c = config.card.config and config.card.config.center
        local ok, n = pcall(localize, { type = "name_text", set = c and c.set, key = c and c.key })
        if ok and type(n) == "string" and n ~= "" then return n end
        return Message.localized("CASHOUT.JOKER"):resolve()
    elseif name:find("tag") then
        local tag = config.tag
        if type(tag) == "table" and tag.key then
            local ok, n = pcall(localize, { type = "name_text", set = "Tag", key = tag.key })
            if ok and type(n) == "string" and n ~= "" then return n end
        end
        if type(config.condition) == "string" and config.condition ~= "" then return config.condition end
        return Message.localized("CASHOUT.TAG"):resolve()
    end
    return name
end

-- Called for every round-eval row as it is added. 'blind1' is always first (so
-- it resets a fresh breakdown); 'bottom' carries the total.
function M.on_row(config)
    if type(config) ~= "table" then return end
    if config.name == "blind1" then M.rows = {}; M.total = nil end
    if config.name == "bottom" then M.total = config.dollars; return end
    local d = config.dollars
    if type(d) ~= "number" or d == 0 then return end
    M.rows[#M.rows + 1] = { label = row_label(config), dollars = d }
end

-- "Blind reward, 5 dollars. Interest, 4 dollars." — nil when empty.
function M.breakdown_text()
    if #M.rows == 0 then return nil end
    local parts = {}
    for _, r in ipairs(M.rows) do
        parts[#parts + 1] = Message.localized("CASHOUT.ROW", { label = r.label, dollars = r.dollars }):resolve()
    end
    return table.concat(parts, ". ")
end

return M
