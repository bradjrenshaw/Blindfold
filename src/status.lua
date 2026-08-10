-- status.lua — one-shot spoken status readouts, bound to Ctrl+letter on the
-- keyboard and trigger+face chords on the pad (LT layer = current-blind
-- values, RT layer = run-persistent ones). Reads live from G.GAME with the
-- same play-state gates as buffers/game.lua; outside a readout's gate it
-- says "Not available now" instead of a stale value.
local require = ...
local Message = require("ui.message")

local M = { say = nil }   -- speech.say, injected by core

local function line(key, vars) return Message.localized(key, vars):resolve() end
local function num(v) return v or 0 end

-- Scores rendered like the HUD (game number_format: commas, scientific past
-- 1e11, infinity's "naneinf"); falls back to tostring outside the game.
local function fmt_num(n)
    if type(n) ~= "number" then return n end
    local ok, s = pcall(number_format, n)
    if ok and s ~= nil then return tostring(s) end
    return tostring(n)
end
local function say(key, vars) if M.say then M.say(line(key, vars)) end end

local function in_run()
    return G and G.STAGES and G.STAGE == G.STAGES.RUN and G.GAME and G.GAME.current_round
end

-- Same gate as buffers/game.lua: blind data (chips/requirement) lingers in
-- G.GAME.blind after defeat through cash-out / shop, so blind-scoped readouts
-- need the play states, not blind.chips.
local function in_blind()
    local S = G and G.STATES
    if not S then return false end
    local s = G.STATE
    return s == S.SELECTING_HAND or s == S.HAND_PLAYED or s == S.DRAW_TO_HAND
        or s == S.PLAY_TAROT or s == S.NEW_ROUND
end

function M.hands()
    if not (in_run() and in_blind()) then return say("GAME.NOT_NOW") end
    say("GAME.HANDS", { count = num(G.GAME.current_round.hands_left) })
end

function M.discards()
    if not in_run() then return say("GAME.NOT_NOW") end
    -- In the shop the discard key rerolls (core's handler rerouting), so its
    -- status readout speaks the reroll cost — just the amount ("$5"), the
    -- context is implied by the key.
    if G.STATES and G.STATE == G.STATES.SHOP then
        local cost = G.GAME.current_round and G.GAME.current_round.reroll_cost
        if type(cost) == "number" then
            return say("GAME.MONEY", { amount = tostring(cost) })
        end
        return say("GAME.NOT_NOW")
    end
    if not in_blind() then return say("GAME.NOT_NOW") end
    say("GAME.DISCARDS", { count = num(G.GAME.current_round.discards_left) })
end

function M.score()
    local blind = in_run() and in_blind() and G.GAME.blind
    if type(blind) ~= "table" or (blind.chips or 0) <= 0 then return say("GAME.NOT_NOW") end
    say("GAME.SCORE", { score = fmt_num(num(G.GAME.chips)), req = fmt_num(blind.chips) })
end

function M.money()
    if not in_run() then return say("GAME.NOT_NOW") end
    say("GAME.MONEY", { amount = num(G.GAME.dollars) })
end

function M.jokers()
    local j = G and G.jokers
    if not (in_run() and type(j) == "table") then return say("GAME.NOT_NOW") end
    say("GAME.JOKERS", { count = #(j.cards or {}), slots = num(j.config and j.config.card_limit) })
end

return M
