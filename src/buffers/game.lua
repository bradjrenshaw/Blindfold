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

local function populate(self)
    if not in_run() then return end
    local g = G.GAME
    local cr = g.current_round or {}
    self:add(line("GAME.HANDS",    { count = num(cr.hands_left) }))
    self:add(line("GAME.DISCARDS", { count = num(cr.discards_left) }))
    self:add(line("GAME.MONEY",    { amount = num(g.dollars) }))

    local blind = g.blind
    if type(blind) == "table" and (blind.chips or 0) > 0 then
        self:add(line("GAME.SCORE", { score = num(g.chips), req = blind.chips }))
        local bname = blind.loc_name or blind.name
        if bname then self:add(line("GAME.BLIND", { name = tostring(bname) })) end
    end

    self:add(line("GAME.ANTE",  { ante = num(g.round_resets and g.round_resets.ante) }))
    self:add(line("GAME.ROUND", { round = num(g.round) }))
end

return Buffer.new("game", { update = function(self) self:repopulate(function() populate(self) end) end })
