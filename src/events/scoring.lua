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

-- ---- Effect formats -----------------------------------------------------
-- Verbosity styles for the per-effect lines (the Scoring settings submenu):
-- the animations fly, so users pick how much each contribution says. The
-- amount carries its own sign — screen readers speak "+"/"-" — so the
-- localized templates hold no plus/minus word of their own. Styles:
--   signed_word "+10 chips"   signed "+10"   word "10 chips"   bare "10"
--   signed_abbr "+10c"        abbr "10c"
--   (times mult:) word "times 3 mult"   x_abbr "x3m"   x "3x"
local function signed(amt)
    local n = tostring(amt)
    return (tonumber(amt) or 0) > 0 and ("+" .. n) or n
end

local function styled(style, amt, word_key, abbr_key)
    if style == "signed" then return signed(amt) end
    if style == "bare" then return tostring(amt) end
    if style == "signed_abbr" then return signed(amt) .. loc(abbr_key) end
    if style == "abbr" then return tostring(amt) .. loc(abbr_key) end
    if style == "word" then return loc(word_key, { amt = amt }) end
    return loc(word_key, { amt = signed(amt) })   -- signed_word (default)
end

local function styled_xmult(style, amt)
    if style == "x_abbr" then return "x" .. tostring(amt) .. loc("SCORING.ABBR_MULT") end
    if style == "x" then return tostring(amt) .. "x" end
    return loc("SCORING.XMULT", { amt = amt })    -- word (default)
end

-- One scoring contribution as configured. kind: "chips" | "mult" | "xmult";
-- gains and losses read their own style (vanilla never emits a negative
-- chips/mult popup — losses arrive as joker message strings — but the
-- renderer is signed either way).
function M.format_effect(kind, amt)
    if kind == "xmult" then
        return styled_xmult(setting("scoring.fmt.xmult", "word"), amt)
    end
    local gain = (tonumber(amt) or 0) >= 0
    if kind == "chips" then
        local style = gain and setting("scoring.fmt.chips_gain", "signed_word")
            or setting("scoring.fmt.chips_loss", "signed_word")
        return styled(style, amt, "SCORING.CHIPS", "SCORING.ABBR_CHIPS")
    end
    local style = gain and setting("scoring.fmt.mult_gain", "signed_word")
        or setting("scoring.fmt.mult_loss", "signed_word")
    -- Mult always carries its m/word — a bare "-10" would read as chips. Also
    -- guards stale saved values from when the option briefly existed.
    if style == "signed" or style == "bare" then style = "signed_word" end
    return styled(style, amt, "SCORING.MULT", "SCORING.ABBR_MULT")
end

-- A style rendered with a sample amount, for the settings cycle's option
-- labels — live examples in the player's language.
function M.format_example(kind, style)
    if kind == "xmult" then return styled_xmult(style, 3) end
    local amt = kind:match("loss") and -10 or 10
    if kind:match("chips") then
        return styled(style, amt, "SCORING.CHIPS", "SCORING.ABBR_CHIPS")
    end
    return styled(style, amt, "SCORING.MULT", "SCORING.ABBR_MULT")
end

-- ---- Joker message normalization ------------------------------------------
-- The game's NUMERIC joker popups ("+3 Mult", "X4 Mult", "+20", Popcorn's
-- "-4 Mult") all render through six templates in the game's own localization
-- (v_dictionary: a_chips / a_mult / a_xmult and their _minus forms). Matching
-- a message against the LIVE templates — language-correct by construction —
-- recovers the amount so these lines obey the same verbosity formats as every
-- other contribution. Anything else ("Again!") stays the game's words,
-- verbatim.
local NUMERIC_MESSAGES = {
    { key = "a_chips",       kind = "chips", sign = 1 },
    { key = "a_chips_minus", kind = "chips", sign = -1 },
    { key = "a_mult",        kind = "mult",  sign = 1 },
    { key = "a_mult_minus",  kind = "mult",  sign = -1 },
    { key = "a_xmult",       kind = "xmult", sign = 1 },
    { key = "a_xmult_minus", kind = "xmult", sign = -1 },
}

