-- Harness: the voice picker's logic (settings/voice_tree.lua) over a menu
-- tree shaped like the speech library's: one cycle per level along the path
-- to the chosen voice, groups opening with their auto.
local ROOT = arg[1] or "."
local f = assert(io.open(ROOT .. "/src/settings/voice_tree.lua", "rb"))
local VT = assert(load(f:read("*a"), "@voice_tree", "t"))()
f:close()

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

-- node{ kind, label, voice?, children... } with parents filled in.
local function node(kind, label, voice, children)
    local n = { kind = kind, label = label, voice = voice, children = children or {} }
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

local function shape(levels)
    local parts = {}
    for _, l in ipairs(levels) do
        local chosen = l.index and l.options[l.index]
        parts[#parts + 1] = (l.parent.label ~= "" and l.parent.label or "root") .. ">"
            .. (chosen and chosen.label or "?") .. "#" .. tostring(l.index)
    end
    return table.concat(parts, " | ")
end

-- 1) The root auto is one level: nothing to descend into.
check(shape(VT.levels(root, "auto")) == "root>Auto#1", "root auto: one row", shape(VT.levels(root, "auto")))

-- 2) A voice shows every level down to it.
local s = shape(VT.levels(root, "samantha"))
check(s == "root>AVSpeech#2 | AVSpeech>English (United States)#2 | English (United States)>Samantha#3",
    "a voice: one row per level", s)

-- 3) A group's auto is a choice like a voice.
s = shape(VT.levels(root, "auto:fr-FR"))
check(s == "root>AVSpeech#2 | AVSpeech>French (France)#3 | French (France)>Auto#1", "a language's auto", s)

-- 4) Novelty voices sit one level further down.
s = shape(VT.levels(root, "zarvox"))
check(s:match("| Novelty>Zarvox#3$") and select(2, s:gsub("|", "")) == 3, "a novelty voice: four rows", s)

-- 5) Choosing a group chooses the auto that opens it, however deep.
local av = root.children[2]
check(VT.descend(av).voice == "auto:av", "choosing a category picks its auto", VT.descend(av).voice)
local novelty = av.children[2].children[4]
check(VT.descend(novelty).voice == "auto:en-US/novelty", "choosing Novelty picks its auto", VT.descend(novelty).voice)
check(VT.descend(root.children[3]).voice == "clipboard", "choosing a voice picks it", VT.descend(root.children[3]).voice)
check(VT.descend(root.children[1]).voice == "auto", "choosing the root auto picks it")

-- 6) A voice the tree does not hold: one row with nothing chosen.
local levels = VT.levels(root, "jaws")
check(#levels == 1 and levels[1].index == nil and levels[1].parent == root,
    "an absent voice: the top row, nothing chosen", shape(levels))

-- 7) No tree at all (no library, or before the first probe).
check(#VT.levels(nil, "auto") == 0, "no tree: no rows")
levels = VT.levels(node("root", ""), "auto")
check(#levels == 1 and #levels[1].options == 0, "an empty tree: one empty row", #levels)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
