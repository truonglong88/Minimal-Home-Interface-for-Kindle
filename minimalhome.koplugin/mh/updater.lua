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

--- Ask GitHub what the newest build is. Quiet: no message either way.
--- every = seconds since the last check before asking again. done(found) runs after a check.
function U.check(every, done)
    if U.busy then return end
    local W = require("mh/wifi")
    if not W.isConnected() then return end
    local now = os.time()
    local last = tonumber(Prefs.get("update_checked_at")) or 0
    if now - last < (every or U.HOME_EVERY) and now >= last then return end
    Prefs.set("update_checked_at", now)
    U.busy = true
    local chunks = {}
    local ok, err = get(U.manifestUrl(), function()
        chunks = {}
        return require("ltn12").sink.table(chunks)
    end, 4, 10)
    U.busy = false
    if not ok then
        logger.info("MinimalHome: update check failed:", err)
        return
    end
    local m = decodeJSON(table.concat(chunks))
    if not validManifest(m) then
        logger.warn("MinimalHome: update check: bad latest.json")
        return
    end
    m.channel = U.channel()
    local before = U.available()
    if U.newer(m.version, U.version()) then
        Prefs.set("update_found", { version = m.version, file = m.file, sha256 = m.sha256:lower(),
            size = tonumber(m.size), channel = m.channel })
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

local function download(m, progress)
    local DataStorage = require("datastorage")
    local util = require("util")
    local dir = DataStorage:getDataDir() .. "/cache"
    util.makePath(dir)
    local path = dir .. "/minimalhome-update.zip"
    local url = "https://github.com/" .. U.REPO .. "/releases/download/"
        .. (m.channel == "dev" and "dev" or ("v" .. m.version)) .. "/" .. m.file
    local size = tonumber(m.size)
    local file, got, shown = nil, 0, -1
    local ok, err = get(url, function()
        if file then file:close() end
        file = io.open(path, "wb")
        got, shown = 0, -1
        return function(chunk)
            if not file then return nil, "cannot write" end
            if not chunk then return 1 end
            got = got + #chunk
            if progress and size and size > 0 then
                local pct = math.min(99, math.floor(got * 100 / size))
                if pct >= shown + 5 then shown = pct; progress(pct) end
            end
            return file:write(chunk) and 1 or nil
        end
    end, 15, 180)
    if file then file:close() end
    if not ok then os.remove(path); return nil, "download: " .. tostring(err) end
    if size and got ~= size then os.remove(path); return nil, "size " .. got .. " ≠ " .. size end
    local sum = sha256File(path)
    if sum ~= m.sha256 then os.remove(path); return nil, "checksum mismatch" end
    return path
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

--- Download, check and put the new build in place. progress(pct) while downloading.
--- True on success (KOReader must then restart); nil and a reason otherwise.
function U.install(m, progress)
    local ffiUtil = require("ffi/util")
    local lfs = require("libs/libkoreader-lfs")
    local here = Theme.plugin_dir
    local fresh, old = here .. ".update", here .. ".old"
    local zip, err = download(m, progress)
    if not zip then return nil, err end
    local ok
    ok, err = unpack(zip, fresh)
    os.remove(zip)
    if not ok then return nil, err end
    local meta = readMeta(fresh)
    if not meta or meta.version ~= m.version then
        ffiUtil.purgeDir(fresh)
        return nil, "the new build says it is " .. tostring(meta and meta.version)
    end
    if lfs.attributes(old, "mode") then ffiUtil.purgeDir(old) end
    ok, err = os.rename(here, old)
    if not ok then ffiUtil.purgeDir(fresh); return nil, "rename: " .. tostring(err) end
    ok, err = os.rename(fresh, here)
    if not ok then
        os.rename(old, here)
        ffiUtil.purgeDir(fresh)
        return nil, "rename: " .. tostring(err)
    end
    ffiUtil.purgeDir(old)
    Prefs.set("update_found", nil)
    Prefs.set("update_from", U.version())
    Prefs.set("update_to", m.version)
    G_reader_settings:flush()
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
