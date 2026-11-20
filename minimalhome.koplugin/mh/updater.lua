--[[--
Updates over Wi-Fi, from the plugin's GitHub releases.

Each build knows its channel (build.lua, written by tools/package.sh):
  dev    → the rolling "dev" pre-release, rebuilt on every push to the dev branch
  stable → the latest official release

A release carries the plugin zip and latest.json:
  { "version": "0.1.37", "file": "minimalhome-0.1.37.zip",
    "sha256": "…", "size": 2512345, "channel": "dev" }

We only look when Wi-Fi is already connected and Home or Settings opens: at
most once an hour from Home, at most once a minute from Settings. Nothing runs
in the background. Updating downloads the zip, checks its size and SHA-256,
unpacks it next to the plugin, swaps the folders and restarts KOReader. If
anything fails, the old plugin stays as it was.
--]]

local UIManager = require("ui/uimanager")
local logger = require("logger")

local Prefs = require("mh/data/prefs")
local Theme = require("mh/theme")

local U = {}

U.REPO = "truonglong88/Minimal-Home-Interface-for-Kindle"
U.HOME_EVERY = 3600   -- seconds between checks when Home opens
U.SETTINGS_EVERY = 60 -- … when Settings opens
U.FOLDER = "minimalhome.koplugin"

-- Version and channel ---------------------------------------------------------------------

local function readMeta(dir)
    local ok, meta = pcall(dofile, dir .. "/_meta.lua")
    return ok and type(meta) == "table" and meta or nil
end

function U.version()
    local meta = readMeta(Theme.plugin_dir)
    return meta and meta.version or "0.0.0"
end

function U.channel()
    local ok, build = pcall(dofile, Theme.plugin_dir .. "/build.lua")
    if ok and type(build) == "table" and build.channel == "dev" then return "dev" end
    return "stable"
end

function U.channelName()
    return U.channel() == "dev" and "Dev" or "Stable"
end

function U.manifestUrl(channel)
    local base = "https://github.com/" .. U.REPO .. "/releases"
    if (channel or U.channel()) == "dev" then return base .. "/download/dev/latest.json" end
    return base .. "/latest/download/latest.json"
end

--- "0.1.37" > "0.1.36"? Compares number by number.
function U.newer(a, b)
    local function parts(v)
        local t = {}
        for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

--- The update found by the last check, if it is still newer than what runs now.
function U.available()
    local m = Prefs.get("update_found")
    if type(m) == "table" and m.channel == U.channel() and U.newer(m.version, U.version()) then return m end
    return nil
end

-- HTTP -------------------------------------------------------------------------------------

--- GET with redirects followed by hand (GitHub sends release files to another host).
--- make_sink() is called once per hop, so a redirect page never ends up in the result.
local function get(url, make_sink, block, total)
    local socket = require("socket")
    local socket_url = require("socket.url")
    local socketutil = require("socketutil")
    for _ = 1, 6 do
        local client = url:match("^https:") and require("ssl.https") or require("socket.http")
        socketutil:set_timeout(block, total)
        local ok, code, headers, status = pcall(function()
            return socket.skip(1, client.request{ url = url, method = "GET", sink = make_sink(), redirect = false,
                headers = { ["User-Agent"] = socketutil.USER_AGENT } })
        end)
        socketutil:reset_timeout()
        if not ok then return nil, tostring(code) end
        logger.info("MinimalHome: update GET", (url:match("^https?://([^/]+)")), "→", code)
        local loc = headers and (headers.location or headers.Location)
        if (code == 301 or code == 302 or code == 303 or code == 307 or code == 308) and loc then
            url = socket_url.absolute(url, loc)
        else
            if code ~= 200 then return nil, tostring(status or code) end
            return true
        end
    end
    return nil, "too many redirects"
end

local function decodeJSON(text)
    local ok, t = pcall(function() return require("rapidjson").decode(text) end)
    if ok and type(t) == "table" then return t end
    ok, t = pcall(function() return require("json").decode(text) end)
    if ok and type(t) == "table" then return t end
    return nil
end

local function validManifest(m)
    return type(m) == "table" and type(m.version) == "string" and m.version:match("^%d+%.%d+%.%d+$")
        and type(m.file) == "string" and m.file:match("^[%w%._%-]+%.zip$")
        and type(m.sha256) == "string" and #m.sha256 == 64
end

-- Checking -----------------------------------------------------------------------------------

--- latest.json as it is on GitHub right now, or nil and a reason. Blocking.
--- Kindles are slow at HTTPS handshakes: be patient, and try twice.
function U.fetchManifest()
    local chunks, ok, err
    for _ = 1, 2 do
        ok, err = get(U.manifestUrl(), function()
            chunks = {}
            return require("ltn12").sink.table(chunks)
        end, 15, 30)
        if ok then break end
    end
    if not ok then return nil, err end
    local m = decodeJSON(table.concat(chunks))
    if not validManifest(m) then return nil, "bad latest.json" end
    return { version = m.version, file = m.file, sha256 = m.sha256:lower(), size = tonumber(m.size),
        channel = U.channel() }
end

