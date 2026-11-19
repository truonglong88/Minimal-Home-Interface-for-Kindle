--[[--
A window onto a tall column of blocks, scrolled by a pixel offset.

Only the blocks that intersect the window are built and painted, so a library
with hundreds of books costs no more than one screen. Blocks that scroll far
away are freed (their covers can be large).

The column is painted into an off-screen buffer at real screen coordinates and
only the window is copied to the screen; this keeps tap areas correct and
clips blocks that are cut by the window's top or bottom edge.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Viewport = WidgetContainer:extend{
    x = 0, y = 0,          -- window position on screen
    w = 0, h = 0,          -- window size
    content_x = 0,         -- left edge of the blocks on screen
    blocks = nil,          -- { { y = <offset in column>, h = <height>, build = fn } ... }
    scroll = 0,
}

function Viewport:init()
    self.blocks = self.blocks or {}
    self.dimen = Geom:new{ x = self.x, y = self.y, w = self.w, h = self.h }
end

function Viewport:getSize()
    return Geom:new{ w = self.w, h = self.h }
end

function Viewport:totalHeight()
    local last = self.blocks[#self.blocks]
    return last and (last.y + last.h) or 0
end

function Viewport:maxScroll()
    return math.max(0, self:totalHeight() - self.h)
end

--- Rebuild the list of visible children for the current scroll offset.
function Viewport:update()
    -- children are the widgets currently visible: only they receive taps
    for i = #self, 1, -1 do self[i] = nil end
    local top, bottom = self.scroll, self.scroll + self.h
    local keep_top, keep_bottom = top - 2 * self.h, bottom + 2 * self.h
    for _, b in ipairs(self.blocks) do
        local visible = b.y + b.h > top and b.y < bottom
        if visible then
            if not b.widget then b.widget = b.build() end
            table.insert(self, b.widget)
        elseif b.widget and (b.y + b.h < keep_top or b.y > keep_bottom) then
            b.widget:free()
            b.widget = nil
        end
    end
end

function Viewport:scrollTo(offset)
    offset = math.max(0, math.min(self:maxScroll(), math.floor(offset + 0.5)))
    if offset == self.scroll then return false end
    self.scroll = offset
    self:update()
    return true
end

function Viewport:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local screen_w, screen_h = bb:getWidth(), bb:getHeight()
    if not self._bb or self._bb:getWidth() ~= screen_w or self._bb:getHeight() ~= screen_h then
        if self._bb then self._bb:free() end
        self._bb = Blitbuffer.new(screen_w, screen_h, bb:getType())
    end
    self._bb:fill(self.bg or Blitbuffer.COLOR_WHITE)
    for _, b in ipairs(self.blocks) do
        if b.widget and b.y + b.h > self.scroll and b.y < self.scroll + self.h then
            b.widget:paintTo(self._bb, self.content_x, y + b.y - self.scroll)
        end
    end
    bb:blitFrom(self._bb, x, y, x, y, self.w, self.h)
end

function Viewport:free()
    for _, b in ipairs(self.blocks) do
        if b.widget then b.widget:free() b.widget = nil end
    end
    for i = #self, 1, -1 do self[i] = nil end
    if self._bb then self._bb:free() self._bb = nil end
end

return Viewport
