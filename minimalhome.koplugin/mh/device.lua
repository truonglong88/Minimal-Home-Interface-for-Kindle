--[[--
Device actions used by the quick panel and the Settings page. Every function
talks to KOReader's own modules and settings, so KOReader's menus stay in step.
All of them are guarded: a missing module never takes the screen down.
--]]

local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Prefs = require("mh/data/prefs")

local D = {}

local function try(what, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok then
        logger.warn("MinimalHome:", what, "failed:", a)
        return nil
    end
    return a, b
end

-- Wi-Fi ----------------------------------------------------------------------

function D.hasWifi()
    return Device:hasWifiToggle()
end

function D.wifiOn()
    return try("wifi state", function()
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr.getWifiState then return NetworkMgr:getWifiState() end
        return NetworkMgr:isWifiOn()
    end) == true
end

function D.wifiConnected()
    return require("mh/ui/components").wifiConnected()
end

function D.toggleWifi(done)
    try("wifi toggle", function()
        local NetworkMgr = require("ui/network/manager")
        if D.wifiOn() then
            NetworkMgr:toggleWifiOff(done, true)
        else
            NetworkMgr:toggleWifiOn(done, false, true)
        end
    end)
end

-- Night mode ------------------------------------------------------------------

function D.nightMode()
    return G_reader_settings:isTrue("night_mode")
end

function D.toggleNightMode()
    UIManager:broadcastEvent(Event:new("ToggleNightMode"))
    UIManager:setDirty("all", "full")
end

-- Rotation lock (accelerometer) ----------------------------------------------------

function D.hasGSensor()
    return Device:hasGSensor()
end

--- Locked = the accelerometer is ignored, the screen keeps its orientation.
function D.rotationLocked()
    return G_reader_settings:isTrue("input_ignore_gsensor")
end

--- Auto-rotation only between upright and upside down, never sideways
--- (KOReader's "Lock auto rotation to current orientation", from portrait).
function D.keepPortraitRotation(ui)
    if not Device:hasGSensor() then return end
    try("portrait lock", function()
        local Screen = Device.screen
        if Screen:getRotationMode() % 2 == 1 then
            -- currently sideways: go back to upright first
            if ui and ui.onSetRotationMode then ui:onSetRotationMode(0) else Screen:setRotationMode(0) end
        end
        if not G_reader_settings:isTrue("input_lock_gsensor") then
            G_reader_settings:makeTrue("input_lock_gsensor")
        end
        Device:lockGSensor(true)
    end)
end

--- The way the Kindle is held now: upright (0) or upside down (2). Sideways
--- counts as upright (we never rotate sideways).
function D.heldRotation()
    local m = Device.screen:getRotationMode() or 0
    return m % 2 == 1 and 0 or m
end

--- Going from a book to Home (and back) keeps the screen the way the Kindle is
--- held. KOReader would turn it to its own file browser default, or to the
--- rotation the book was last read in.
function D.followHeldRotation(ui)
    try("follow rotation", function()
        local FM = require("apps/filemanager/filemanager")
        if not FM._minimalhome_rotation then
            FM._minimalhome_rotation = true
            local orig = FM.setRotationMode
            FM.setRotationMode = function(self, ...)
                local rl = require("mh/rotlog")
                rl.log("file manager opens, before")
                if not require("mh/data/prefs").get("enabled") then return orig(self, ...) end
                if G_reader_settings:isTrue("lock_rotation") then return end
                local held = D.heldRotation()
                self:onSetRotationMode(held)
                rl.log("file manager opens, after (kept " .. tostring(held) .. ")")
            end
        end
        -- a book opening: its saved rotation is read right after the plugins are
        -- made, so make it the current one
        if ui and ui.document and ui.doc_settings and not G_reader_settings:isTrue("lock_rotation")
                and require("mh/data/prefs").get("enabled") then
            local key = ui.paging and "kopt_rotation_mode" or "copt_rotation_mode"
            require("mh/rotlog").log("book opens with its saved rotation", key .. "=" .. tostring(ui.doc_settings.readSetting
                and ui.doc_settings:readSetting(key)) .. " → " .. D.heldRotation())
            ui.doc_settings:saveSetting(key, D.heldRotation())
            local view = ui.view
            if view and view.onSetRotationMode and not view._minimalhome_rotlog then
                view._minimalhome_rotlog = true
                local orig_v = view.onSetRotationMode
                view.onSetRotationMode = function(v, mode, ...)
                    require("mh/rotlog").log("book turned", mode)
                    return orig_v(v, mode, ...)
                end
            end
        end
    end)
end

function D.toggleRotationLock()
    try("rotation lock", function()
        G_reader_settings:flipNilOrFalse("input_ignore_gsensor")
        Device:toggleGSensor(not G_reader_settings:isTrue("input_ignore_gsensor"))
    end)
end

-- Front light -------------------------------------------------------------------

function D.hasFrontlight()
    return Device:hasFrontlight()
end

local function powerd() return Device:getPowerDevice() end

function D.brightness()
    local p = powerd()
    return p:frontlightIntensity(), p.fl_min, p.fl_max
end

--- Is the light actually lit? Asks the hardware where possible: KOReader's own
--- flag can say "off" while the Kindle has turned the light back on (on wake).
function D.lightOn()
    return try("light state", function()
        local p = powerd()
        if p.isFrontlightOnHW then return p:isFrontlightOnHW() end
        return p:isFrontlightOn()
    end) == true
end

--- Make sure the light is really off: KOReader skips turnOffFrontlight when it
--- already believes the light is off, and the Kindle may relight it on wake.
function D.forceLightOff()
    try("light off", function()
        local p = powerd()
        if p.turnOffFrontlight then p:turnOffFrontlight() end
        local hw_on = p.isFrontlightOnHW and p:isFrontlightOnHW()
        if hw_on and p.setIntensityHW then
            p:setIntensityHW(p.fl_min) -- lipc and the kernel's brightness file: 0 is off
            if p._decideFrontlightState then p:_decideFrontlightState() end
        end
        -- so KOReader doesn't turn it back on when the device wakes up
        if p.updateResumeFrontlightState then p:updateResumeFrontlightState() end
    end)
end

local function koreaderSaysOn()
    return try("light flag", function() return powerd():isFrontlightOn() end) == true
end

--- Turn the front light off, or back on at its previous level. "Off" is
--- remembered and enforced again when the device wakes up and when KOReader starts.
--- Light on at its last level, whatever KOReader believes (its "on" flag can
--- be stale after sleep, and then turnOnFrontlight does nothing).
function D.relight()
    try("light on", function()
        local p = powerd()
        if (p.fl_intensity or p.fl_min) <= p.fl_min then
            p.fl_intensity = p.fl_min + math.max(1, math.floor((p.fl_max - p.fl_min) / 2))
        end
        p.is_fl_on = false
        p:turnOnFrontlight()
        if not D.lightOn() and p.turnOnFrontlightHW then
            p:turnOnFrontlightHW()
        end
        p.is_fl_on = true
    end)
end

function D.setLightOn(on)
    Prefs.set("light_off", not on)
    if on then
        D.relight()
    else
        D.forceLightOff()
    end
end

--- Called on wake and at start: keep the light off if the user turned it off.
function D.keepLightOff()
    if not Prefs.get("light_off") or D.autoBrightness() then return end
    -- turned back on through KOReader's own light dialog: respect that
    if koreaderSaysOn() then Prefs.set("light_off", false) return end
    D.forceLightOff()
end

-- The quick panel shows the light in 12 steps (Oasis 2 hardware: 0–24).
D.LIGHT_STEPS = 12

function D.brightnessStep()
    local level, lo, hi = D.brightness()
    if hi <= lo then return 0 end
    return math.floor((level - lo) / (hi - lo) * D.LIGHT_STEPS + 0.5)
end

function D.setBrightnessStep(step)
    local _, lo, hi = D.brightness()
    step = math.max(0, math.min(D.LIGHT_STEPS, step))
    D.setBrightness(lo + math.floor((hi - lo) * step / D.LIGHT_STEPS + 0.5))
end

function D.setBrightness(v)
    try("brightness", function()
        local p = powerd()
        v = math.max(p.fl_min, math.min(p.fl_max, v))
        if v > p.fl_min then Prefs.set("light_off", false) end
        if v == p.fl_min then
            p:setIntensity(v)
            if p.turnOffFrontlight then p:turnOffFrontlight() end
        else
            if p.turnOnFrontlight and not p:isFrontlightOn() then p:turnOnFrontlight() end
            p:setIntensity(v)
        end
    end)
end

--- Going to sleep: put the light out, whatever its setting, so the
--- screensaver is not lit all night. The Kindle can relight it while it
--- settles into sleep, so it is put out again a few times.
--- Switching the light off in hardware also makes KOReader think the user
--- turned it off, so its "on" flag is put back each time: waking relights it.
local sleep_offs = {}
local lit_before_sleep = false
local asleep = false
function D.lightOffForSleep()
    if not Device:hasFrontlight() then return end
    D.cancelSleepLight()
    -- the Kindle can send "going to sleep" more than once: remember the state
    -- from the first time only (by the second the light is already out)
    if not asleep then lit_before_sleep = D.lightOn() == true end
    asleep = true
    local function off()
        try("light off for sleep", function()
            local p = powerd()
            if p.turnOffFrontlightHW then p:turnOffFrontlightHW() else p:setIntensityHW(p.fl_min) end
            p.is_fl_on = lit_before_sleep
        end)
    end
    off()
    for _, delay in ipairs({ 0.5, 2, 5 }) do
        sleep_offs[#sleep_offs + 1] = off
        UIManager:scheduleIn(delay, off)
    end
end

--- Waking up: stop putting the light out, and relight it if it was lit.
function D.cancelSleepLight()
    for _, f in ipairs(sleep_offs) do UIManager:unschedule(f) end
    sleep_offs = {}
end

function D.lightAfterSleep()
    D.cancelSleepLight()
    asleep = false
    if not lit_before_sleep then return end
    lit_before_sleep = false
    if Prefs.get("light_off") then return end
    -- KOReader relights it too (a tick later); make sure, without fighting it
    D.relight()
    UIManager:scheduleIn(1, function()
        if not D.lightOn() and not Prefs.get("light_off") then D.relight() end
    end)
end

--- Ambient light in lux from the Kindle's light sensor, or nil when the
--- reading is not available (KOReader has no API for it; we ask the system).
function D.ambientLux()
    if not Device:isKindle() then return nil end
    return try("light sensor", function()
        local ok, lipc = pcall(require, "liblipclua")
        if not ok or not lipc then return nil end
        local h = lipc.init and lipc.init("com.github.koreader.minimalhome")
            or (lipc.open_no_name and lipc.open_no_name())
        if not h then return nil end
        local okv, lux = pcall(h.get_int_property, h, "com.lab126.powerd", "alsLux")
        h:close()
        if okv and type(lux) == "number" and lux >= 0 then return lux end
        return nil
    end)
end

function D.hasAutoBrightness()
    return Device:hasLightSensor() and D.ambientLux() ~= nil
end

function D.autoBrightness()
    return Prefs.get("auto_brightness") == true
end

--- Light level for a lux reading: dark room → dim, daylight → off.
function D.brightnessForLux(lux, fl_min, fl_max)
    local span = fl_max - fl_min
    if lux >= 2000 then return fl_min end -- daylight: e-ink needs no light
    local t = math.log(lux + 1) / math.log(2001)   -- 0 (dark) … 1 (bright)
    local level = 0.15 + 0.6 * t                    -- dim in the dark, brighter indoors
    return fl_min + math.floor(span * level + 0.5)
end

local auto_tick
function D.applyAutoBrightness()
    if not D.autoBrightness() then return end
    -- the light was switched off by hand: auto brightness must not light it again
    if Prefs.get("light_off") then return end
    local lux = D.ambientLux()
    if not lux then return end
    local level, lo, hi = D.brightness()
    local want = D.brightnessForLux(lux, lo, hi)
    -- only touch the light when the level changes (no write every minute)
    if want ~= level then
        D.setBrightness(want)
        -- an open quick panel redraws its bar for the new level
        UIManager:broadcastEvent(require("ui/event"):new("MHBrightnessChanged"))
    end
end

function D.startAutoBrightness()
    if auto_tick then UIManager:unschedule(auto_tick) end
    if not D.autoBrightness() then return end
    auto_tick = function()
        D.applyAutoBrightness()
        UIManager:scheduleIn(60, auto_tick)
    end
    auto_tick()
end

function D.stopAutoBrightness()
    if auto_tick then UIManager:unschedule(auto_tick) end
    auto_tick = nil
end

--- Returns false (and changes nothing) when the sensor cannot be read.
function D.setAutoBrightness(on)
    if on and not D.ambientLux() then return false end
    Prefs.set("auto_brightness", on and true or false)
    if on then D.startAutoBrightness() else D.stopAutoBrightness() end
    return true
end

-- Screen refresh ----------------------------------------------------------------

D.REFRESH_STEPS = { 0, 1, 6, 12, 24 } -- 0 = never

function D.refreshEvery()
    local rate = UIManager:getRefreshRate()
    return rate or 6
end

function D.refreshLabel(n)
    if n == 0 then return "Never" elseif n == 1 then return "Every page" end
    return "Every " .. n .. " pages"
end

function D.cycleRefresh()
    local cur = D.refreshEvery()
    local nxt = D.REFRESH_STEPS[1]
    for i, v in ipairs(D.REFRESH_STEPS) do
        if v == cur then nxt = D.REFRESH_STEPS[i % #D.REFRESH_STEPS + 1] break end
    end
    try("refresh rate", function()
        UIManager:setRefreshRate(nxt, nxt)
        G_reader_settings:saveSetting("full_refresh_count", nxt)
        G_reader_settings:saveSetting("night_full_refresh_count", nxt)
    end)
end

-- Page-turn buttons ---------------------------------------------------------------

function D.hasPageButtons()
    return Device:hasKeys()
end

function D.pageButtonsSwapped()
    return G_reader_settings:isTrue("input_invert_page_turn_keys")
end

function D.toggleSwapPageButtons()
    UIManager:broadcastEvent(Event:new("SwapPageTurnButtons"))
end

-- Sleep timer (AutoSuspend plugin) -----------------------------------------------------

D.SLEEP_STEPS = { 5, 10, 15, 30, 60, 0 } -- minutes, 0 = never

function D.sleepMinutes()
    local s = G_reader_settings:readSetting("auto_suspend_timeout_seconds") or 15 * 60
    return math.floor(s / 60 + 0.5)
end

function D.sleepLabel(m)
    if m <= 0 then return "Never" end
    if m >= 60 and m % 60 == 0 then return (m / 60) .. " h" end
    return m .. " min"
end

function D.cycleSleep(ui)
    local cur = D.sleepMinutes()
    local nxt = D.SLEEP_STEPS[1]
    for i, v in ipairs(D.SLEEP_STEPS) do
        if v == cur then nxt = D.SLEEP_STEPS[i % #D.SLEEP_STEPS + 1] break end
    end
    local seconds = nxt > 0 and nxt * 60 or -1
    G_reader_settings:saveSetting("auto_suspend_timeout_seconds", seconds)
    local as = ui and ui.autosuspend
    if as then
        try("sleep timer", function()
            as.auto_suspend_timeout_seconds = seconds
            if as._unschedule then as:_unschedule() end
            if seconds > 0 and as._start then as:_start() end
        end)
    end
end

-- SSH (KOReader's SSH plugin) ---------------------------------------------------------

function D.hasSSH(ui)
    return ui and ui.SSH ~= nil
end

function D.sshRunning(ui)
    return D.hasSSH(ui) and try("ssh state", function() return ui.SSH:isRunning() end) == true
end

--- The Kindle's IPv4 address on Wi-Fi, or nil.
function D.ipAddress()
    return try("ip address", function()
        local ok, NetInfo = pcall(require, "ffi/netinfo")
        if ok and NetInfo and NetInfo.new then
            for _, iface in ipairs(NetInfo:new():retrieve() or {}) do
                if iface.ipv4 and iface.name ~= "lo" then return iface.ipv4 end
            end
        end
        -- older KOReader: ask the system
        local p = io.popen("ifconfig wlan0 2>/dev/null")
        if p then
            local out = p:read("*a") or ""
            p:close()
            return out:match("inet addr:(%d+%.%d+%.%d+%.%d+)") or out:match("inet (%d+%.%d+%.%d+%.%d+)")
        end
    end)
end

function D.sshPort(ui)
    return tostring(ui and ui.SSH and ui.SSH.SSH_port or G_reader_settings:readSetting("SSH_port") or "2222")
end

--- Sub-line for the SSH row: where to connect when it is on.
function D.sshInfo(ui)
    if not D.sshRunning(ui) then return "For wireless updates" end
    local ip = D.ipAddress()
    if not ip then return "On · port " .. D.sshPort(ui) .. " (no Wi-Fi address)" end
    return "IP " .. ip .. " · port " .. D.sshPort(ui)
end

function D.toggleSSH(ui)
    if not D.hasSSH(ui) then return end
    try("ssh toggle", function()
        if ui.SSH:isRunning() then ui.SSH:stop() else ui.SSH:start() end
    end)
end

-- Storage ------------------------------------------------------------------------

--- Free and total bytes on the partition that holds the books, or nil.
function D.storage(path)
    return try("storage", function()
        local u = require("util").diskUsage(path or require("mh/data/prefs").booksFolder())
        if not u or not u.total or u.total <= 0 then return nil end
        return u.available or (u.total - (u.used or 0)), u.total
    end)
end

--- "2.3 GB free of 4 GB" (decimal units, as on a computer).
function D.storageLabel(free, total)
    local function size(b)
        if b >= 1e9 then
            local s = string.format("%.1f", b / 1e9):gsub("%.0$", "")
            return s .. " GB"
        end
        return string.format("%d MB", math.floor(b / 1e6 + 0.5))
    end
    return size(free) .. " free of " .. size(total)
end

-- Battery ------------------------------------------------------------------------

function D.battery()
    if not Device:hasBattery() then return nil end
    return try("battery", function()
        local p = powerd()
        return p:getCapacity(), p:isCharging()
    end)
end

-- Fonts ---------------------------------------------------------------------------

function D.currentFont()
    return G_reader_settings:readSetting("cre_font") or "Noto Serif"
end

function D.fontList()
    return try("font list", function()
        local cre = require("document/credocument"):engineInit()
        local list = cre.getFontFaces()
        table.sort(list, function(a, b) return a:lower() < b:lower() end)
        return list
    end) or {}
end

--- File and face index of a book font (to draw its name in its own style).
function D.fontFile(face)
    return try("font file", function()
        local cre = require("document/credocument"):engineInit()
        local file, idx = cre.getFontFaceFilenameAndFaceIndex(face)
        if not file then file, idx = cre.getFontFaceFilenameAndFaceIndex(face, nil, true) end
        return file, idx
    end)
end

--- Used for books opened from now on (KOReader's default book font).
function D.setFont(face)
    G_reader_settings:saveSetting("cre_font", face)
end

-- Screensaver ----------------------------------------------------------------------

D.SCREENSAVERS = {
    { id = "book", label = "Book cover", desc = "The book you are reading" },
    { id = "cats", label = "Two cats", desc = "A black cat and a white cat", file = "cats.png" },
    { id = "cups", label = "Teacups", desc = "Two kittens in coffee cups", file = "cups.png" },
    { id = "phone", label = "Lazy Sunday", desc = "A black cat scrolling on a pillow", file = "phone.png" },
    { id = "ink", label = "Scribble pals", desc = "A dog and his bird friend in ink", file = "scribble-dog.png" },
    { id = "peek", label = "Peekaboo", desc = "A kitten peeking over the edge", file = "peek.png" },
}

function D.screensaverPath(entry)
    if not entry.file then return nil end
    return require("mh/theme").plugin_dir .. "/screensavers/" .. entry.file
end

--- Which of our options KOReader is set to now (nil if something else).
function D.currentScreensaver()
    local t = G_reader_settings:readSetting("screensaver_type")
    if t == "cover" then return "book" end
    if t == "document_cover" then
        local path = G_reader_settings:readSetting("screensaver_document_cover") or ""
        for _, e in ipairs(D.SCREENSAVERS) do
            if e.file and path:sub(-#e.file - 1) == "/" .. e.file then return e.id end
        end
    end
    return nil
end

function D.screensaverLabel()
    local id = D.currentScreensaver()
    for _, e in ipairs(D.SCREENSAVERS) do
        if e.id == id then return e.label end
    end
    local t = G_reader_settings:readSetting("screensaver_type")
    if t == "disable" or t == nil then return "Off" end
    return "Custom"
end

--- With "Book cover", a book without a cover (or one KOReader skips) falls back
--- to a random picture from screensaver_dir: point it at a folder holding only
--- the "Two cats" picture, so the fallback is always the cats.
function D.ensureCoverFallback()
    local dir = require("mh/theme").plugin_dir .. "/screensavers/fallback"
    G_reader_settings:saveSetting("screensaver_dir", dir)
    G_reader_settings:makeTrue("screensaver_images_crop_to_fit")
end

function D.setScreensaver(id)
    for _, e in ipairs(D.SCREENSAVERS) do
        if e.id == id then
            if e.file then
                -- a single image: KOReader shows a "document cover" that is an image file
                G_reader_settings:saveSetting("screensaver_type", "document_cover")
                G_reader_settings:saveSetting("screensaver_document_cover", D.screensaverPath(e))
                G_reader_settings:makeTrue("screensaver_images_crop_to_fit")
            else
                G_reader_settings:saveSetting("screensaver_type", "cover")
                D.ensureCoverFallback()
            end
            -- no "Sleeping" banner over the picture
            G_reader_settings:makeFalse("screensaver_show_message")
            return true
        end
    end
    return false
end

-- KOReader itself ---------------------------------------------------------------------

--- Restart or quit KOReader, with the top loading bar (as when a book opens)
--- running while settings are saved and widgets close. Quitting blocks the
--- event loop, so the bar is painted straight to the screen at each step.
local function leave(ui, finish, message)
    local LB = require("mh/loadingbar")
    LB.show(0.15, true)
    -- stays on screen until KOReader is gone
    pcall(function() require("mh/ui/snackbar").paintNow(message) end)
    UIManager:scheduleIn(0.05, function()
        LB.show(0.45, true)
        pcall(function() G_reader_settings:flush() end)
        LB.show(0.75, true)
        local function last()
            LB.show(1, true)
            finish()
        end
        if ui and ui.menu and ui.menu.exitOrRestart then
            ui.menu:exitOrRestart(last)
        else
            last()
        end
    end)
end

function D.restartKOReader(ui)
    leave(ui, function() UIManager:restartKOReader() end, "Restarting KOReader…")
end

--- Quit KOReader; on a Kindle this returns to the Kindle's own home screen.
--- Closing the file browser alone is not enough: our home screen (and this
--- Settings page) are still open, so KOReader would keep running.
function D.exitKOReader(ui)
    leave(ui, function() UIManager:quit() end, "Exiting to Kindle…")
end

-- Books ---------------------------------------------------------------------

--- Delete a book file with its reading progress (KOReader's own delete, as in
--- its file browser). True when the file is gone.
function D.deleteBook(ui, path)
    local ok, res = pcall(function()
        local fm = ui and ui.deleteFile and ui or require("apps/filemanager/filemanager").instance
        if fm and fm.deleteFile then return fm:deleteFile(path, true) end
        local removed = os.remove(path)
        if removed then
            pcall(function() require("docsettings").updateLocation(path) end)
            pcall(function() require("readhistory"):fileDeleted(path) end)
        end
        return removed
    end)
    if not ok then logger.warn("MinimalHome: delete failed:", res) end
    if ok and res then return true end
    return require("libs/libkoreader-lfs").attributes(path, "mode") == nil
end

return D
