-- dev/routes.lua — the dev server's inspection/driving routes. Part of the
-- GENERATION (reloads with the mod), so edit freely and POST /reload.
--   POST /eval        body = Lua; an expression's value is returned, or run a
--                     chunk and see what it print()s. REPL globals persist
--                     across calls (and reloads); BA = the live Blindfold
--                     table, H = the host, dump(v, depth) pretty-prints.
--   GET  /state       stage / state / menu / active overlay / generation
--   GET  /overlay     the active owned overlay: nodes, labels, cursor, links
--                     (the F8 dump)
--   POST /key         body = a key as LÖVE names it ("down", "return",
--                     "ctrl+s"): pressed and released through the game's
--                     Controller, exactly like the keyboard
--   GET  /screenshot  captures the next frame; returns the PNG's path
local require = ...

local R = {}

local function dump(v, depth, seen, indent)
    depth = depth == nil and 2 or depth
    indent = indent or ""
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    seen = seen or {}
    if seen[v] then return "<cycle " .. tostring(v) .. ">" end
    if depth <= 0 then return tostring(v) end
    seen[v] = true
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "number" or ta == "string" then return a < b end
        return tostring(a) < tostring(b)
    end)
    local out, shown = {}, 0
    for _, k in ipairs(keys) do
        shown = shown + 1
        if shown > 60 then
            out[#out + 1] = indent .. "  ... (" .. (#keys - 60) .. " more)"
            break
        end
        out[#out + 1] = indent .. "  [" .. (type(k) == "string" and k or tostring(k)) .. "] = "
            .. dump(v[k], depth - 1, seen, indent .. "  ")
    end
    seen[v] = nil
    if not out[1] then return "{}" end
    return "{\n" .. table.concat(out, "\n") .. "\n" .. indent .. "}"
end

local function repl_env()
    local H = _G.BlindfoldHost
    H.repl = H.repl or setmetatable({}, { __index = _G })
    return H.repl
end

local function eval(src)
    if type(src) ~= "string" or src:match("^%s*$") then
        return "[empty] POST Lua source as the request body\n"
    end
    local out = {}
    local env = repl_env()
    env.BA, env.H, env.dump = _G.Blindfold, _G.BlindfoldHost, dump
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            parts[i] = type(v) == "string" and v or dump(v)
        end
        out[#out + 1] = table.concat(parts, "\t")
    end
    local chunk = load("return " .. src, "=eval")
    if not chunk then
        local err
        chunk, err = load(src, "=eval")
        if not chunk then return "[compile error] " .. tostring(err) .. "\n" end
    end
    setfenv(chunk, env)
    local res = { pcall(chunk) }
    if not res[1] then
        out[#out + 1] = "[error] " .. tostring(res[2])
    else
        for i = 2, table.maxn(res) do out[#out + 1] = dump(res[i]) end
    end
    return table.concat(out, "\n") .. "\n"
end

local function name_of(tbl, value)
    for k, v in pairs(tbl or {}) do if v == value then return k end end
    return tostring(value)
end

local function state()
    local ba = _G.Blindfold
    local D = ba and ba.overlays
    local lines = {
        "generation: " .. tostring(_G.BlindfoldHost and _G.BlindfoldHost.gen),
        "stage: " .. name_of(G and G.STAGES, G and G.STAGE),
        "state: " .. name_of(G and G.STATES, G and G.STATE),
        "overlay menu: " .. tostring(G and G.OVERLAY_MENU ~= nil),
        "owned overlay: " .. tostring(D and D.active_last),
        "steamodded: " .. tostring(type(SMODS) == "table"),
    }
    if ba and ba.boot_error then lines[#lines + 1] = "boot error: " .. tostring(ba.boot_error) end
    return table.concat(lines, "\n") .. "\n"
end

local function overlay()
    local D = _G.Blindfold and _G.Blindfold.overlays
    if not D then return "no dispatcher\n" end
    local ok, desc = pcall(D.describe)
    return tostring(ok and desc or ("[error] " .. tostring(desc))) .. "\n"
end

local MOD_KEYS = { ctrl = "lctrl", shift = "lshift", alt = "lalt" }

local function key(body)
    local ctrl = G and G.CONTROLLER
    if not ctrl then return "[not ready] no controller\n" end
    local spec = (body or ""):match("^%s*(.-)%s*$")
    if spec == "" then return "[empty] POST a key name, e.g. down, return, ctrl+s\n" end
    local held, k = {}, spec
    for m in spec:gmatch("(%a+)%+") do held[#held + 1] = MOD_KEYS[m:lower()] or m end
    k = spec:match("([^+]+)$")
    -- Modifiers are read from love.keyboard.isDown (the real keyboard), so
    -- report the held ones as down for the duration of the press.
    local down = {}
    for _, m in ipairs(held) do
        down[m] = true
        down[(m:gsub("^l", "r"))] = false   -- only the left variant is "held"
    end
    local kb = love.keyboard
    local real_isDown = kb.isDown
    kb.isDown = function(...)
        for i = 1, select("#", ...) do
            if down[select(i, ...)] then return true end
        end
        return real_isDown(...)
    end
    local ok, err = pcall(function()
        for _, m in ipairs(held) do ctrl:key_press(m) end
        ctrl:key_press(k)
        ctrl:key_release(k)
        for i = #held, 1, -1 do ctrl:key_release(held[i]) end
    end)
    kb.isDown = real_isDown
    if not ok then return "[error] " .. tostring(err) .. "\n" end
    return "pressed " .. spec .. "\n"
end

local function screenshot()
    local name = "blindfold_shot.png"
    pcall(love.filesystem.remove, name)
    love.graphics.captureScreenshot(name)
    return love.filesystem.getSaveDirectory() .. "/" .. name
        .. "\n(written at the end of this frame)\n"
end

R.routes = {
    ["/eval"] = function(method, body) return eval(body) end,
    ["/state"] = function() return state() end,
    ["/overlay"] = function() return overlay() end,
    ["/key"] = function(method, body) return key(body) end,
    ["/screenshot"] = function() return screenshot() end,
}

return R
