-- Harness: the run-event dispatcher — group toggles gate speech, the Events
-- buffer records everything regardless, and history is capped.
local ROOT = arg[1] or "."
local loaded = {}
local function ba_require(name)
    if loaded[name] then return loaded[name] end
    local f = assert(io.open(ROOT .. "/src/" .. name:gsub("%.", "/") .. ".lua", "rb"))
    local code = f:read("*a"); f:close()
    local chunk = assert(load(code, "@" .. name, "t"))
    loaded[name] = true
    loaded[name] = chunk(ba_require) or true
    return loaded[name]
end

_G.love = { filesystem = { write = function() end, read = function() return nil end,
    append = function() end } }

local Settings = ba_require("settings.registry")
local Events = ba_require("events.dispatcher")
Events.register_settings()

local spoken = {}
Events.say = function(s) spoken[#spoken + 1] = s end
-- No G.E_MANAGER in the harness: emit speaks immediately.

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

-- Enabled group speaks and records.
Events.emit("tags", "tag fired")
check(spoken[1] == "tag fired", "enabled group speaks", spoken[1])
check(Events.buffer.contents[1] == "tag fired", "event recorded in the buffer", Events.buffer.contents[1])

-- Toggled-off group is silent but still recorded.
Settings.values["events.cards.enabled"] = false
spoken = {}
Events.emit("cards", "card destroyed")
check(#spoken == 0, "disabled group is silent", spoken[1])
check(Events.buffer.contents[2] == "card destroyed", "silent event still recorded", Events.buffer.contents[2])

-- Resources default OFF (per Brad: the +1/-1 deltas spam).
spoken = {}
Events.emit("resources", "+1 hand")
check(#spoken == 0, "resources default off", spoken[1])
check(Events.buffer.contents[3] == "+1 hand", "resources still recorded", Events.buffer.contents[3])

-- Empty/non-string events are dropped entirely.
Events.emit("tags", "")
Events.emit("tags", nil)
check(#Events.buffer.contents == 3, "empty events are dropped", #Events.buffer.contents)

-- Rolling history: capped at 100, oldest evicted, newest kept.
for i = 1, 150 do Events.emit("cards", "line " .. i) end
check(#Events.buffer.contents == 100, "history capped at 100", #Events.buffer.contents)
check(Events.buffer.contents[100] == "line 150", "newest entry kept", Events.buffer.contents[100])
check(Events.buffer.contents[1] == "line 51", "oldest entries evicted", Events.buffer.contents[1])

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
