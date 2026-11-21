-- platform/voiceover.lua — speech and braille through VoiceOver on macOS.
--
-- Loadstar has no VoiceOver voice (Prism's proved unreliable for its author),
-- so on a Mac Blindfold spoke only through the system synthesizer, at its own
-- rate and without braille. This module hands text to VoiceOver itself, so
-- it speaks with the user's VoiceOver voice, rate and verbosity and shows on
-- their braille display, as NVDA does on Windows.
--
-- How: an accessibility announcement posted on the game's window
-- (NSAccessibilityPostNotificationWithUserInfo with
-- NSAccessibilityAnnouncementRequestedNotification). No permission is
-- needed, but VoiceOver only speaks it while the game is the active app.
--
-- VoiceOver has no queue for announcements: every new one cuts the one it
-- is speaking, whatever its priority (tested by ear on macOS 27), and it
-- never says when it has finished. So the queue lives here. Lines said in
-- one frame are joined into one announcement (pump); a line that should not
-- interrupt waits until the one before it has probably finished, estimated
-- from its length and the user's VoiceOver speed (set_cps, the "VoiceOver
-- speed" slider). Lines that pile up meanwhile go out together.
--
-- Talks to AppKit through LuaJIT's FFI and the Objective-C runtime, every
-- message through a cast to its exact prototype (objc_msgSend must not be
-- called variadically on arm64). Must run on the main thread, which is
-- where the game calls speech.say and love.update.
local ffi = require("ffi")

local M = { available = false }

if ffi.os ~= "OSX" then return M end

-- Declared one block at a time: a block LuaJIT has seen before (macos.lua
-- declares the runtime too) fails as a whole, and pcall keeps the rest.
pcall(ffi.cdef, [[
    void *objc_getClass(const char *name);
    void *sel_registerName(const char *name);
    void objc_msgSend(void);
]])
pcall(ffi.cdef, [[
    void *objc_autoreleasePoolPush(void);
    void objc_autoreleasePoolPop(void *pool);
]])
pcall(ffi.cdef, [[
    void NSAccessibilityPostNotificationWithUserInfo(void *element, void *notification, void *user_info);
    void *NSAccessibilityAnnouncementRequestedNotification;
    void *NSAccessibilityAnnouncementKey;
    void *NSAccessibilityPriorityKey;
]])

local C = ffi.C
local send = ffi.cast("void *", C.objc_msgSend)
local msg = ffi.cast("void *(*)(void *, void *)", send)
local msg_bool = ffi.cast("signed char (*)(void *, void *)", send)
local msg_str = ffi.cast("void *(*)(void *, void *, const char *)", send)
local msg_long = ffi.cast("void *(*)(void *, void *, long)", send)
local msg_dict = ffi.cast("void *(*)(void *, void *, void **, void **, unsigned long)", send)
local sel = C.sel_registerName

local PRIORITY_MEDIUM, PRIORITY_HIGH = 50, 90   -- NSAccessibilityPriorityLevel

-- Characters per second VoiceOver speaks at; set from the user's setting.
M.cps = 38   -- the slider's default (75), tuned by ear against a fast VoiceOver
function M.set_cps(cps)
    if type(cps) == "number" and cps > 0 then M.cps = cps end
end

-- About how long VoiceOver takes to say `text`: characters at M.cps, plus
-- the pauses it makes at punctuation and a little to get started.
function M.estimate(text)
    local chars = #text:gsub("[\128-\191]", "")   -- UTF-8 characters, not bytes
    local _, pauses = text:gsub("[%.%,%!%?%:;]", "")
    return 0.12 + chars / M.cps + pauses * 0.07
end

local ok_init, err_init = pcall(function()
    M.cls = {
        NSApplication = C.objc_getClass("NSApplication"),
        NSWorkspace = C.objc_getClass("NSWorkspace"),
        NSString = C.objc_getClass("NSString"),
        NSNumber = C.objc_getClass("NSNumber"),
        NSDictionary = C.objc_getClass("NSDictionary"),
    }
    M.sel = {
        sharedApplication = sel("sharedApplication"),
        sharedWorkspace = sel("sharedWorkspace"),
        isVoiceOverEnabled = sel("isVoiceOverEnabled"),
        keyWindow = sel("keyWindow"),
        mainWindow = sel("mainWindow"),
        stringWithUTF8String = sel("stringWithUTF8String:"),
        numberWithLong = sel("numberWithLong:"),
        dictionaryWithObjects = sel("dictionaryWithObjects:forKeys:count:"),
    }
    -- Touch the AppKit symbols now, so a missing one fails here, not mid-game.
    M.notification = C.NSAccessibilityAnnouncementRequestedNotification
    M.key_text = C.NSAccessibilityAnnouncementKey
    M.key_priority = C.NSAccessibilityPriorityKey
    assert(M.notification ~= nil and M.key_text ~= nil and M.key_priority ~= nil,
        "AppKit announcement constants are null")
end)
M.available = ok_init
M.init_error = not ok_init and tostring(err_init) or nil

-- The clock the queue runs on (a test swaps it).
function M.clock()
    local ok, t = pcall(function() return love.timer.getTime() end)
    return ok and t or os.clock()
end
local function now() return M.clock() end

-- Is VoiceOver on? Asked of NSWorkspace at most twice a second.
local _running, _checked_at = false, -1
function M.running()
    if not M.available then return false end
    local t = now()
    if t - _checked_at < 0.5 then return _running end
    _checked_at = t
    local ok, on = pcall(function()
        local ws = msg(M.cls.NSWorkspace, M.sel.sharedWorkspace)
        return ws ~= nil and msg_bool(ws, M.sel.isVoiceOverEnabled) ~= 0
    end)
    _running = ok and on or false
    return _running
end

-- The element VoiceOver hears the announcement from: the game's window
-- (key, else main), else the application itself.
local function target()
    local app = msg(M.cls.NSApplication, M.sel.sharedApplication)
    if app == nil then return nil end
    local w = msg(app, M.sel.keyWindow)
    if w == nil then w = msg(app, M.sel.mainWindow) end
    return w ~= nil and w or app
end

local keys = ffi.new("void *[2]")
local objs = ffi.new("void *[2]")

-- VoiceOver reads "96/1200" as a fraction ("96 and 1/2, 0 0"): spaced out,
-- it reads the numbers whole with "slash" between them, as NVDA does.
-- Game text also carries layout spacing ("( lvl.1 )  Level up"), which
-- VoiceOver can turn into pauses: runs of spaces and the spaces inside
-- brackets go.
function M.tidy(text)
    text = text:gsub("(%d)/(%d)", "%1 / %2")
    text = text:gsub("%(%s+", "("):gsub("%s+%)", ")"):gsub("%s%s+", " ")
    return text
end

-- Post one announcement now. Returns true when it went out.
function M.post(text, interrupt)
    if not M.available or type(text) ~= "string" or text == "" then return false end
    text = M.tidy(text)
    local pool = C.objc_autoreleasePoolPush()
    local ok, err = pcall(function()
        local element = target()
        assert(element ~= nil, "no window or application to announce from")
        local str = msg_str(M.cls.NSString, M.sel.stringWithUTF8String, text)
        assert(str ~= nil, "text is not valid UTF-8")
        local prio = msg_long(M.cls.NSNumber, M.sel.numberWithLong,
            interrupt and PRIORITY_HIGH or PRIORITY_MEDIUM)
        keys[0], keys[1] = M.key_text, M.key_priority
        objs[0], objs[1] = str, prio
        local info = msg_dict(M.cls.NSDictionary, M.sel.dictionaryWithObjects, objs, keys, 2)
        C.NSAccessibilityPostNotificationWithUserInfo(element, M.notification, info)
    end)
    C.objc_autoreleasePoolPop(pool)
    if not ok then M.last_error = tostring(err) end
    return ok
end

-- Lines said this frame, and whether they interrupt. Blindfold cuts speech
-- by calling silence() when a key is handled and then saying the new line
-- (speech.lua), so a silence marks whatever follows it within
-- INTERRUPT_WINDOW seconds as interrupting.
local INTERRUPT_WINDOW = 0.25
local frame, frame_interrupt = {}, false
local silenced_at = nil

-- Announcements waiting for VoiceOver to finish the one it is speaking, one
-- per frame that said something, oldest first. Past CATCH_UP of them the
-- rest go out together, so speech cannot fall ever further behind.
local CATCH_UP = 4
local queue = {}

-- When the announcement VoiceOver is speaking will probably be over.
local busy_until = 0

-- Queue a line for this frame. An interrupting line drops what was queued
-- before it, as the speech queue does.
function M.say(text, interrupt)
    if interrupt then frame = {} end
    if interrupt or (silenced_at and now() - silenced_at <= INTERRUPT_WINDOW) then
        frame_interrupt = true
    end
    frame[#frame + 1] = text
end

-- Cut speech: drop everything waiting; the next line interrupts VoiceOver
-- (there is no call that just stops it; its own Control key does).
function M.silence()
    frame, frame_interrupt, queue = {}, false, {}
    silenced_at = now()
end

-- Joined so VoiceOver pauses between lines: a line that does not end in
-- punctuation gets a period.
local function join(lines)
    local parts = {}
    for i, l in ipairs(lines) do
        l = l:gsub("^%s+", ""):gsub("%s+$", "")
        if l ~= "" then
            if i < #lines and not l:find("[%.%!%?%:;,]$") then l = l .. "." end
            parts[#parts + 1] = l
        end
    end
    return table.concat(parts, " ")
end

local function post_timed(text, interrupt, t)
    if text ~= "" and M.post(text, interrupt) ~= false then
        busy_until = t + M.estimate(M.tidy(text))
    end
end

-- End of frame. What this frame said becomes one announcement: at once if
-- it interrupts, else at the back of the queue. Then, once VoiceOver has
-- probably finished, the next queued announcement goes out: one at a time,
-- so a run of short lines (scoring) keeps an even rhythm.
function M.pump()
    local t = now()
    if #frame > 0 then
        local text, interrupt = join(frame), frame_interrupt
        frame, frame_interrupt = {}, false
        if interrupt then
            silenced_at = nil
            queue = {}
            post_timed(text, true, t)
        elseif text ~= "" then
            queue[#queue + 1] = text
        end
    end
    if #queue == 0 or t < busy_until then return end
    local text
    if #queue > CATCH_UP then
        text = join(queue)
        queue = {}
    else
        text = table.remove(queue, 1)
    end
    post_timed(text, false, t)
end

return M
