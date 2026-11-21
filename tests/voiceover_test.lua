-- Harness: the VoiceOver queue (src/platform/voiceover.lua). VoiceOver cuts
-- every announcement with the next one, so the module joins a frame's lines,
-- holds a queued line until the previous one has probably been spoken, and
-- lets a line after silence() (a key press) cut in at once.
--
-- Off macOS (or without AppKit) the module loads with available = false;
-- the queue logic is plain Lua, so it runs here with post() and the clock
-- swapped for fakes.
local ROOT = arg[1] or "."
local VO = assert(dofile(ROOT .. "/src/platform/voiceover.lua"))

local failures = 0
local function check(cond, what)
    if cond then print("ok   " .. what)
    else failures = failures + 1; print("FAIL " .. what) end
end

local t = 0
VO.clock = function() return t end
local posted = {}
VO.post = function(text, interrupt)
    posted[#posted + 1] = { text = text, interrupt = interrupt }
    return true
end
VO.set_cps(10)   -- easy arithmetic: 10 characters a second

-- A frame's lines go out together, joined with a period between them.
VO.say("Ace of Spades")
VO.say("Plus 11 chips")
VO.pump()
check(#posted == 1, "one announcement for one frame")
check(posted[1].text == "Ace of Spades. Plus 11 chips", "lines joined with a period")
check(posted[1].interrupt == false, "a plain line does not interrupt")

-- A queued line waits while the previous one is still being spoken, and
-- queued lines then go out one at a time (an even rhythm in scoring).
local busy = VO.estimate("Ace of Spades. Plus 11 chips")
check(busy > 2.5 and busy < 4, "estimate follows length and speed (" .. busy .. "s)")
t = t + 0.5
VO.say("Pair")
VO.pump()
check(#posted == 1, "queued line held while VoiceOver speaks")
t = t + 0.5
VO.say("Level 1")
VO.pump()
check(#posted == 1, "still held")
t = busy + 0.01
VO.pump()
check(#posted == 2 and posted[2].text == "Pair", "oldest held line goes out first, alone")
t = t + VO.estimate("Pair") + 0.01
VO.pump()
check(#posted == 3 and posted[3].text == "Level 1", "then the next one")

-- A long backlog goes out together, so speech catches up.
t = t + 10
for i = 1, 6 do
    VO.say("Plus " .. i)
    VO.pump()   -- the first goes out at once; the rest queue behind it
end
check(#posted == 4 and posted[4].text == "Plus 1", "backlog: first line at once")
t = t + 10
VO.pump()
check(#posted == 5 and posted[5].text == "Plus 2. Plus 3. Plus 4. Plus 5. Plus 6",
    "backlog past the limit joined (" .. tostring(posted[5] and posted[5].text) .. ")")

-- A key press: silence(), then the new line cuts in at once.
t = t + 0.1
VO.say("stale line")
VO.silence()
VO.say("Two of Hearts")
VO.pump()
check(#posted == 6 and posted[6].text == "Two of Hearts", "silence drops the queued line")
check(posted[6].interrupt == true, "line after silence interrupts")

-- The interrupt does not linger: a later plain line queues normally.
t = t + 10
VO.say("Round won")
VO.pump()
check(posted[7] and posted[7].interrupt == false, "later line no longer interrupts")

-- An explicit interrupt drops what was queued in the same frame.
t = t + 10
VO.say("old")
VO.say("new", true)
VO.pump()
check(posted[8].text == "new" and posted[8].interrupt == true, "say(text, true) replaces the frame's lines")

-- Accented text counts characters, not bytes.
check(math.abs(VO.estimate("čšž") - VO.estimate("csz")) < 1e-9, "UTF-8 characters counted once")

-- Counts like "96/1200" are spaced so VoiceOver does not read a fraction.
check(VO.tidy("Joker Stickers,  (96/1200) 8%") == "Joker Stickers, (96 / 1200) 8%", "counts with a slash spaced out")
check(VO.tidy("and/or") == "and/or", "slashes between words untouched")
check(VO.tidy("( lvl.1 )  Level up Full House") == "(lvl.1) Level up Full House", "layout spacing removed")

if failures > 0 then print(failures .. " FAILURES"); os.exit(1) end
print("ALL PASS")
