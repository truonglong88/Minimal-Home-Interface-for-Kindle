--[[--
Low battery warnings (design: "Battery").

  20 %  snackbar "Battery low · 20%", goes away by itself
   5 %  popup "Battery 5%" that stays until OK is tapped (or the charger is
        plugged in)

Each is shown once, as the level is crossed. Nothing while charging; charging
back above 25 % arms them again. Checked once a minute while awake (a timer
that stops while the Kindle sleeps) and when the charger is plugged / unplugged.
--]]

local Device = require("device")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Prefs = require("mh/data/prefs")

local B = {}

B.LOW = 20
B.CRITICAL = 5
B.REARM = 25
B.EVERY = 60 -- seconds

local function level()
    if not Device:hasBattery() then return nil end
    local ok, cap, charging = pcall(function()
        local p = Device:getPowerDevice()
        return p:getCapacity(), p:isCharging()
    end)
    if not ok then return nil end
    return tonumber(cap), charging == true
end

function B.closePopup()
    if B.popup and not B.popup.closed then
        B.popup.sticky = false
        B.popup:answer(true)
    end
    B.popup = nil
end

function B.showCritical(cap)
    if B.popup and not B.popup.closed then return end
    local C = require("mh/ui/components")
    local Theme = require("mh/theme")
    local col = Theme.boldColors(false)
    B.popup = require("mh/ui/confirm").show{
        title = "Battery " .. cap .. "%",
        title_icon = C.batteryIcon(Theme.px(96), Theme.px(48), cap, col.fg),
        text = "Plug in your Kindle. It turns itself off when the battery runs out; your page is saved.",
        no_ok = true, cancel_text = "OK", sticky = true,
        cancel_callback = function() B.popup = nil end,
    }
end

--- Look at the battery now and warn if a level has just been crossed.
function B.check()
    local cap, charging = level()
    if not cap then return end
    local warned = Prefs.get("battery_warned") -- nil, 20 or 5
    if charging then
        B.closePopup()
        if warned and cap > B.REARM then Prefs.set("battery_warned", nil) end
        return
    end
    if warned and cap > B.REARM then
        Prefs.set("battery_warned", nil)
        warned = nil
    end
    if cap <= B.CRITICAL and warned ~= B.CRITICAL then
        Prefs.set("battery_warned", B.CRITICAL)
        logger.info("MinimalHome: battery critical:", cap)
        B.showCritical(cap)
    elseif cap <= B.LOW and not warned then
        Prefs.set("battery_warned", B.LOW)
        logger.info("MinimalHome: battery low:", cap)
        require("mh/ui/snackbar").show("Battery low · " .. cap .. "%", 4)
    end
end

local function tick()
    local ok, err = pcall(B.check)
    if not ok then logger.warn("MinimalHome: battery check:", err) end
    UIManager:scheduleIn(B.EVERY, tick)
end

--- Start the once-a-minute check (one timer, however many plugin instances).
function B.start(delay)
    if not Device:hasBattery() then return end
    UIManager:unschedule(tick)
    UIManager:scheduleIn(delay or 2, tick)
end

function B.stop()
    UIManager:unschedule(tick)
end

return B
