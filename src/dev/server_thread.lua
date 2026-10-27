-- dev/server_thread.lua — RUNS ON A love.thread (its own Lua state). The dev
-- server's socket side: a loopback HTTP/1.1 listener (LuaSocket, built into
-- LÖVE) that hands each request to the main thread and relays its answer, so
-- socket I/O never blocks the game. GET /health answers here directly, which
-- also tells "server up, main thread frozen" apart from "server down".
--
-- Protocol with dev/server.lua: requests go out on `req_chan` as one string
-- "<id>\n<method>\n<path>\n<body>"; the main thread pushes the response text
-- on "blindfold_dev_resp_<id>".
local req_chan, port = ...
require("love.timer")
local socket = require("socket")

local reqs = love.thread.getChannel(req_chan)
local status = love.thread.getChannel("blindfold_dev_status")

local server, err = socket.bind("127.0.0.1", port)
if not server then
    status:push("bind failed on " .. tostring(port) .. ": " .. tostring(err))
    return
end
status:push("listening on 127.0.0.1:" .. tostring(port))

local MAIN_TIMEOUT = 60   -- seconds to wait for the main thread (a reload can take a moment)

local function reply(client, code, body)
    body = body or ""
    client:send(string.format(
        "HTTP/1.1 %s\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n",
        code, #body) .. body)
end

local function serve(client)
    client:settimeout(5)
    local line = client:receive("*l")
    if not line then return end
    local method, path = line:match("^(%u+)%s+(%S+)")
    if not method then return reply(client, "400 Bad Request", "bad request line\n") end
    local length = 0
    while true do
        local h = client:receive("*l")
        if not h or h == "" then break end
        local n = h:match("^[Cc]ontent%-[Ll]ength:%s*(%d+)")
        if n then length = tonumber(n) end
    end
    local body = ""
    if length > 0 then body = client:receive(length) or "" end

    if path == "/health" then return reply(client, "200 OK", "ok\n") end

    local id = tostring(love.timer.getTime()) .. ":" .. tostring(math.random(1, 1e9))
    local resp = love.thread.getChannel("blindfold_dev_resp_" .. id)
    reqs:push(id .. "\n" .. method .. "\n" .. path .. "\n" .. body)
    local out = resp:demand(MAIN_TIMEOUT)
    if out == nil then
        out = "[timeout] the main thread did not answer within " .. MAIN_TIMEOUT
            .. "s (frozen, loading, or not pumping?)\n"
    end
    reply(client, "200 OK", out)
end

math.randomseed(os.time())
while true do
    local client = server:accept()
    if client then
        pcall(serve, client)
        pcall(client.close, client)
    end
end
