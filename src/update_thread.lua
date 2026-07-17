-- update_thread.lua — RUNS ON A love.thread (its own Lua state; only
-- love.thread is preloaded there). Fetches the two GitHub endpoints the
-- update check needs and pushes the raw response bodies back on the channel
-- (releases first, then commits; empty string = request failed). Network I/O
-- happens here so the game thread never blocks.
--
-- LOVE ships no TLS, so HTTPS goes through Windows' own WinINet via LuaJIT
-- FFI (the thread state has its own ffi, no cdef clash with the main state).
local chan_name, releases_url, commits_url = ...
local channel = love.thread.getChannel(chan_name)

local ok, err = pcall(function()
    local ffi = require("ffi")
    if ffi.os ~= "Windows" then
        error("Update checks via WinINet are only supported on Windows")
    end
    ffi.cdef([[
        typedef void* HINTERNET;
        HINTERNET InternetOpenA(const char* agent, unsigned long access,
                                const char* proxy, const char* bypass, unsigned long flags);
        HINTERNET InternetOpenUrlA(HINTERNET h, const char* url, const char* headers,
                                   unsigned long headers_len, unsigned long flags, uintptr_t ctx);
        int InternetReadFile(HINTERNET h, void* buf, unsigned long to_read, unsigned long* read);
        int InternetCloseHandle(HINTERNET h);
    ]])
    local wininet = ffi.load("wininet")
    -- SECURE | NO_CACHE_WRITE | RELOAD: always hit the network, over TLS.
    local FLAGS = 0x00800000 + 0x04000000 + 0x80000000

    local net = wininet.InternetOpenA("Blindfold", 0, nil, nil, 0)
    assert(net ~= nil, "InternetOpenA failed")

    local function get(url)
        local h = wininet.InternetOpenUrlA(net, url, nil, 0, FLAGS, 0)
        if h == nil then return "" end
        local parts = {}
        local buf = ffi.new("char[8192]")
        local got = ffi.new("unsigned long[1]")
        while wininet.InternetReadFile(h, buf, 8192, got) ~= 0 and got[0] > 0 do
            parts[#parts + 1] = ffi.string(buf, got[0])
        end
        wininet.InternetCloseHandle(h)
        return table.concat(parts)
    end

    local releases = get(releases_url)
    local commits = get(commits_url)
    wininet.InternetCloseHandle(net)
    channel:push(releases)
    channel:push(commits)
end)
if not ok then
    channel:push("")
    channel:push("")
end
