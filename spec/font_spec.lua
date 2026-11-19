-- Fonts must load even when KOReader's working directory is unknown and
-- Font:getFace raises on a path it can't open (the 0.1.3 "home screen gone" bug).
-- Usage: luajit spec/font_spec.lua
package.path = "minimalhome.koplugin/?.lua;" .. package.path
local function load(bad)
    local tried = {}
    package.loaded["mh/theme"] = nil
    package.loaded["ffi/blitbuffer"] = { gray = function() return 0 end, COLOR_BLACK = 1, COLOR_WHITE = 0 }
    package.loaded["device"] = { screen = { getWidth = function() return 1264 end, getHeight = function() return 1680 end } }
    package.loaded["libs/libkoreader-lfs"] = { currentdir = function() return nil end }
    package.loaded["fontlist"] = { fontdir = "./fonts" }
    package.loaded["ui/font"] = { getFace = function(_, name)
        tried[#tried + 1] = name
        if name:find(bad) then error("attempt to index local 'face' (a nil value)") end
        return { name = name }
    end }
    local getinfo = debug.getinfo
    debug.getinfo = function(l, w)
        local i = getinfo(l, w); i.source = "@./plugins/minimalhome.koplugin/mh/theme.lua"; return i
    end
    local Theme = dofile("minimalhome.koplugin/mh/theme.lua")
    debug.getinfo = getinfo
    return Theme, tried
end
local Theme = load("^%./plugins")
local f = Theme.face("sans", 30)
assert(f and f.name == "../plugins/minimalhome.koplugin/fonts/Inter-Regular.ttf", "our font, relative to fonts/: " .. tostring(f and f.name))
Theme = load("plugins")
f = Theme.face("sans", 30)
assert(f and f.name == "NotoSans-Regular.ttf", "falls back to KOReader's font: " .. tostring(f and f.name))
assert(Theme.fontName("sans_medium") == "NotoSans-Regular.ttf", "status bar font falls back too")
print("fonts OK")