--- Ask GitHub what the newest build is. Quiet: no message either way.
--- every = seconds since the last check before asking again. done(found) runs after a check.
function U.check(every, done)
    if U.busy then return end
    local W = require("mh/wifi")
    if not W.isConnected() then return end
    local now = os.time()
    local last = tonumber(Prefs.get("update_checked_at")) or 0
    if now - last < (every or U.HOME_EVERY) and now >= last then return end
    U.busy = true
    local m, err = U.fetchManifest()
    U.busy = false
    if not m then
        -- not remembered as checked: the next Home / Settings asks again
        logger.info("MinimalHome: update check failed:", err)
        return
    end
    Prefs.set("update_checked_at", now)
    local before = U.available()
    if U.newer(m.version, U.version()) then
        Prefs.set("update_found", m)
    else
        Prefs.set("update_found", nil)
    end
    local found = U.available()
    logger.info("MinimalHome: update check:", found and ("found " .. found.version) or "up to date")
    if done and ((found and found.version) ~= (before and before.version)) then done(found) end
end

--- Check a moment after a screen has been painted, so the screen never waits on the network.
function U.checkSoon(every, done)
    UIManager:scheduleIn(1, function()
        local ok, err = pcall(U.check, every, done)
        if not ok then
            U.busy = false
            logger.warn("MinimalHome: update check:", err)
        end
    end)
end

-- Installing ---------------------------------------------------------------------------------
--
-- Downloading, checking and unpacking run in a child process, so the screen stays
-- usable meanwhile (scroll, Back, swipe Home). Only the final swap of the two
-- folders happens here, and then KOReader restarts.

U.TIMEOUT = 300 -- seconds for the whole download

local function paths()
    local DataStorage = require("datastorage")
    local here = Theme.plugin_dir
    return {
        zip = DataStorage:getDataDir() .. "/cache/minimalhome-update.zip",
        here = here, fresh = here .. ".update", old = here .. ".old",
    }
end

