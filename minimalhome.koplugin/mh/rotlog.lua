--[[
Rotation log: writes one line to crash.log ("MinimalHome rot:") at each step
where the screen's rotation can change, so a wrong orientation on the device
can be traced. Temporary, for the "Home turns the wrong way" bug.
]]
local logger = require("logger")

local R = {}

function R.state()
    local Device = require("device")
    local Screen = Device.screen
    local parts = {}
    local function add(k, v) parts[#parts + 1] = k .. "=" .. tostring(v) end
    pcall(function() add("screen", Screen:getRotationMode()) end)
    pcall(function() add("native", Screen.native_rotation_mode) end)
    pcall(function() add("touch", Screen.getTouchRotation and Screen:getTouchRotation()) end)
    pcall(function() add("size", Screen:getWidth() .. "x" .. Screen:getHeight()) end)
    pcall(function() add("locked", Device:isGSensorLocked()) end)
    add("fm_default", G_reader_settings:readSetting("fm_rotation_mode"))
    add("lock_rotation", G_reader_settings:isTrue("lock_rotation"))
    add("ignore_gsensor", G_reader_settings:isTrue("input_ignore_gsensor"))
    return table.concat(parts, " ")
end

function R.log(where, extra)
    pcall(function()
        logger.info("MinimalHome rot:", where, extra and tostring(extra) or "", R.state())
    end)
end

--- Log every accelerometer turn the device reports.
function R.install()
    pcall(function()
        local Input = require("device").input
        if not Input or Input._minimalhome_rotlog then return end
        Input._minimalhome_rotlog = true
        local orig = Input.handleMiscGyroEv
        if not orig then return end
        local function wrapped(self, ev)
            R.log("gyro before", ev and ev.value)
            local res = orig(self, ev)
            R.log("gyro after", res and res.handler or "-")
            return res
        end
        Input.handleMiscGyroEv = wrapped
        if Input.handleGyroEv == orig then Input.handleGyroEv = wrapped end
    end)
end

return R
