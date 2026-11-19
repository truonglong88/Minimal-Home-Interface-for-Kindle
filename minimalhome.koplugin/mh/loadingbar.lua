--[[--
A thin loading bar across the very top of the screen while a book opens.

Opening a book blocks KOReader's event loop, so nothing can animate; instead the
bar is painted straight onto the screen at each progress report from the book
engine (crengine sends them while loading and laying out the book) and from our
own code (when the tap lands, when the reader starts). KOReader's own small
progress bar (top left, after 2 s) is replaced by this one.
--]]

local Device = require("device")
local Screen = Device.screen
local logger = require("logger")

local Theme = require("mh/theme")

local LB = {}

local last_paint = 0
local shown = false
local MIN_INTERVAL = 0.25 -- seconds between repaints (e-ink refreshes are slow)

local function now()
    local ok, t = pcall(function() return require("ffi/util").gettime() end)
    if ok and t then return t end
    return os.time()
end

--- Paint the bar at `ratio` (0…1).
function LB.show(ratio, force)
    local ok, err = pcall(function()
        local t = now()
        if not force and shown and t - last_paint < MIN_INTERVAL and ratio < 1 then return end
        last_paint, shown = t, true
        local Blitbuffer = require("ffi/blitbuffer")
        local w = Screen:getWidth()
        local h = Theme.px(10)
        local filled = math.max(Theme.px(24), math.floor(w * math.max(0, math.min(1, ratio)) + 0.5))
        Screen.bb:paintRect(0, 0, w, h, Blitbuffer.COLOR_WHITE)
        Screen.bb:paintRect(0, 0, filled, h, Blitbuffer.COLOR_BLACK)
        Screen:refreshFast(0, 0, w, h)
    end)
    if not ok then logger.warn("MinimalHome: loading bar:", err) end
end

--- Loading finished: the reader repaints the whole screen, which clears the bar.
function LB.done()
    shown = false
end

--- Route crengine's load/layout progress to our bar (once, for every book).
function LB.install()
    local ok, ReaderRolling = pcall(require, "apps/reader/modules/readerrolling")
    if not ok or not ReaderRolling or ReaderRolling._minimalhome_bar then return end
    local original = ReaderRolling.showEngineProgress
    ReaderRolling.showEngineProgress = function(self, percent)
        if not require("mh/data/prefs").get("reader_style") then
            return original(self, percent)
        end
        if percent then
            -- loading is the first half; keep the bar moving forward only
            LB.show(0.1 + 0.9 * percent)
        else
            LB.done()
        end
    end
    ReaderRolling._minimalhome_bar = true
end

return LB
