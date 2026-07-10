-- buffers/game.lua — the "game" buffer: a live readout of the player's current
-- run status (hands, discards, money, score vs blind, ante, round). These are
-- the non-focusable HUD values, browsable with the buffer hotkeys. Everything
-- reads live from G.GAME on each navigation and is nil-guarded.
local require = ...
local Buffer = require("buffers.buffer")
local Message = require("ui.message")

local function line(key, vars) return Message.localized(key, vars):resolve() end
local function num(v) return v or 0 end

local function in_run()
    return G and G.STAGES and G.STAGE == G.STAGES.RUN and G.GAME and G.GAME.current_round
end

-- Whether a blind is actively being played. G.GAME.blind persists (with its
-- chips) after defeat through cash-out / shop, so the round-specific lines
-- (hands / discards / score / blind) must be gated on the play states, not on
-- blind.chips, or they'd linger once the blind is complete.
local function in_blind()
    local S = G and G.STATES
    if not S then return false end
    local s = G.STATE
    return s == S.SELECTING_HAND or s == S.HAND_PLAYED or s == S.DRAW_TO_HAND
        or s == S.PLAY_TAROT or s == S.NEW_ROUND
end

local function populate(self)
    if not in_run() then return end
    local g = G.GAME
    local cr = g.current_round or {}
    local playing = in_blind()

    if playing then
        self:add(line("GAME.HANDS",    { count = num(cr.hands_left) }))
        self:add(line("GAME.DISCARDS", { count = num(cr.discards_left) }))
    end
    self:add(line("GAME.MONEY", { amount = num(g.dollars) }))

    if playing then
        local blind = g.blind
        if type(blind) == "table" and (blind.chips or 0) > 0 then
            self:add(line("GAME.SCORE", { score = num(g.chips), req = blind.chips }))
            local bname = blind.loc_name or blind.name
            if bname then self:add(line("GAME.BLIND", { name = tostring(bname) })) end
            -- The boss effect the HUD shows all round (The Ox's even names
            -- your most-played hand). Empty for small/big blinds.
            if type(blind.loc_debuff_text) == "string" and blind.loc_debuff_text ~= "" then
                self:add(blind.loc_debuff_text)
            end
        end
    end

    self:add(line("GAME.ANTE",  { ante = num(g.round_resets and g.round_resets.ante) }))
    self:add(line("GAME.ROUND", { round = num(g.round) }))
end

return Buffer.new("game", { update = function(self) self:repopulate(function() populate(self) end) end })
