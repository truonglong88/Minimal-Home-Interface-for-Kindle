local screen = { _w = 1264, _h = 1680, _mode = 0 }
screen.getWidth = function() return screen._w end
screen.getHeight = function() return screen._h end
screen.getSize = function() return { w = screen._w, h = screen._h } end
screen.getRotationMode = function() return screen._mode end
screen.setRotationMode = function(_, m)
    screen._mode = m
    if m % 2 == 1 then screen._w, screen._h = 1680, 1264 else screen._w, screen._h = 1264, 1680 end
end
for k, v in pairs({
    scaleBySize = function(_, px) return math.ceil((tonumber(px) or 0) * 1264 / 600) end,
    scaleByDPI = function(_, px) return px end, getDPI = function() return 300 end,
}) do screen[k] = v end
return {
    screen = screen,
    input = { group = { PgFwd = { "RPgFwd", "LPgFwd" }, PgBack = { "RPgBack", "LPgBack" }, Back = { "Back" } } },
    isTouchDevice = function() return true end,
    hasKeys = function() return true end,
    hasScreenKB = function() return false end,
    hasDPad = function() return false end,
    hasFewKeys = function() return false end,
    useDPadAsActionKeys = function() return false end,
    hasKeyboard = function() return false end,
    hasSymKey = function() return false end,
    hasKeyboard = function() return false end,
    hasBattery = function() return true end,
    hasFrontlight = function() return true end,
    hasWifiToggle = function() return true end,
    hasGSensor = function() return true end,
    hasLightSensor = function() return true end,
    isKindle = function() return true end,
    model = "KindleOasis2",
    toggleGSensor = function() end,
    lockGSensor = function() end,
    getPowerDevice = function()
        _G.__mh_powerd = _G.__mh_powerd or {
            fl_min = 0, fl_max = 24, _i = 12,
            getCapacity = function() return 82 end,
            isCharging = function() return false end,
            frontlightIntensity = function(p) return p._i end,
            setIntensity = function(p, v) p._i = v end,
            isFrontlightOn = function(p) return p._i > 0 end,
            turnOnFrontlight = function() end,
            turnOffFrontlight = function() end,
        }
        return _G.__mh_powerd
    end,
}