local _msg_patterns, _msg_lang
local function message_patterns()
    local lang = G and G.SETTINGS and G.SETTINGS.language
    if _msg_patterns and _msg_lang == lang then return _msg_patterns end
    _msg_patterns, _msg_lang = {}, lang
    local dict = G and G.localization and G.localization.misc
        and G.localization.misc.v_dictionary
    if type(dict) ~= "table" then return _msg_patterns end
    for _, spec in ipairs(NUMERIC_MESSAGES) do
        local tmpl = dict[spec.key]
        if type(tmpl) == "string" then
            -- Escape pattern magic, then #1# captures the (possibly
            -- comma-grouped / decimal) number.
            local p = tmpl:gsub("%W", "%%%0")
            p = "^" .. p:gsub("%%%#1%%%#", "([%%d%%.,]+)") .. "$"
            _msg_patterns[#_msg_patterns + 1] =
                { pattern = p, kind = spec.kind, sign = spec.sign }
        end
    end
    return _msg_patterns
end

-- A numeric game message reformatted per the effect-format settings, or nil
-- to speak it verbatim.
function M.normalize_message(msg)
    if type(msg) ~= "string" or msg == "" then return nil end
    for _, spec in ipairs(message_patterns()) do
        local n = msg:match(spec.pattern)
        if n then
            local num = tonumber((n:gsub(",", "")))
            if num then
                if spec.kind == "xmult" then
                    local s = M.format_effect("xmult", num)
                    return spec.sign < 0 and ("-" .. s) or s
                end
                return M.format_effect(spec.kind, num * spec.sign)
            end
        end
    end
    return nil
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
        if nonzero then phrase = M.format_effect("chips", amt) end
    elseif eval_type == "mult" or eval_type == "h_mult" then
        if nonzero then phrase = with_source(card, M.format_effect("mult", amt)) end
    elseif eval_type == "x_mult" or eval_type == "h_x_mult" then
        if nonzero then phrase = with_source(card, M.format_effect("xmult", amt)) end
    elseif eval_type == "dollars" then
        if nonzero then phrase = with_source(card, loc("SCORING.DOLLARS", { amt = amt })) end
    elseif eval_type == "debuff" then
        phrase = loc("SCORING.DEBUFF", { source = source_name(card) or "" })
    elseif eval_type == "jokers" or eval_type == "extra" then
        local msg = extra and extra.message
        if type(msg) == "string" and msg ~= "" then
            phrase = with_source(card, M.normalize_message(msg) or msg)
        elseif extra then
            -- No message string: derive the effect from the modifier fields.
            local n, eff = nil, nil
            n = extra.x_mult_mod or extra.x_mult
            if n then eff = M.format_effect("xmult", n)
            else
                n = extra.mult_mod or extra.mult
                if n then eff = M.format_effect("mult", n)
                else
                    n = extra.chip_mod or extra.chips
                    if n then eff = M.format_effect("chips", n) end
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

-- Hand level DOWN (The Arm). Level-UPS announce through the full hand-text
-- panel, but level_up_hand's own piecemeal text updates carry no hand name,
-- so a downgrade never reaches that path — core wraps the function itself
-- and calls this for negative amounts. The hand table is already updated
-- synchronously by the time the wrap runs.
function M.on_level_down(hand)
    if not setting("scoring.enabled", true) then return end
    local h = G and G.GAME and G.GAME.hands and G.GAME.hands[hand]
    if not h then return end
    local name = hand
    local ok, n = pcall(localize, hand, "poker_hands")
    if ok and type(n) == "string" and n ~= "" then name = n end
    local line = loc("SCORING.HAND_LEVEL_DOWN",
        { name = name, level = h.level, chips = h.chips, mult = h.mult })
    if G.E_MANAGER and Event then
        G.E_MANAGER:add_event(Event({
            trigger = "immediate",
            func = function() speak(line); return true end,
        }))
    else
        speak(line)
    end
end

-- Play-area banner: vanilla uses it only for "Not Allowed!" — The Eye / The
-- Mouth rejecting a repeated / wrong hand type (chips and mult forced to 0,
-- cards wasted). Not gated behind the scoring toggle: it's the only signal
-- of WHY the hand scored nothing. Queued like every scoring line so it lands
-- on the popup's beat, not ahead of the whole sequence.
function M.on_play_area_status(text)
    if type(text) ~= "string" or text == "" then return end
    if not (G and G.E_MANAGER and Event) then
        speak(text)
        return
    end
    G.E_MANAGER:add_event(Event({
        trigger = "immediate",
        func = function()
            speak(text)
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
    elseif type(vals.handname) == "string" and vals.handname ~= ""
        and type(vals.level) == "number"
        and type(vals.chips) == "number" and type(vals.mult) == "number" then
        -- A hand being UPGRADED (planet card, level-up jokers). The values in
        -- THIS call may be pre- or post-upgrade depending on the caller (the
        -- planet path shows the panel BEFORE level_up_hand increments;
        -- joker-triggered upgrades call it after) — so the announcement is
        -- queued one event later and reads the LIVE hand table, which is
        -- post-upgrade in every path by then.
        M._last_hand = vals.handname
        local name = vals.handname
        local fallback = { name = name, level = vals.level, chips = vals.chips, mult = vals.mult }
        local function announce()
            local live
            pcall(function()
                for key, h in pairs(G.GAME.hands) do
                    local ok, loc_name = pcall(localize, key, "poker_hands")
                    if ok and loc_name == name then
                        live = { name = name, level = h.level, chips = h.chips, mult = h.mult }
                        break
                    end
                end
            end)
            speak(loc("SCORING.HAND_LEVEL", live or fallback))
        end
        if G and G.E_MANAGER and Event then
            G.E_MANAGER:add_event(Event({
                trigger = "immediate",
                func = function()
                    announce()
                    return true
                end,
            }))
        else
            announce()
        end
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