local function sha256File(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local append = require("ffi/sha2").sha256()
    while true do
        local block = f:read(65536)
        if not block then break end
        append(block)
    end
    f:close()
    return append():lower()
end

local function download(m, path)
    local util = require("util")
    util.makePath(path:match("(.*)/"))
    local url = "https://github.com/" .. U.REPO .. "/releases/download/"
        .. (m.channel == "dev" and "dev" or ("v" .. m.version)) .. "/" .. m.file
    local size = tonumber(m.size)
    local file, got = nil, 0
    local started = os.time()
    local ok, err = get(url, function()
        if file then file:close() end
        file = io.open(path, "wb")
        got = 0
        return function(chunk)
            if not file then return nil, "cannot write" end
            if not chunk then return 1 end
            if os.time() - started > U.TIMEOUT then return nil, "took too long" end
            got = got + #chunk
            if not file:write(chunk) then return nil, "disk full?" end
            file:flush() -- the screen shows progress from the file's size
            return 1
        end
    end, 20, U.TIMEOUT)
    if file then file:close() end
    if not ok then return nil, "download: " .. tostring(err) end
    if size and got ~= size then return nil, "size " .. got .. " ≠ " .. size end
    if sha256File(path) ~= m.sha256 then return nil, "checksum mismatch" end
    return true
end

--- Unpack the zip (its root is minimalhome.koplugin/) into a folder next to the plugin.
local function unpack(zip, dest)
    local ffiUtil = require("ffi/util")
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(dest, "mode") then ffiUtil.purgeDir(dest) end
    local Archiver = require("ffi/archiver")
    local arc = Archiver.Reader:new()
    if not arc:open(zip) then return nil, "cannot open zip" end
    local prefix = U.FOLDER .. "/"
    local count, err = 0, nil
    for entry in arc:iterate() do
        local p = entry.path or ""
        if p:sub(1, #prefix) ~= prefix or p:find("%.%.") then
            err = "unexpected file in zip: " .. p
            break
        end
        local rel = p:sub(#prefix + 1)
        if rel ~= "" and entry.mode == "file" then
            if not arc:extractToPath(p, dest .. "/" .. rel) then
                err = arc.err or ("cannot unpack " .. rel)
                break
            end
            count = count + 1
        end
    end
    arc:close()
    if not err and count == 0 then err = "empty zip" end
    if err then
        if lfs.attributes(dest, "mode") then ffiUtil.purgeDir(dest) end
        return nil, err
    end
    return true
end

--- Download, check and unpack next to the plugin (blocking: runs in the child).
function U.prepare(m)
    local p = paths()
    os.remove(p.zip)
    -- the build found earlier may have been replaced on GitHub since (Dev builds come
    -- often): take whatever latest.json says now, if it is still newer than this one
    local now = U.fetchManifest()
    if now and U.newer(now.version, U.version()) then m = now end
    local ok, err = download(m, p.zip)
    if ok then ok, err = unpack(p.zip, p.fresh) end
    os.remove(p.zip)
    if not ok then return nil, err end
    local meta = readMeta(p.fresh)
    if not meta or meta.version ~= m.version then
        require("ffi/util").purgeDir(p.fresh)
        return nil, "the new build says it is " .. tostring(meta and meta.version)
    end
    return true, m
end

--- Put the unpacked build in place of the running one. KOReader must restart after.
function U.swap(m)
    local ffiUtil = require("ffi/util")
    local lfs = require("libs/libkoreader-lfs")
    local p = paths()
    if not lfs.attributes(p.fresh .. "/_meta.lua", "mode") then return nil, "nothing unpacked" end
    if lfs.attributes(p.old, "mode") then ffiUtil.purgeDir(p.old) end
    local ok, err = os.rename(p.here, p.old)
    if not ok then ffiUtil.purgeDir(p.fresh); return nil, "rename: " .. tostring(err) end
    ok, err = os.rename(p.fresh, p.here)
    if not ok then
        os.rename(p.old, p.here)
        ffiUtil.purgeDir(p.fresh)
        return nil, "rename: " .. tostring(err)
    end
    ffiUtil.purgeDir(p.old)
    Prefs.set("update_found", nil)
    Prefs.set("update_to", m.version)
    G_reader_settings:flush()
    return true
end

--- Blocking install (download + swap), for tests and tools.
function U.install(m)
    local ok, res = U.prepare(m)
    if not ok then return nil, res end
    return U.swap(res)
end

-- U.job: the download under way { m, pid, fd, pct }; U.ready: unpacked, waiting to be swapped in.
U.listeners = {}

local function notify()
    for _, fn in pairs(U.listeners) do pcall(fn) end
end

local function readerOpen()
    local ok, r = pcall(function() return require("apps/reader/readerui").instance end)
    return ok and r ~= nil
end

--- Swap in the unpacked build and restart, unless a book is open (then on the way Home).
function U.finish()
    local m = U.ready
    if not m or readerOpen() then return false end
    U.ready = nil
    local ok, err = U.swap(m)
    if not ok then
        logger.warn("MinimalHome: update failed:", err)
        require("mh/ui/snackbar").show("Couldn’t update · still on " .. U.version(), 4)
        notify()
        return false
    end
    local fm = package.loaded["apps/filemanager/filemanager"]
    require("mh/device").restartKOReader(fm and fm.instance)
    return true
end

--- Start downloading in the background. Listeners (U.listeners) hear about progress and the end.
function U.start(m)
    if U.job or U.ready then return true end
    local ffiutil = require("ffi/util")
    local lfs = require("libs/libkoreader-lfs")
    local zip = paths().zip
    os.remove(zip)
    local pid, fd = ffiutil.runInSubProcess(function(_, child_fd)
        local ok, res, got = pcall(U.prepare, m)
        local msg = (ok and res) and ("ok " .. got.version) or ("error: " .. tostring(ok and got or res))
        ffiutil.writeToFD(child_fd, msg, true)
    end, true)
    if not pid then return nil, "could not start the download" end
    local job = { m = m, pid = pid, fd = fd, pct = 0, started = os.time() }
    U.job = job
    notify()
    local function poll()
        if U.job ~= job then return end
        local done = ffiutil.isSubProcessDone(pid)
        local waiting = fd and ffiutil.getNonBlockingReadSize(fd) ~= 0
        if done or waiting then
            local msg = fd and ffiutil.readAllFromFD(fd) or ""
            if not done then ffiutil.isSubProcessDone(pid, true) end
            U.job = nil
            local got = msg:match("^ok (%S+)$")
            if got then
                local ready = {}
                for k, v in pairs(m) do ready[k] = v end
                ready.version = got -- a newer build may have replaced the one we started with
                U.ready = ready
                if not U.finish() then
                    -- reading: it goes in on the way back to Home
                    if U.ready then require("mh/ui/snackbar").show("Update ready · it installs when you go Home", 4) end
                    notify()
                end
            else
                logger.warn("MinimalHome: update failed:", msg)
                require("mh/ui/snackbar").show("Couldn’t update · still on " .. U.version(), 4)
                notify()
            end
            return
        end
        if os.time() - job.started > U.TIMEOUT + 60 then
            ffiutil.terminateSubProcess(pid)
            if fd then ffiutil.readAllFromFD(fd) end
            U.job = nil
            logger.warn("MinimalHome: update failed: timed out")
            require("mh/ui/snackbar").show("Couldn’t update · still on " .. U.version(), 4)
            notify()
            return
        end
        local size = lfs.attributes(zip, "size") or 0
        local total = tonumber(m.size) or 0
        local pct = total > 0 and math.min(99, math.floor(size * 100 / total)) or 0
        if pct >= job.pct + 5 then -- every 5 %: e-ink refreshes are not free
            job.pct = pct
            notify()
        end
        UIManager:scheduleIn(0.5, poll)
    end
    UIManager:scheduleIn(0.5, poll)
    return true
end

--- After the restart: "Updated to 0.1.37", once.
function U.announce()
    local to = Prefs.get("update_to")
    if not to then return end
    Prefs.set("update_to", nil)
    Prefs.set("update_from", nil)
    if to == U.version() then
        UIManager:scheduleIn(1.5, function() require("mh/ui/snackbar").show("Updated to " .. to) end)
    end
end

return U
