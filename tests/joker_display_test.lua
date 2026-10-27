-- Harness: reading the JokerDisplay mod's readout under a joker — nothing
-- without JokerDisplay; the visible box (full / collapsed / debuffed);
-- colour-only units spoken through the scoring formatter; sign and number
-- joined; brackets tidied; hidden readouts silent.
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

local MULT, CHIPS, XM, GREEN, GREY = { 1 }, { 2 }, { 3 }, { 4 }, { 5 }
_G.G = { UIT = { T = 1, O = 2, C = 3, R = 4, ROOT = 5 },
    C = { MULT = MULT, CHIPS = CHIPS, JOKER_DISPLAY_XMULT_TEXT = XM, GREEN = GREEN } }
local JD = ba_require("ui.joker_display")

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local function T(text, colour) return { UIT = G.UIT.T, config = { text = text, colour = colour }, children = {} } end
local function box(...) return { UIRoot = { UIT = G.UIT.ROOT, config = {}, children = { ... } }, states = { visible = true } } end
local function fmt(kind, n) return ({ mult = "+" .. n .. " mult", chips = "+" .. n .. " chips", xmult = "X" .. n .. " mult" })[kind] end

check(JD.text({ children = {} }, fmt) == nil, "no JokerDisplay: nil", JD.text({ children = {} }, fmt))

local gros = { joker_display_values = {}, children = {
    joker_display = box(T("(", GREEN), T("1 in 6", GREEN), T(")", GREEN), T("+", MULT), T("15", MULT)) } }
check(JD.text(gros, fmt) == "(1 in 6) +15 mult", "units from colour, sign joined", JD.text(gros, fmt))

local scary = { joker_display_values = {}, children = {
    joker_display = box(T("+", CHIPS), T("30", CHIPS), T("(", GREY), T("Face Cards", { 9 }), T(")", GREY)) } }
check(JD.text(scary, fmt) == "+30 chips (Face Cards)", "brackets tidied", JD.text(scary, fmt))

local bb = { joker_display_values = {}, children = { joker_display = box(T("X", XM), T("1.5", XM)) } }
check(JD.text(bb, fmt) == "X1.5 mult", "x-mult", JD.text(bb, fmt))

local small = { joker_display_values = { small = true }, children = {
    joker_display = box(T("full", GREY)), joker_display_small = box(T("small", GREY)) } }
check(JD.text(small, fmt) == "small", "collapsed reads the small box", JD.text(small, fmt))

local hidden = { joker_display_values = { disabled = true }, children = { joker_display = box(T("+5", MULT)) } }
check(JD.text(hidden, fmt) == nil, "hidden readout is silent", JD.text(hidden, fmt))

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
