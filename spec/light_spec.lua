-- The light stays off once switched off in the quick panel, even when the
-- Kindle relights it by itself; turning it on through KOReader is respected.
-- Usage: luajit spec/light_spec.lua
package.path = "minimalhome.koplugin/?.lua;" .. package.path
local tasks = {}
local settings = {}
_G.G_reader_settings = {
    readSetting = function(_, k) return settings[k] end,
    saveSetting = function(_, k, v) settings[k] = v end,
}
local hw, flag = 10, true -- hardware level, KOReader's own "is on" flag
local p = { fl_min = 0, fl_max = 24, fl_intensity = 10 }
function p:isFrontlightOnHW() return hw > 0 end
function p:isFrontlightOn() return flag end
function p:turnOffFrontlight() if not flag then return end hw = 0; flag = false end
function p:turnOnFrontlight() hw = self.fl_intensity; flag = true end
function p:setIntensityHW(v) hw = v end
function p:_decideFrontlightState() flag = hw > 0 end
function p:updateResumeFrontlightState() end
function p:frontlightIntensity() return hw end
package.loaded["device"] = { getPowerDevice = function() return p end, hasFrontlight = function() return true end }
package.loaded["ui/event"] = {}
package.loaded["logger"] = { info = function() end, warn = print, err = print, dbg = function() end }
package.loaded["ui/uimanager"] = {
    scheduleIn = function(_, _, f) tasks[#tasks + 1] = f end,
    unschedule = function(_, f) for i, t in ipairs(tasks) do if t == f then table.remove(tasks, i) end end end,
}
local D = dofile("minimalhome.koplugin/mh/device.lua")
local function tick() local t = table.remove(tasks, 1); if t then t() end end

D.setLightOn(false)
assert(hw == 0 and not D.lightOn(), "switched off")
assert(#tasks == 0, "no polling")
-- the device wakes with the light relit by the Kindle: turned off again
hw = 15
D.keepLightOff()
assert(hw == 0, "kept off on wake")
-- turned on through KOReader's own light dialog: respected, not fought
flag, hw = true, 8
D.keepLightOff()
assert(hw == 8 and settings.minimalhome.light_off == false, "KOReader's own 'on' is respected")
print("light OK")
