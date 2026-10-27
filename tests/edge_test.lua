-- Harness: edge navigation is SILENT (no re-read of the current control),
-- while real moves and Home/End keep speaking.
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

local D = ba_require("overlay.dispatcher")
local Id = ba_require("overlay.id")
local Message = ba_require("ui.message")

-- A three-item vertical list, no wrapping.
local active = true
local ov = {
    id = "t",
    handler = function() return active and "active" or "inactive" end,
    build = function(self, b)
        b:capture_input()
        for i = 1, 3 do
            b:add_item(Id.structural("i" .. i), { label = function(ctx)
                ctx.message:fragment(Message.raw("item " .. i))
            end })
        end
    end,
}
D.register(ov)

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local res = D.tick(nil)
check(res and res.message == "item 1", "open speaks the start", res and res.message)

-- Up at the top edge: SILENT — no re-read of item 1.
res = D.tick({ kind = "move", dir = "up" })
check(res and (res.message == nil or res.message == ""),
    "up at the top edge is silent", res and res.message)
check(res and not res.moved, "edge reports no move", res and res.moved)

-- A real move still speaks.
res = D.tick({ kind = "move", dir = "down" })
check(res and res.message == "item 2", "real move speaks the destination", res and res.message)

-- Sideways where no edges exist at all: also silent.
res = D.tick({ kind = "move", dir = "left" })
check(res and (res.message == nil or res.message == ""),
    "left with no transition is silent", res and res.message)

-- Bottom edge, same.
D.tick({ kind = "move", dir = "down" })
res = D.tick({ kind = "move", dir = "down" })
check(res and (res.message == nil or res.message == ""),
    "down at the bottom edge is silent", res and res.message)

-- Home/End keep their landing announcement (explicit jump = confirmation).
res = D.tick({ kind = "move_to_edge", dir = "left" })
check(res and res.message == "item 1", "Home still announces the landing", res and res.message)
res = D.tick({ kind = "move_to_edge", dir = "left" })
check(res and res.message == "item 1", "Home at the start still confirms", res and res.message)

-- The open-announce race: an arrow press that lands BEFORE the frame tick on
-- a freshly opened screen and bumps an edge must NOT suppress the start
-- announcement (the silent bump used to poison last_spoken; user report:
-- screens opened mute).
active = false
D.tick(nil)   -- overlay closes, cache and last_spoken drop
active = true
res = D.tick({ kind = "move", dir = "up" })   -- races the open, hits the top edge
check(res and (res.message == nil or res.message == ""),
    "racing edge bump on a fresh screen is silent", res and res.message)
res = D.tick(nil)
check(res and res.message == "item 1",
    "the open-announce still follows the racing bump", res and res.message)
res = D.tick(nil)
check(res == nil, "and speaks only once", res and res.message)

-- Whereas a racing REAL move announces its destination and stands as the
-- open announcement (nothing extra afterward).
active = false
D.tick(nil)
active = true
res = D.tick({ kind = "move", dir = "down" })
check(res and res.message == "item 2", "racing real move speaks its destination", res and res.message)
res = D.tick(nil)
check(res == nil, "no duplicate announce after a racing move", res and res.message)

-- Handoff to another overlay that lands on the SAME game element (Steamodded's
-- New Run tab taking the menu over while the cursor stays on the tab strip):
-- not re-read. Landing anywhere else still announces.
local strip, other = {}, {}
local top_on, top_ref = false, strip
D.register({
    id = "top",
    handler = function() return top_on and "active" or "inactive" end,
    build = function(self, b)
        b:capture_input()
        b:add_item(Id.referenced(top_ref, "first"), { label = function(ctx)
            ctx.message:fragment(Message.raw("top first"))
        end })
    end,
})
active = false
D.tick(nil)
active = true
ov.build = function(self, b)
    b:capture_input()
    b:add_item(Id.referenced(strip, "s"), { label = function(ctx)
        ctx.message:fragment(Message.raw("strip"))
    end })
end
res = D.tick(nil)
check(res and res.message == "strip", "base overlay speaks the strip", res and res.message)
top_on = true
res = D.tick(nil)
check(res == nil, "handoff onto the same element is quiet", res and res.message)
res = D.tick(nil)
check(res == nil, "and stays quiet", res and res.message)
top_on = false
D.tick(nil)
top_ref = other
top_on = true
res = D.tick(nil)
check(res and res.message == "top first", "handoff onto a different element announces", res and res.message)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
