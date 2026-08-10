-- Harness: rebind capture + modifier dispatch + binding conflicts through the
-- real input manager.
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

-- LÖVE keyboard state the manager polls (modifiers are read from the input
-- layer, not the game's held_keys table).
local held = {}
_G.love = { keyboard = { isDown = function(...)
    for _, k in ipairs({ ... }) do if held[k] then return true end end
    return false
end } }

local Input = ba_require("input.manager")
local KB = Input.KeyboardBinding

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local ctrl = { held_keys = {} }   -- game Controller stub

-- 1) Capture a Ctrl combo: Ctrl press is swallowed, S press binds Ctrl+S.
local captured
Input.start_listening(function(b) captured = b end)
held.lctrl = true
Input.on_key_down(ctrl, "lctrl")
check(captured == nil, "modifier press alone doesn't finish capture", captured)
Input.on_key_down(ctrl, "s")
check(captured and captured.key == "s" and captured.ctrl == true
    and not captured.shift and not captured.alt,
    "Ctrl+S captures with ctrl folded in",
    captured and captured:display())
held.lctrl = false
Input.on_key_up(ctrl, "lctrl")
check(captured.key == "s", "late modifier release doesn't re-capture", captured.key)

-- 2) Capture a bare modifier: pressed and released alone binds itself.
captured = nil
Input.start_listening(function(b) captured = b end)
held.lshift = true
Input.on_key_down(ctrl, "lshift")
check(captured == nil, "held modifier still pending", captured)
held.lshift = false
Input.on_key_up(ctrl, "lshift")
check(captured and captured.key == "lshift" and not captured.shift,
    "lone Shift press-release binds bare lshift", captured and captured:display())

-- 3) Capture Ctrl+arrow (the buffer-restore scenario).
captured = nil
Input.start_listening(function(b) captured = b end)
held.lctrl = true
Input.on_key_down(ctrl, "lctrl")
Input.on_key_down(ctrl, "left")
check(captured and captured.key == "left" and captured.ctrl,
    "Ctrl+Left captures for the buffer keys", captured and captured:display())
held.lctrl = false
Input.on_key_up(ctrl, "lctrl")

-- 4) Normal dispatch: a bare modifier binding (Shift = Back) still matches
--    even though isDown reports the key itself as held.
Input.actions = {}
Input.by_key = {}
local fired = {}
Input.register{ key = "back", bindings = { KB.new("lshift") },
    handler = function() fired.back = (fired.back or 0) + 1 end }
Input.register{ key = "bare_nav", bindings = { KB.new("left") },
    handler = function() fired.bare = (fired.bare or 0) + 1 end }
Input.register{ key = "buffer_nav", bindings = { KB.new("left", true) },
    handler = function() fired.buffer = (fired.buffer or 0) + 1 end }
held.lshift = true
local consumed = Input.on_key_down(ctrl, "lshift")
held.lshift = false
check(consumed and fired.back == 1, "bare Shift binding fires (own group excluded)", fired.back)

-- 5) Specificity: Ctrl+Left beats bare Left when Ctrl is held.
held.lctrl = true
Input.on_key_down(ctrl, "left")
held.lctrl = false
check(fired.buffer == 1 and not fired.bare, "Ctrl+Left picks the chord action", fired.buffer)
Input.on_key_down(ctrl, "left")
check(fired.bare == 1 and fired.buffer == 1, "bare Left picks the bare action", fired.bare)

-- 6) Conflict detection: another action holding the same binding is found;
--    the action's own binding, or a different-modifier variant, is not.
local c = Input.conflict("back", KB.new("left"))
check(c and c.key == "bare_nav", "bare Left conflicts with its holder", c and c.key)
c = Input.conflict("bare_nav", KB.new("left"))
check(c == nil, "rebinding an action to its own key is not a conflict", c and c.key)
c = Input.conflict("back", KB.new("left", true))
check(c and c.key == "buffer_nav", "Ctrl+Left conflicts with the chord holder", c and c.key)
c = Input.conflict("back", KB.new("left", false, true))
check(c == nil, "Shift+Left is free (modifiers distinguish)", c and c.key)

-- 7) Pad conflicts via the button map.
Input.PAD_ACTIONS = { a = "back" }
c = Input.pad_conflict("bare_nav", "a")
check(c and c.key == "back", "pad button conflicts with its holder", c and c.key)
c = Input.pad_conflict("back", "a")
check(c == nil, "own pad button is not a conflict", c and c.key)
c = Input.pad_conflict("back", "y")
check(c == nil, "unmapped pad button is free", c and c.key)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
