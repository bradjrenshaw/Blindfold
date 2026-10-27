-- dev/server.lua — the dev server's main-thread side (HOST: started once,
-- survives hot reloads; changes here need a game restart, so keep it small).
-- A loopback HTTP server for a driver (Claude, curl) to inspect and drive the
-- live mod. Off unless enabled: env BLINDFOLD_DEV=1, or the marker file
-- blindfold_dev.enable in the save directory (%APPDATA%\Balatro), which
-- scripts\run_game.ps1 drops — a Steam launch doesn't pass our env through.
--
-- Host routes (here):
--   GET  /health            liveness (answered on the socket thread itself)
--   POST /reload            hot reload: re-run core.lua + the module tree
--   GET  /speech?since=N    lines spoken since cursor N ("cursor: M" first)
--   GET  /module            generation + hook count
-- Everything else comes from the current generation's dev/routes.lua
-- (BA.dev_routes), so the inspection routes reload with the rest of the mod.
--
-- Requests are handled in pump(), once per frame on the main thread.
local S = { enabled = false, port = nil }

local DEFAULT_PORT = 8772     -- wotr-access 8771, Tangledeep 8770
local REQ_CHAN = "blindfold_dev_req"
local SPEECH_CAP = 500

local lines, base = {}, 0     -- speech ring buffer; base = index of lines[1]

local function tap(text)
    lines[#lines + 1] = text
    if #lines > SPEECH_CAP then table.remove(lines, 1); base = base + 1 end
end

local function speech_since(since)
    since = math.max(tonumber(since) or 0, base)
    local out, last = {}, base + #lines
    for i = since, last - 1 do out[#out + 1] = i .. ": " .. lines[i - base + 1] end
    return "cursor: " .. last .. "\n" .. table.concat(out, "\n") .. (out[1] and "\n" or "")
end

function S.gate()
    if os.getenv("BLINDFOLD_DEV") == "1" then return "env" end
    local ok, info = pcall(love.filesystem.getInfo, "blindfold_dev.enable")
    if ok and info then return "marker" end
    return nil
end

-- Start the socket thread and the speech tap. host: the BlindfoldHost table;
-- speech_mod: the speech module (its observer feeds /speech).
function S.start(host, speech_mod, log)
    if S.enabled then return true end
    local how = S.gate()
    if not how then return false end
    local code = host.read and host.read("dev/server_thread.lua")
    if not code then log("dev server: cannot read dev/server_thread.lua"); return false end
    S.port = tonumber(os.getenv("BLINDFOLD_DEV_PORT") or "") or DEFAULT_PORT
    local ok, err = pcall(function()
        love.thread.newThread(code):start(REQ_CHAN, S.port)
    end)
    if not ok then log("dev server: thread failed: " .. tostring(err)); return false end
    S.host, S.log = host, log
    speech_mod.observer = tap
    S.enabled = true
    log("dev server starting on 127.0.0.1:" .. S.port .. " (gate: " .. how .. ")")
    return true
end

local function parse_query(path)
    local route, q = path:match("^([^?]*)%??(.*)$")
    local query = {}
    for k, v in (q or ""):gmatch("([^&=]+)=?([^&]*)") do query[k] = v end
    return route, query
end

local function handle(method, path, body)
    local route, query = parse_query(path)
    if route == "/reload" and method == "POST" then
        return S.host.reload()
    end
    if route == "/speech" then return speech_since(query.since) end
    if route == "/module" then
        local n = 0
        for _, byk in pairs(S.host.hooks) do for _ in pairs(byk) do n = n + 1 end end
        return "generation " .. S.host.gen .. ", " .. n .. " hooked functions\n"
    end
    local ba = _G.Blindfold
    local routes = ba and ba.dev_routes
    local fn = routes and routes[route]
    if fn then return fn(method, body, query) end
    local names = {}
    for k in pairs(routes or {}) do names[#names + 1] = k end
    table.sort(names)
    return "[404] " .. method .. " " .. route .. "\nroutes: /health /reload /speech /module "
        .. table.concat(names, " ") .. "\n"
end

-- Once per frame (main thread): status lines, then every queued request.
function S.pump()
    if not S.enabled then return end
    local status = love.thread.getChannel("blindfold_dev_status"):pop()
    if status then S.log("dev server: " .. tostring(status)) end
    local reqs = love.thread.getChannel(REQ_CHAN)
    while true do
        local msg = reqs:pop()
        if not msg then break end
        local id, method, path, body = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n(.*)$")
        local out
        if id then
            local ok, res = pcall(handle, method, path, body)
            out = ok and tostring(res or "") or ("[error] " .. tostring(res) .. "\n")
            love.thread.getChannel("blindfold_dev_resp_" .. id):push(out)
        end
    end
end

return S
