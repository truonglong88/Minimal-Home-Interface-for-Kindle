--[[--
Confirm dialog (design: "Confirm dialog – any yes / no question"): a card with
a title, a line or two of explanation, Cancel and a black action button.

    Confirm.show{ title = "Delete this book?", text = "…", ok_text = "Delete",
                  ok_callback = function() … end }

`Confirm.card(opts, on_cancel, on_ok)` builds just the card; KOReader's own
yes / no questions are drawn with it too (mh/messages).
--]]

local Device = require("device")
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

local Confirm = InputContainer:extend{
    title = nil,
    text = nil,
    ok_text = "OK",
    cancel_text = "Cancel",
    ok_callback = nil,
    cancel_callback = nil,
}

--- The card and where it goes on screen.
function Confirm.card(opts, on_cancel, on_ok)
    local col = Theme.boldColors(false)
    local W = Screen:getWidth()
    local margin = px(Theme.margin_h)
    local card_w = W - 2 * margin
    local inner = card_w - 2 * px(56)
    local content = VerticalGroup:new{ align = "left" }
    if opts.title and opts.title ~= "" then
        table.insert(content, C.textbox(opts.title, "serif_bold", 56, col.fg, inner, 3, 0.15, "left"))
    end
    if opts.text and opts.text ~= "" then
        if #content > 0 then table.insert(content, C.space(1, px(24))) end
        local color = #content > 0 and col.muted or col.fg
        table.insert(content, C.textbox(opts.text, "sans_medium", 34, color, inner, 8, 0.45, "left"))
    end
    table.insert(content, C.space(1, px(44)))
    local buttons = HorizontalGroup:new{ align = "center" }
    local ok_text = opts.ok_text or "OK"
    if opts.no_ok then
        table.insert(buttons, C.tappable(C.box(inner, px(116), C.text(opts.cancel_text or "Cancel", "sans_bold", 38, col.fg),
            { border = px(4), border_color = col.fg, radius = px(10), halign = "center", valign = "center" }), on_cancel))
    else
        local half = math.floor((inner - px(28)) / 2)
        table.insert(buttons, C.tappable(C.box(half, px(116), C.text(opts.cancel_text or "Cancel", "sans_bold", 38, col.fg, half - px(20)),
            { border = px(4), border_color = col.fg, radius = px(10), halign = "center", valign = "center" }), on_cancel))
        table.insert(buttons, C.space(px(28), 1))
        table.insert(buttons, C.tappable(C.box(half, px(116), C.text(ok_text, "sans_bold", 38, col.bg, half - px(20)),
            { bg = col.fg, border = px(4), border_color = col.fg, radius = px(10), halign = "center", valign = "center" }), on_ok))
    end
    table.insert(content, buttons)
    local card_h = content:getSize().h + 2 * px(48)
    local y = math.max(px(200), math.floor((Screen:getHeight() - card_h) / 2) - px(120))
    local card = C.box(card_w, card_h, content, { bg = col.bg, border = px(4), border_color = col.fg,
        radius = px(20), pad_l = px(56), pad_t = px(48) })
    return card, Geom:new{ x = margin, y = y, w = card_w, h = card_h }
end

function Confirm:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local range = function() return self.dimen end
    self.ges_events = { MHTapOutside = { GestureRange:new{ ges = "tap", range = range } } }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    local card, rect = Confirm.card(self,
        function() UIManager:nextTick(function() self:answer(false) end) end,
        function() UIManager:nextTick(function() self:answer(true) end) end)
    self.card, self.card_rect = card, rect
    card.overlap_offset = { rect.x, rect.y }
    self[1] = OverlapGroup:new{ dimen = Geom:new{ w = self.dimen.w, h = self.dimen.h }, card }
end

function Confirm:paintTo(bb, x, y)
    self.card:paintTo(bb, x + self.card_rect.x, y + self.card_rect.y)
end

function Confirm:answer(ok)
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "ui", self.card_rect)
    local cb = ok and self.ok_callback or self.cancel_callback
    if cb then cb() end
end

function Confirm:onMHTapOutside(_, ges)
    local p, r = ges and ges.pos, self.card_rect
    if p and not (p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h) then self:answer(false) end
    return true
end

function Confirm:onSuspend() self:answer(false) end

function Confirm:onClose()
    self:answer(false)
    return true
end

function Confirm:onCloseWidget()
    self.closed = true
    if self[1] then self[1]:free() end
end

function Confirm.show(opts)
    local c = Confirm:new(opts)
    UIManager:show(c, "ui", c.card_rect)
    return c
end

return Confirm
