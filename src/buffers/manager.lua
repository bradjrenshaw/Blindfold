-- buffers/manager.lua — registry of buffers + the navigation controls (port of
-- SayTheSpire2's BufferManager + BufferControls). Left/right cycle between the
-- enabled buffers; up/down move within the current buffer. Each move speaks the
-- result. `M.say` is set to speech.say by core.
local require = ...
local Message = require("ui.message")

local M = { buffers = {}, position = 0, say = nil }

local function speak(text)
    if M.say and type(text) == "string" and text ~= "" then M.say(text) end
end
local function speak_loc(key, vars) speak(Message.localized(key, vars):resolve()) end
local function buffer_label(b) return Message.localized("BUFFER." .. string.upper(b.key)):resolve() end

function M.add(b)
    M.buffers[#M.buffers + 1] = b
    if M.position == 0 and b.enabled then M.position = #M.buffers end
    return b
end

function M.get(key)
    for _, b in ipairs(M.buffers) do if b.key == key then return b end end
    return nil
end

function M.current()
    if M.position < 1 or M.position > #M.buffers then return nil end
    local b = M.buffers[M.position]
    return b.enabled and b or nil
end

-- Cycle to the next/previous ENABLED buffer (dir = +1 / -1).
local function step(dir)
    if #M.buffers == 0 then return false end
    local start = (M.position >= 1) and M.position or (dir > 0 and #M.buffers or 1)
    local i = start
    repeat
        i = i + dir
        if i > #M.buffers then i = 1 elseif i < 1 then i = #M.buffers end
        if M.buffers[i].enabled then
            M.position = i
            M.buffers[i]:update()
            if M.buffers[i].follow_latest and M.buffers[i]:count() > 0 then
                M.buffers[i].position = M.buffers[i]:count()
            end
            return true
        end
    until i == start
    return false
end

function M.report_buffer()
    local b = M.current()
    if not b then speak_loc("BUFFER.NONE", {}); return end
    if b:is_empty() then speak_loc("BUFFER.EMPTY", { buffer = buffer_label(b) }); return end
    speak_loc("BUFFER.CURRENT", { buffer = buffer_label(b), item = b:current_item() })
end

function M.report_item()
    local b = M.current()
    if not b then speak_loc("BUFFER.NONE", {}); return end
    if b:is_empty() then speak_loc("BUFFER.EMPTY", { buffer = buffer_label(b) }); return end
    speak(b:current_item())
end

function M.next_buffer() step(1);  M.report_buffer() end
function M.prev_buffer() step(-1); M.report_buffer() end
function M.next_item() local b = M.current(); if b then b:move_to_next() end; M.report_item() end
function M.prev_item() local b = M.current(); if b then b:move_to_previous() end; M.report_item() end

return M
