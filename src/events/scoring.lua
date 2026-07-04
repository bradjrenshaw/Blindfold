-- events/scoring.lua — speak the hand-scoring sequence. The game funnels every
-- floating "+10 chips / x3 mult / joker message" through card_eval_status_text,
-- and the hand name + final score through update_hand_text. We wrap both (see
-- core.lua); per-effect lines are composed at evaluation time but spoken from
-- the game's own event queue so each utterance lands when its popup animates
-- (see on_status). Source cards/jokers are named by reusing the focus proxies.
local require = ...
local Factory = require("ui.factory")
local Message = require("ui.message")

local M = { say = nil, settings = nil, _last_hand = nil, _last_score = nil, _cur_chips = nil, _cur_mult = nil }

local function speak(text)
    if M.say and type(text) == "string" and text ~= "" then M.say(text) end
end
local function loc(key, vars) return Message.localized(key, vars):resolve() end

-- Read a mod setting (or the default when the settings layer isn't loaded).
local function setting(key, default)
    local s = M.settings
    if s and s.value then
        local v = s.value(key)
        if v ~= nil then return v end
    end
    return default
end

-- The card/joker a status text floats over, named via its focus proxy. Fully
-- guarded: a failure here must never drop the announcement (it only drops the
-- name), so the whole lookup is inside one pcall.
local function source_name(card)
    local ok, name = pcall(function()
        if not card then return nil end
        local proxy = Factory.create(card)
        local m = proxy and proxy:get_label()
        if type(m) == "table" and m.resolve then
            local s = m:resolve()
            if s and s ~= "" then return s end
        end
        return nil
    end)
    return ok and name or nil
end

-- Prefix an effect with its source ("Blueprint, times 3 mult"); plain chips from
-- individual played cards stay unprefixed to keep the sequence short.
local function with_source(card, effect)
    local name = source_name(card)
    return name and loc("SCORING.SOURCE", { source = name, effect = effect }) or effect
end

-- One scoring contribution (mirrors card_eval_status_text's own dispatch).
--
-- Composed IMMEDIATELY — the whole hand is evaluated in one frame, and joker
-- names / effect messages must be read while that state is live — but SPOKEN
-- from the game's event queue: the original card_eval_status_text call queued
-- its popup + sound as a 'before'-delay event on the sequential base queue
-- (common_events.lua:898), so queueing the utterance right behind it makes
-- each line land exactly when its popup fires. The readout follows the
-- animation pacing, including game-speed scaling. (extra.instant popups show
-- immediately, so those speak immediately.)
function M.on_status(card, eval_type, amt, extra)
    if not card then return end
    if not setting("scoring.enabled", true) then return end
    local detail = setting("scoring.detail", "full")
    if detail == "summary" then return end                          -- summary: no per-event detail
    if detail == "jokers" and eval_type == "chips" then return end  -- jokers only: skip per-card chips
    local nonzero = (amt or 0) ~= 0
    local phrase
    if eval_type == "chips" then
        if nonzero then phrase = loc("SCORING.CHIPS", { amt = amt }) end
    elseif eval_type == "mult" or eval_type == "h_mult" then
        if nonzero then phrase = with_source(card, loc("SCORING.MULT", { amt = amt })) end
    elseif eval_type == "x_mult" or eval_type == "h_x_mult" then
        if nonzero then phrase = with_source(card, loc("SCORING.XMULT", { amt = amt })) end
    elseif eval_type == "dollars" then
        if nonzero then phrase = with_source(card, loc("SCORING.DOLLARS", { amt = amt })) end
    elseif eval_type == "debuff" then
        phrase = loc("SCORING.DEBUFF", { source = source_name(card) or "" })
    elseif eval_type == "jokers" or eval_type == "extra" then
        local msg = extra and extra.message
        if type(msg) == "string" and msg ~= "" then
            phrase = with_source(card, msg)
        elseif extra then
            -- No message string: derive the effect from the modifier fields.
            local n, eff = nil, nil
            n = extra.x_mult_mod or extra.x_mult
            if n then eff = loc("SCORING.XMULT", { amt = n })
            else
                n = extra.mult_mod or extra.mult
                if n then eff = loc("SCORING.MULT", { amt = n })
                else
                    n = extra.chip_mod or extra.chips
                    if n then eff = loc("SCORING.CHIPS", { amt = n }) end
                end
            end
            if eff then phrase = with_source(card, eff) end
        end
    end
    if not phrase then return end
    if (extra and extra.instant) or not (G and G.E_MANAGER and Event) then
        speak(phrase)
        return
    end
    G.E_MANAGER:add_event(Event({
        trigger = "immediate",
        func = function()
            speak(phrase)
            return true
        end,
    }))
end

-- The hand name + base chips/mult on the play, and the final score.
function M.on_hand_text(config, vals)
    if not vals then return end
    if not setting("scoring.enabled", true) then return end
    -- The play call (config.immediate) carries the poker hand plus its base
    -- chips and mult; the lighter preview call while selecting carries just the
    -- name (so you hear the hand forming as you highlight cards).
    if config and config.immediate and type(vals.handname) == "string" and vals.handname ~= ""
       and type(vals.chips) == "number" and type(vals.mult) == "number"
       and (vals.chips > 0 or vals.mult > 0) then
        M._last_hand = vals.handname
        -- A new hand is being played: its total must speak even when it lands
        -- on exactly the same number as the previous hand's (the dedupe only
        -- guards against repeats WITHIN one scoring).
        M._last_score = nil
        speak(loc("SCORING.HAND", { name = vals.handname, chips = vals.chips, mult = vals.mult }))
    elseif type(vals.handname) == "string" and vals.handname ~= "" and vals.handname ~= M._last_hand then
        M._last_hand = vals.handname
        if setting("scoring.hand_preview", true) then speak(vals.handname) end
    end
    if vals.chip_total ~= nil and vals.chip_total ~= M._last_score then
        -- Final score. The same call resets chips/mult to 0, so report the
        -- running totals captured during the count-up: "X chips times Y mult
        -- equals Z".
        M._last_score = vals.chip_total
        if type(M._cur_chips) == "number" and type(M._cur_mult) == "number" then
            speak(loc("SCORING.TOTAL", { chips = M._cur_chips, mult = M._cur_mult, score = vals.chip_total }))
        else
            speak(loc("SCORING.SCORE", { score = vals.chip_total }))
        end
        M._cur_chips, M._cur_mult = nil, nil
    else
        -- Track the running chips and mult so the final equation has them.
        if type(vals.chips) == "number" and vals.chips > 0 then M._cur_chips = vals.chips end
        if type(vals.mult) == "number" and vals.mult > 0 then M._cur_mult = vals.mult end
    end
end

return M
