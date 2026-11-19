--[[--
Go to page (design: "Reading › Go to page"): a card over the page with the page
number, "of N", where you are now, Cancel / Go — and our number keypad below it.
--]]

local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen

local C = require("mh/ui/components")
local Theme = require("mh/theme")
local px = Theme.px

local GoToPage = InputContainer:extend{
    ui = nil,
    value = "",
}

function GoToPage:init()
    self.col = Theme.boldColors(false)
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.total, self.page = 1, 1
    pcall(function() self.total = self.ui.document:getPageCount() end)
    pcall(function() self.page = self.ui:getCurrentPage() end)
    self.chapter = nil
    pcall(function()
        local t = self.ui.toc:getTocTitleByPage(self.page)
        if t and t ~= "" then self.chapter = t end
    end)
    local range = function() return self.dimen end
    self.ges_events = { MHTapOutside = { GestureRange:new{ ges = "tap", range = range } } }
    self:makeInputBox()
    self:build()
end

-- Digits only; the keyboard types into this.
function GoToPage:makeInputBox()
    local dialog = self
    local box = {}
    box.addChars = function(_, chars)
        if chars == "\n" then UIManager:nextTick(function() dialog:go() end) return end
        local digits = chars:gsub("%D", "")
        if digits == "" or #dialog.value >= 6 then return end
        dialog.value = dialog.value .. digits
        dialog:rebuild()
    end
    box.delChar = function()
        dialog.value = dialog.value:sub(1, -2)
        dialog:rebuild()
    end
    box.delToStartOfLine = function()
        dialog.value = ""
        dialog:rebuild()
    end
    box.onCloseKeyboard = function() dialog:close() end
    self.inputbox = box
end

function GoToPage:build()
    local W = self.dimen.w
    local margin = px(Theme.margin_h)
    local card_w = W - 2 * margin
    local inner = card_w - 2 * px(56)
    local field_text = self.value ~= "" and self.value or ""
    local num = C.text(field_text, "sans_bold", 64, self.col.fg)
    local caret = C.Rect:new{ w = px(4), h = px(64), color = self.col.fg }
    local of = C.text("of " .. self.total, "sans_medium", 36, self.col.muted)
    local field_row = OverlapGroup:new{ dimen = Geom:new{ w = inner - px(64), h = px(128) },
        C.box(inner - px(64), px(128), HorizontalGroup:new{ align = "center", num, C.space(px(6), 1), caret },
            { valign = "center" }) }
    local of_box = C.box(of:getSize().w, px(128), of, { valign = "center" })
    of_box.overlap_align = "right"
    table.insert(field_row, of_box)
    local field = C.box(inner, px(136), field_row, { border = px(4), border_color = self.col.fg, radius = px(10),
        pad_l = px(32), pad_t = px(4) })
    local here = "You’re on page " .. self.page .. (self.chapter and (" · " .. self.chapter) or "")
    local half = math.floor((inner - px(28)) / 2)
    local cancel = C.tappable(C.box(half, px(116), C.text("Cancel", "sans_bold", 38, self.col.fg),
        { border = px(4), border_color = self.col.fg, radius = px(10), halign = "center", valign = "center" }),
        function() UIManager:nextTick(function() self:close() end) end)
    local go = C.tappable(C.box(half, px(116), C.text("Go", "sans_bold", 38, self.col.bg),
        { bg = self.col.fg, radius = px(10), halign = "center", valign = "center" }),
        function() UIManager:nextTick(function() self:go() end) end)
    local content = VerticalGroup:new{
        align = "left",
        C.text("Go to page", "serif_bold", 56, self.col.fg, inner),
        C.space(1, px(28)), field,
        C.space(1, px(28)), C.text(here, "sans_medium", 32, self.col.muted, inner),
        C.space(1, px(36)), HorizontalGroup:new{ align = "center", cancel, C.space(px(28), 1), go },
    }
    local card_h = content:getSize().h + 2 * px(48)
    self.card_rect = Geom:new{ x = margin, y = px(300), w = card_w, h = card_h }
    self.card = C.box(card_w, card_h, content, { bg = self.col.bg, border = px(4), border_color = self.col.fg,
        radius = px(20), pad_l = px(56), pad_t = px(48) })
    self.card.overlap_offset = { margin, px(300) }
    self[1] = OverlapGroup:new{ dimen = Geom:new{ w = W, h = self.dimen.h }, self.card }
end

function GoToPage:rebuild()
    if self.closed then return end
    if self[1] then self[1]:free() end
    self:build()
    UIManager:setDirty(self, "ui", self.card_rect)
end

function GoToPage:paintTo(bb, x, y)
    -- only the card: the page stays visible around it
    self.card:paintTo(bb, x + self.card_rect.x, y + self.card_rect.y)
end

function GoToPage:go()
    local n = tonumber(self.value)
    self:close()
    if not n then return end
    n = math.max(1, math.min(self.total, n))
    self.ui:handleEvent(Event:new("GotoPage", n))
end

function GoToPage:onMHTapOutside(_, ges)
    local p, r = ges and ges.pos, self.card_rect
    local kb = self.keyboard and self.keyboard.dimen
    local inside = p and p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h
    local on_kb = p and kb and p.y >= kb.y
    if not inside and not on_kb then self:close() end
    return true
end

function GoToPage:show()
    UIManager:show(self, "ui")
    self.keyboard = require("mh/ui/keyboard"):new{
        inputbox = self.inputbox, mode = "numpad", allow_vi = false, action = "Go",
        on_action = function() UIManager:nextTick(function() self:go() end) end,
    }
    -- taps on the card still reach us while the keyboard is on top
    self.is_always_active = true
    UIManager:show(self.keyboard)
    return self
end

function GoToPage:close()
    if self.closed then return end
    self.closed = true
    self.is_always_active = nil
    if self.keyboard then UIManager:close(self.keyboard) end
    UIManager:close(self, "ui")
end

function GoToPage:onSuspend() self:close() end

function GoToPage:onClose()
    self:close()
    return true
end

function GoToPage:onCloseWidget()
    self.closed = true
    if self[1] then self[1]:free() end
end

return GoToPage
