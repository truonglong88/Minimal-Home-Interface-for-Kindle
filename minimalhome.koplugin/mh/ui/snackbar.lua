--[[--
Snackbar (design: "Snackbar – 1/3 from the bottom").

A black rounded box with white text, centred, its bottom edge one third of
the screen height above the bottom. One look for every message.

    Snackbar.show("Updated")                  -- goes away after 2 s
    Snackbar.show("Screenshot saved", 3)
    Snackbar.show(title, nil, "second line")  -- smaller grey line under it
    Snackbar.paintNow("Opening book…")       -- straight onto the screen, for
                                              -- moments that block the UI
                                              -- (opening a book, restart, exit)
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local Screen = Device.screen

local C = require("mh/ui/components")
local Theme = require("mh/theme")
local px = Theme.px

local Snackbar = InputContainer:extend{
    text = "",
    sub = nil,
    timeout = 2,
    toast = true, -- never takes taps away from what is underneath
}

local current

Snackbar.MAX_LINES = 6

--- How long a message stays: 2 s, plus about a second per extra line of text.
function Snackbar.duration(text, sub)
    local n = #(text or "") + #(sub or "")
    return math.min(8, 2 + math.floor(n / 45))
end

--- The box itself (also used by paintNow).
local function build(text, sub)
    local W = Screen:getWidth()
    local max_w = math.min(px(980), W - 2 * px(Theme.margin_h))
    local pad_h, pad_v = px(56), px(30)
    local inner_w = max_w - 2 * pad_h
    -- one line when it fits (the box hugs the text), wrapped when it doesn't
    local function line(str, kind, size, color)
        local t = C.text(str, kind, size, color)
        if t:getSize().w <= inner_w then return t end
        t:free()
        return C.textboxOn(Blitbuffer.COLOR_BLACK, str, kind, size, color, inner_w, Snackbar.MAX_LINES, 0.3, "center")
    end
    local group = VerticalGroup:new{ align = "center", line(text, "sans_bold", 36, Blitbuffer.COLOR_WHITE) }
    if sub and sub ~= "" then
        table.insert(group, C.space(1, px(8)))
        table.insert(group, line(sub, "sans_medium", 30, Blitbuffer.gray(0.15)))
    end
    local box_w = math.max(px(320), group:getSize().w + 2 * pad_h)
    local gh = group:getSize().h
    local box_h = gh + 2 * pad_v
    local box = C.box(box_w, box_h, group, { bg = Blitbuffer.COLOR_BLACK, radius = px(16),
        halign = "center", valign = "center" })
    local H = Screen:getHeight()
    local x = math.floor((W - box_w) / 2)
    local y = H - math.floor(H / 3) - box_h
    return box, Geom:new{ x = x, y = y, w = box_w, h = box_h }
end

Snackbar.build = build

function Snackbar:init()
    self.box, self.dimen = build(self.text, self.sub)
    self[1] = self.box
end

function Snackbar:paintTo(bb)
    self.box:paintTo(bb, self.dimen.x, self.dimen.y)
end

function Snackbar:onCloseWidget()
    if current == self then current = nil end
    if self.box then self.box:free() end
end

--- Show a message; replaces the one on screen, if any.
function Snackbar.show(text, timeout, sub)
    if current then UIManager:close(current, "ui", current.dimen) end
    local s = Snackbar:new{ text = text, sub = sub }
    current = s
    UIManager:show(s, "ui", s.dimen)
    UIManager:scheduleIn(timeout or Snackbar.duration(text, sub), function()
        if current == s then UIManager:close(s, "ui", s.dimen) end
    end)
    return s
end

--- Paint straight onto the screen, for when the event loop is about to block.
--- It stays until whatever comes next repaints that part of the screen.
function Snackbar.paintNow(text, sub)
    local ok, err = pcall(function()
        local box, d = build(text, sub)
        box:paintTo(Screen.bb, d.x, d.y)
        Screen:refreshFast(d.x, d.y, d.w, d.h)
        box:free()
    end)
    if not ok then logger.warn("MinimalHome: snackbar:", err) end
end

return Snackbar
