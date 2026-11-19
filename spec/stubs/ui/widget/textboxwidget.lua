local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local BB = require("ffi/blitbuffer")
local TM = require("text_measure")
local TB = Widget:extend{ text = nil, face = nil, width = 400, height = nil, line_height = 0.3,
    fgcolor = nil, bgcolor = nil, alignment = "left", height_overflow_show_ellipsis = false }
function TB:init()
    assert(self.face and self.width, "TextBoxWidget needs face and width")
    local lines, cur, cur_w = {}, {}, 0
    for word in tostring(self.text or ""):gmatch("%S+") do
        local ww = TM.width(self.face, word .. " ")
        if cur_w + ww > self.width and #cur > 0 then
            lines[#lines + 1] = table.concat(cur, " "); cur, cur_w = {}, 0
        end
        cur[#cur + 1] = word; cur_w = cur_w + ww
    end
    if #cur > 0 then lines[#lines + 1] = table.concat(cur, " ") end
    if #lines == 0 then lines = { "" } end
    self.line_height_px = math.ceil(self.face.size * (1 + self.line_height))
    if self.height then
        local max_lines = math.max(1, math.floor(self.height / self.line_height_px))
        if #lines > max_lines then
            local keep = {}
            for i = 1, max_lines do keep[i] = lines[i] end
            if self.height_overflow_show_ellipsis then keep[max_lines] = TM.truncate(self.face, keep[max_lines] .. " …", self.width) end
            lines = keep
        end
        self.lines_per_page = max_lines
    end
    self.vertical_string_list = lines
    self._lines = lines
end
function TB:getLineHeight() return self.line_height_px end
function TB:getSize() return Geom:new{ w = self.width, h = self.height or (#self._lines * self.line_height_px) } end
function TB:paintTo(bb, x, y)
    for i, l in ipairs(self._lines) do
        BB._emit(bb, { "text", x, y + (i - 1) * self.line_height_px, l, self.face.path, self.face.size,
            self.fgcolor and self.fgcolor.v or 1, self.alignment, self.width })
    end
end
function TB:free() end
return TB
