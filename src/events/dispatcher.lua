-- events/dispatcher.lua — the run-event layer, a lightweight take on
-- SayTheSpire2's EventDispatcher + EventRegistry.
--
-- Game hooks (core.lua) emit EVENTS: emit(group, text). The dispatcher
-- gates speech on the group's single settings toggle — coarse GROUPS,
-- deliberately not STS2's per-event granularity — speaks on the game's own
-- event queue so lines land near their popups, and mirrors EVERY event into
-- the Events review buffer regardless of toggles (buffers are always the
-- full-detail view).
--
-- Groups:
--   tags       tag effects firing (Investment +$25, Grim, tag NOPE)
--   cards      cards created / destroyed / transformed (Wheel of Fortune,
--              Judgement, Ceremonial Dagger's victim, "No space!")
--   resources  hand/discard/ante/round deltas the game pops next to the HUD
--              (money deliberately NOT here: every dollar change already
--              announces through scoring / cash-out / tag paths)
local require = ...
local Buffer = require("buffers.buffer")
local Settings = require("settings.registry")

local M = { say = nil }

-- One toggle per group, surfaced in the Announcements screen.
M.GROUPS = {
    { key = "tags",      label_key = "SET.EV_TAGS" },
    { key = "cards",     label_key = "SET.EV_CARDS" },
    { key = "resources", label_key = "SET.EV_RESOURCES" },
}

function M.register_settings()
    for _, g in ipairs(M.GROUPS) do
        Settings.register{ key = "events." .. g.key .. ".enabled", type = "bool",
            label_key = g.label_key, default = true, category = "announce" }
    end
end

local function enabled(group)
    local v = Settings.value("events." .. group .. ".enabled")
    if v == nil then return true end
    return v
end

-- Rolling history, browsable via the review buffers (newest last). Capped so
-- a long run can't grow it unbounded; the cursor tracks removals.
local MAX_HISTORY = 100
M.buffer = Buffer.new("events", { follow_latest = true })

local function push_history(text)
    local b = M.buffer
    b.contents[#b.contents + 1] = text
    if #b.contents > MAX_HISTORY then
        table.remove(b.contents, 1)
        if b.position > 1 then b.position = b.position - 1 end
    end
end

-- Emit one event. opts.instant speaks immediately — for hooks that already
-- run at their popup's moment; everything else queues on the game's event
-- manager so the line lands on the animation's beat, like scoring does.
function M.emit(group, text, opts)
    if type(text) ~= "string" or text == "" then return end
    push_history(text)
    if not enabled(group) then return end
    local function s() if M.say then M.say(text) end end
    if (opts and opts.instant) or not (G and G.E_MANAGER and Event) then
        s()
    else
        G.E_MANAGER:add_event(Event({
            trigger = "immediate",
            func = function() s(); return true end,
        }))
    end
end

return M
