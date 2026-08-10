-- Harness: dispatcher refresh_identity — a same-screen content rebuild keeps
-- the cursor but re-announces the focused node (the keybinds screen after a
-- rebind).
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

-- A mirror-shaped overlay: stable screen identity (tag), per-build instance.
local instance = "box1"
local screen = "tag:test"
local ov = {
    id = "t",
    handler = function() return "active" end,
    sub_identity = function() return screen end,
    refresh_identity = function() return instance end,
    build = function(self, b)
        b:capture_input()
        for i = 1, 3 do
            b:add_item(Id.structural("i" .. i), { label = function(ctx)
                ctx.message:fragment(Message.raw("item " .. i .. " of " .. instance))
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

-- Fresh open speaks the start node; a move speaks the destination.
local res = D.tick(nil)
check(res and res.message == "item 1 of box1", "fresh open speaks the start", res and res.message)
res = D.tick({ kind = "move", dir = "down" })
check(res and res.message == "item 2 of box1", "move speaks the destination", res and res.message)

-- Steady state: nothing to say.
res = D.tick(nil)
check(res == nil, "steady state stays silent", res and res.message)

-- The rebuild: new instance, same screen. Cursor stays on row 2, and the row
-- (with its fresh text) is spoken again.
instance = "box2"
res = D.tick(nil)
check(res and res.message == "item 2 of box2", "rebuild re-announces the kept cursor", res and res.message)
res = D.tick(nil)
check(res == nil, "silent again after the re-announce", res and res.message)

-- A screen-identity change is still a full fresh open (reset to start).
screen = "tag:other"
instance = "box3"
res = D.tick(nil)
check(res and res.message == "item 1 of box3", "new screen identity resets to the start", res and res.message)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
