--[[--
Wi-Fi for the Wi-Fi popup: on / off, the networks nearby, connecting.

Built on KOReader's NetworkMgr (its Kindle backend talks to the Kindle's own
Wi-Fi service), without KOReader's dialogs: scanning, "Connecting…" and the
network list are ours. On a Kindle a connection is asynchronous, so after
asking for one we watch for it and report the result once.
--]]

local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local W = {}

W.CONNECT_TIMEOUT = 30 -- seconds
W.POLL = 0.5

-- networks whose saved password just failed: ask for it again next time
W.failed = {}

local function NM() return require("ui/network/manager") end

local function try(what, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok then
        logger.warn("MinimalHome: wifi " .. what .. ":", a)
        return nil
    end
    return a, b
end

function W.isOn()
    return try("state", function() return NM():isWifiOn() end) == true
end

function W.isConnected()
    return try("connected", function() return NM():isConnected() end) == true
end

--- Name of the network we are connected to, or nil.
function W.current()
    if not W.isConnected() then return nil end
    local nw = try("current", function() return NM():getCurrentNetwork() end)
    return nw and nw.ssid or nil
end

function W.locked(net)
    local f = net and net.flags or ""
    return f:find("WPA") ~= nil or f:find("WEP") ~= nil or f:find("PSK") ~= nil or f:find("SAE") ~= nil
end

--- 1–3 arcs from KOReader's signal quality (0–100).
function W.level(net)
    local q = net and net.signal_quality or 0
    if q >= 60 then return 3 elseif q >= 30 then return 2 end
    return 1
end

--- Networks nearby, strongest first, without duplicates or hidden ones. Blocks for a few seconds.
function W.scan()
    local list, err = try("scan", function() return NM():getNetworkList() end)
    if not list then return nil, err end
    local seen, out = {}, {}
    table.sort(list, function(a, b) return (a.signal_quality or 0) > (b.signal_quality or 0) end)
    for _, n in ipairs(list) do
        if n.ssid and n.ssid ~= "" and not seen[n.ssid] then
            seen[n.ssid] = true
            out[#out + 1] = n
        end
    end
    return out
end

--- A network we can join without asking (open, or its password is saved and worked).
function W.known(net)
    if not net then return false end
    if W.failed[net.ssid] then return false end
    return not W.locked(net) or (net.password ~= nil and net.password ~= "")
end

-- Kindle: switch the radio with the Kindle's own service (what KOReader does),
-- but without KOReader's scan dialog afterwards.
local function kindleRadio(on)
    local ok, lipc = pcall(require, "liblipclua")
    local h = ok and lipc.init("com.github.koreader.minimalhome")
    if not h then return false end
    local v = on and 1 or 0
    if on then
        h:set_int_property("com.lab126.cmd", "wirelessEnable", v)
        h:set_int_property("com.lab126.wifid", "enable", v)
    else
        h:set_int_property("com.lab126.wifid", "enable", v)
        h:set_int_property("com.lab126.cmd", "wirelessEnable", v)
    end
    h:close()
    return true
end

local function markConnected(ssid)
    local nm = NM()
    nm.wifi_was_on = true
    G_reader_settings:makeTrue("wifi_was_on")
    nm.lease_ssid = ssid
    nm.pending_connection = false
    pcall(function() nm:queryNetworkState() end)
    UIManager:broadcastEvent(Event:new("NetworkConnected"))
end

-- The one watch running (a new attempt replaces it).
local watch_id = 0

--- Call done(true, ssid) once connected (to `ssid`, or to any network when nil),
--- done(false) after the timeout.
function W.watch(ssid, done, timeout)
    watch_id = watch_id + 1
    local id = watch_id
    local deadline = (timeout or W.CONNECT_TIMEOUT) / W.POLL
    local tries = 0
    local function check()
        if id ~= watch_id then return end
        tries = tries + 1
        local cur = W.current()
        if cur and (ssid == nil or cur == ssid) then
            markConnected(cur)
            done(true, cur)
        elseif tries >= deadline then
            done(false, ssid)
        else
            UIManager:scheduleIn(W.POLL, check)
        end
    end
    UIManager:scheduleIn(W.POLL, check)
end

function W.stopWatching()
    watch_id = watch_id + 1
end

--- Turn the radio on; done(true, ssid) if it joins a saved network by itself,
--- done(false) if it is on but not connected.
function W.turnOn(done)
    UIManager:broadcastEvent(Event:new("NetworkConnecting"))
    if Device:isKindle() and kindleRadio(true) then
        -- the Kindle joins its saved networks on its own
        W.watch(nil, done or function() end, 15)
        return
    end
    -- other devices: KOReader's own way (it may show its own list)
    try("on", function()
        NM():toggleWifiOn(function() if done then done(true, W.current()) end end, false, true)
    end)
end

function W.turnOff(done)
    W.stopWatching()
    try("off", function() NM():disableWifi(done, true) end)
end

--- Join `net`, with a new password when given. done(ok, ssid) when we know.
function W.connect(net, password, done)
    local nm = NM()
    if password ~= nil or not (net.password and net.password ~= "") then
        -- a new network, or a new password: save it first (the Kindle needs a profile)
        net.password = password
        try("save", function()
            nm:saveNetwork({ ssid = net.ssid, password = password, flags = net.flags or "", psk = net.psk })
        end)
    end
    W.failed[net.ssid] = nil
    local ok, err = try("join", function() return nm:authenticateNetwork(net) end)
    if ok == false then
        W.failed[net.ssid] = true
        logger.warn("MinimalHome: wifi join failed:", err)
        done(false, net.ssid)
        return
    end
    try("ip", function() nm:obtainIP() end)
    W.watch(net.ssid, function(success, ssid)
        if not success then W.failed[net.ssid] = true end
        done(success, ssid or net.ssid)
    end)
end

--- The snackbar for the result.
function W.report(ok, ssid)
    local Snackbar = require("mh/ui/snackbar")
    if ok then
        Snackbar.show("Connected to " .. (ssid or "Wi-Fi"), 3)
    else
        Snackbar.show("Couldn’t connect to " .. (ssid or "Wi-Fi"), 4)
    end
end

-- Sleep ------------------------------------------------------------------------

--- Going to sleep: Wi-Fi off (it is the biggest drain), remembering whether it was on.
function W.sleep()
    -- "going to sleep" can come more than once: by the second time Wi-Fi is
    -- already off, so only the first one says whether it was on
    if W.asleep then return end
    W.asleep = true
    W.was_on = W.isOn()
    if W.was_on then W.turnOff() end
end

--- Waking up: Wi-Fi back on only if it was on before sleeping. Quietly: it
--- joins the saved network by itself, the status bar shows when it has.
function W.wake()
    W.asleep = nil
    if not W.was_on then return end
    W.was_on = nil
    UIManager:scheduleIn(1, function()
        if not W.isOn() then W.turnOn() end
    end)
end

return W
