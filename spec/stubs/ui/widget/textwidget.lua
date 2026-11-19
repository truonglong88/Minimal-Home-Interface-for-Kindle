local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local BB = require("ffi/blitbuffer")
local TM = require("text_measure")
local TextWidget = Widget:extend{ text = nil, face = nil, fgcolor = nil, max_width = nil, padding = 0 }
function TextWidget:init()
    assert(self.face, "TextWidget needs a face")
    self.shown = TM.truncate(self.face, tostring(self.text or ""), self.max_width)
    self._w = TM.width(self.face, self.shown)
    self._h = TM.lineHeight(self.face)
end
function TextWidget:getSize() return Geom:new{ w = self._w, h = self._h } end
function TextWidget:paintTo(bb, x, y)
    BB._emit(bb, { "text", x, y, self.shown, self.face.path, self.face.size, self.fgcolor and self.fgcolor.v or 1 })
end
function TextWidget:free() end
function TextWidget:isTruncated() return false end
function TextWidget:getWidth() return self._w end
function TextWidget:setText(t) self.text = t end
function TextWidget:getBaseline() return math.floor(self._h * 0.8) end
return TextWidget
