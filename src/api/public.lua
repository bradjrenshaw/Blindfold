-- api/public.lua — the runtime API other mods call (docs/mod-api.md, layer
-- 2), installed onto the global Blindfold table:
--
--   Blindfold.api_version                  -- 1
--   Blindfold.say(text, { interrupt })     -- speak once
--   Blindfold.announce(text)               -- speak + keep in the Events buffer
--   Blindfold.card_info(id, fn)            -- fn(card) -> string | { strings }:
--                                          --   read right after a card's name
--   Blindfold.add_buffer{ key, label, lines = fn() -> { strings } }
--
-- A mod that loads before Blindfold can queue its setup instead:
--   BLINDFOLD_QUEUE = BLINDFOLD_QUEUE or {}
--   table.insert(BLINDFOLD_QUEUE, function(Blindfold) ... end)
-- The queue is run once Blindfold boots, and checked again every frame.
--
-- Registrations live on the host (_G.BlindfoldHost.api), so a dev hot reload
-- keeps them; ids / keys make registering twice replace, not duplicate.
local require = ...
local Buffer = require("buffers.buffer")

local M = {}

local VERSION = 1

local function registry()
    local H = _G.BlindfoldHost or {}
    _G.BlindfoldHost = H
    H.api = H.api or { card_info = {}, card_order = {}, buffers = {}, buffer_order = {} }
    return H.api
end

local function str(v)
    if type(v) == "number" then v = tostring(v) end
    return type(v) == "string" and v ~= "" and v or nil
end

-- Lines the mods have for a card: each registered card_info, then the card's
-- own center field (center.blindfold.info, a function(card) on the mod's
-- object definition, no registration needed). Failures are skipped.
function M.card_lines(card)
    local out = {}
    local function take(fn)
        if type(fn) ~= "function" then return end
        local ok, r = pcall(fn, card)
        if not ok then return end
        if type(r) == "table" then
            for _, l in ipairs(r) do out[#out + 1] = str(l) end
        else
            out[#out + 1] = str(r)
        end
    end
    local R = registry()
    for _, id in ipairs(R.card_order) do take(R.card_info[id]) end
    local center = type(card) == "table" and card.config and card.config.center
    local bf = type(center) == "table" and center.blindfold
    if type(bf) == "table" then take(bf.info) end
    return out
end

local function make_buffer(spec)
    local label = spec.label
    local b = Buffer.new("mod_" .. spec.key, {
        update = function(self)
            self:repopulate(function()
                local ok, lines = pcall(spec.lines)
                for _, l in ipairs(ok and type(lines) == "table" and lines or {}) do
                    self:add(str(l))
                end
            end)
        end,
    })
    b.label = function()
        if type(label) == "function" then
            local ok, l = pcall(label)
            return ok and str(l) or spec.key
        end
        return str(label) or spec.key
    end
    return b
end

-- Install onto the Blindfold table. deps: { say, emit, buffers } — speech,
-- the events dispatcher's emit, and the buffer manager.
function M.install(BF, deps)
    local R = registry()
    local added = {}   -- this generation's buffer per key

    local function add_to_manager(spec)
        if added[spec.key] or not deps.buffers then return end
        added[spec.key] = deps.buffers.add(make_buffer(spec))
    end

    BF.api_version = VERSION

    function BF.say(text, opts)
        text = str(text)
        if text and deps.say then deps.say(text, opts and opts.interrupt == true) end
    end

    function BF.announce(text)
        text = str(text)
        if text and deps.emit then deps.emit("mods", text, { instant = true }) end
    end

    function BF.card_info(id, fn)
        if type(id) == "function" then id, fn = tostring(id), id end
        id = str(id)
        if not id or type(fn) ~= "function" then return false end
        if not R.card_info[id] then R.card_order[#R.card_order + 1] = id end
        R.card_info[id] = fn
        return true
    end

    function BF.add_buffer(spec)
        if type(spec) ~= "table" or not str(spec.key) or type(spec.lines) ~= "function" then
            return false
        end
        if not R.buffers[spec.key] then R.buffer_order[#R.buffer_order + 1] = spec.key end
        R.buffers[spec.key] = spec
        if added[spec.key] then
            -- re-registered: point the live buffer at the new spec
            local fresh = make_buffer(spec)
            added[spec.key]._update, added[spec.key].label = fresh._update, fresh.label
        else
            add_to_manager(spec)
        end
        return true
    end

    -- Buffers registered in an earlier generation.
    for _, key in ipairs(R.buffer_order) do add_to_manager(R.buffers[key]) end

    M.drain(BF)
end

-- Run what mods queued (BLINDFOLD_QUEUE). Called at install and per frame.
function M.drain(BF)
    local q = _G.BLINDFOLD_QUEUE
    if type(q) ~= "table" or q[1] == nil then return end
    _G.BLINDFOLD_QUEUE = {}
    for _, fn in ipairs(q) do
        if type(fn) == "function" then pcall(fn, BF) end
    end
end

return M
