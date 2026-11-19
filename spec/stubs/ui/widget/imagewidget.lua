local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local BB = require("ffi/blitbuffer")
local I = Widget:extend{ image = nil, width = 0, height = 0 }
function I:getSize() return Geom:new{ w = self.width, h = self.height } end
function I:paintTo(bb, x, y) BB._emit(bb, { "image", x, y, self.width, self.height, self.image and self.image.name or "" }) end
function I:free() end
return I
