--[[--
The sort dropdown: a bordered card under the sort label.

    SORT BY
    Recently opened              ✓
      Newest first · tap again to reverse
    Recently added
    Title
    Author

Tapping outside the card closes it.
--]]

local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Device = require("device")
local Screen = Device.screen

local C = require("mh/ui/components")
local Model = require("mh/data/model")
local Theme = require("mh/theme")
local px = Theme.px

local SortMenu = InputContainer:extend{
    anchor = nil,     -- Geom of the sort label on screen
    sort_key = nil,
    sort_asc = true,
    col = nil,
    on_pick = nil,    -- function(key, asc)
}

function SortMenu:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events = {
        MHTapOutside = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    local w = px(620)
    local bw = px(4)
    local inner_w = w - 2 * bw
    local list = VerticalGroup:new{ align = "left" }
    table.insert(list, C.space(1, px(12)))
    table.insert(list, C.box(inner_w, px(64), C.text("SORT BY", "sans_bold", 28, self.col.muted),
        { pad_l = px(36), valign = "center" }))
    for _, s in ipairs(Model.SORTS) do
        local checked = s.id == self.sort_key
        local text = VerticalGroup:new{
            align = "left",
            C.text(s.label, checked and "sans_bold" or "sans_medium", 38, self.col.fg),
        }
        if checked then
            table.insert(text, C.space(1, px(4)))
            table.insert(text, C.text(s.dirs[self.sort_asc == false and 2 or 1] .. " · tap again to reverse",
                "sans_medium", 28, self.col.muted))
        end
        local row = OverlapGroup:new{
            dimen = Geom:new{ w = inner_w - 2 * px(36), h = px(120) },
            C.box(text:getSize().w, px(120), text, { valign = "center" }),
        }
        if checked then
            local tick = C.text("✓", "sans_bold", 44, self.col.fg)
            table.insert(row, C.box(tick:getSize().w, px(120), tick,
                { valign = "center", overlap_align = "right" }))
        end
        -- divider inset from the card's edges
        table.insert(list, HorizontalGroup:new{ C.space(px(28), 1), C.hline(inner_w - 2 * px(28), px(3), self.col.line) })
        table.insert(list, C.tappable(C.box(inner_w, px(120), row, { pad_l = px(36) }), function()
            local asc = true
            if checked then asc = self.sort_asc == false end
            self:close()
            if self.on_pick then self.on_pick(s.id, asc) end
        end))
    end
    table.insert(list, C.space(1, px(12)))

    local h = list:getSize().h + 2 * bw
    self.card = C.box(w, h, list, { bg = self.col.bg, border = bw, border_color = self.col.fg,
        radius = px(14), pad = bw })

    -- right-aligned under the label; above it if there is no room below
    local a = self.anchor
    local x = math.max(px(16), a.x + a.w - w)
    local y = a.y + a.h + px(12)
    if y + h > Screen:getHeight() - px(16) then
        y = math.max(px(16), a.y - px(12) - h)
    end
    self.card_rect = Geom:new{ x = x, y = y, w = w, h = h }
    self[1] = self.card
end

function SortMenu:paintTo(bb)
    self.card:paintTo(bb, self.card_rect.x, self.card_rect.y)
end

function SortMenu:onMHTapOutside(_, ges)
    local p, r = ges and ges.pos, self.card_rect
    if p and not (p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h) then
        self:close()
    end
    return true -- the card is modal: nothing behind it reacts
end

-- Turning the device closes the menu and lets the home screen rotate.
function SortMenu:onSetRotationMode(mode)
    self:close()
    if self.on_rotate then self.on_rotate(mode) end
    return true
end

function SortMenu:onClose()
    self:close()
    return true
end

function SortMenu:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "ui", self.card_rect)
end

function SortMenu:show()
    UIManager:show(self, "ui", self.card_rect)
end

function SortMenu:onSuspend() self:close() end

return SortMenu
