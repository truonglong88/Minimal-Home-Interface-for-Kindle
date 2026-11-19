local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local BB = require("ffi/blitbuffer")
local I = Widget:extend{ icon = nil, width = 0, height = 0 }
function I:getSize() return Geom:new{ w = self.width, h = self.height } end
function I:paintTo(bb, x, y) BB._emit(bb, { "icon", x, y, self.width, self.height, self.icon }) end
function I:free() end
return I
