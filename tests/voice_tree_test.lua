-- Harness: the voice picker. settings/voice_tree.lua (which lines a tree view
-- lists) and overlays/voice_picker.lua driven through the real dispatcher:
-- up/down between lines, right/left opening and closing groups, Enter
-- choosing, over a menu tree shaped like the speech library's.
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

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local Message = ba_require("ui.message")
Message.set_resolver(function(key)
    local words = { ["SET.TREE_EXPANDED"] = "expanded", ["SET.TREE_COLLAPSED"] = "collapsed",
        ["CARD.SELECTED"] = "selected", ["SET.TREE_LEVEL"] = "level {n}" }
    return words[key] or key
end)
local VT = ba_require("settings.voice_tree")
local Picker = ba_require("overlays.voice_picker")
local D = ba_require("overlay.dispatcher")

-- A menu tree like speech.menu's: parents filled in, ids unique.
local next_id = 0
local function node(kind, label, voice, children)
    next_id = next_id + 1
    local n = { id = "n" .. next_id, kind = kind, label = label, voice = voice, children = children or {} }
    for _, c in ipairs(n.children) do c.parent = n end
    return n
end
local function group(kind, label, auto, ...)
    local kids = { node("auto", "Auto", auto) }
    for _, c in ipairs({ ... }) do kids[#kids + 1] = c end
    return node(kind, label, nil, kids)
end
local function voice(name) return node("voice", name, name:lower()) end

local root = node("root", "", nil, {
    node("auto", "Auto", "auto"),
    group("category", "AVSpeech", "auto:av",
        group("language", "English (United States)", "auto:en-US",
            voice("Fred"), voice("Samantha"),
            group("novelty", "Novelty", "auto:en-US/novelty", voice("Bells"), voice("Zarvox"))),
        group("language", "French (France)", "auto:fr-FR", voice("Thomas"))),
    voice("Clipboard"),
})

-- 1) Which lines a tree view lists.
local function listing(expanded)
    local parts = {}
    for _, l in ipairs(VT.visible(root, expanded)) do parts[#parts + 1] = l.depth .. ":" .. l.node.label end
    return table.concat(parts, " ")
end
check(listing({}) == "1:Auto 1:AVSpeech 1:Clipboard", "all closed: the top level only", listing({}))
local expanded = {}
VT.expand_to(VT.find(root, "samantha"), expanded)
check(listing(expanded) == "1:Auto 1:AVSpeech 2:Auto 2:English (United States) 3:Auto 3:Fred 3:Samantha "
    .. "3:Novelty 2:French (France) 1:Clipboard", "opened down to a voice: its groups, nothing else", listing(expanded))
check(VT.find(root, "auto:fr-FR").parent.label == "French (France)", "a group's auto is found like a voice")
check(VT.find(root, "jaws") == nil, "an absent voice has no line")
check(#VT.visible(nil, {}) == 0, "no tree: no lines")

-- 2) The picker, driven like the game drives it.
_G.G = { OVERLAY_MENU = { blindfold_title_key = "SET.VOICE_PICK" } }
D.register(Picker)
local picked
local view = Picker.open(root, "samantha", function(n) return n.label end, function(v) picked = v end)
check(view.text == "Samantha", "the screen shows the current choice", view.text)

local function tick(kind, dir)
    local r = D.tick(kind and { kind = kind, dir = dir, mods = {} } or nil)
    return r and r.message or nil
end
-- The label of the line under the cursor.
local function focused()
    local cur = D.cache[Picker.id].state.cur
    for _, l in ipairs(VT.visible(root, Picker.state.expanded)) do
        if "vt:" .. l.node.id == cur.key then return l.node.label end
    end
end
-- A key, then the frame after it (where a suggested move is announced).
local function key(kind, dir)
    local said = tick(kind, dir)
    local after = tick()
    if said and after then return said .. " / " .. after end
    return said or after
end

check(tick() == "Samantha, selected", "opens on the current choice", "?")
check(key("move_to_edge", "left") == "Auto", "Home reaches the lines above the choice", "?")
check(key("move_to_edge", "right") == "Clipboard", "End: the last line", "?")
for _ = 1, 3 do key("move", "up") end   -- back to Samantha
check(key("move", "down") == "Novelty, collapsed", "down: the next line", "?")
check(key("move_to_edge", "right") == "Clipboard", "End from a group: still the last line", "?")
check(key("move", "up") == "level 2, French (France), collapsed", "up from the last line", "?")
check(key("move_to_edge", "left") == "Auto", "Home from a group: still the first line", "?")
for _ = 1, 7 do key("move", "down") end   -- back to Novelty
check(focused() == "Novelty", "and back down to Novelty", focused())
check(key("move", "right") == "expanded", "right on a closed group opens it", "?")
check(key("move", "right") == "Auto", "right on an open group: its first line", "?")
check(key("move", "down") == "Bells", "down inside the group", "?")
check(key("move", "left") == "Novelty, expanded", "left from a voice: its group", "?")
check(key("move", "left") == "collapsed", "left on an open group closes it", "?")
check(key("move", "left") == "English (United States), expanded", "left on a closed group: the group above", "?")
local s = key("move", "up")
check(s == "Auto", "up within a level: just the line", s)
s = key("move", "up")
check(s == "level 1, AVSpeech, expanded", "up across a level says the level first", s)
s = key("move", "down")
check(s == "level 2, Auto", "and down across one", s)
key("move", "up")
check(key("move", "left") == "collapsed", "closing a category", "?")
check(key("move", "left") == nil, "left at the top level: nothing", "?")
check(key("move", "down") == "Clipboard", "a closed group hides its lines", "?")
check(key("move", "down") == nil, "down at the end: silent", "?")
check(key("move_to_edge", "left") == "Auto", "Home: the first line", "?")
check(view.text == "Auto", "the screen follows the focused line", view.text)

-- Enter on a group toggles it; Enter on a voice or an auto chooses it.
key("move", "down")
check(key("confirm") == "expanded", "Enter on a group opens it", "?")
check(picked == nil, "and chooses nothing", picked)
key("move", "right")
s = key("confirm")
check(picked == "auto:av", "Enter on an auto chooses it", picked)
key("move", "down"); key("move", "right"); key("move", "right"); key("move", "down")
key("confirm")
check(picked == "fred", "Enter on a voice chooses it", picked)

-- 3) Not the picker's screen: it stands down.
_G.G.OVERLAY_MENU.blindfold_title_key = "SET.VOICE"
check(Picker:handler() == "inactive", "inactive on any other screen")

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
