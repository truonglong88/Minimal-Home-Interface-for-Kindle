--[[--
Wi-Fi password card (design: "Settings › Wi-Fi – new network: password"):
the network's name, the password shown as typed (Hide to mask it), Cancel /
Join, and our keyboard below.
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

local WifiPassword = InputContainer:extend{
    network = nil,     -- { ssid = …, flags = … }
    on_join = nil,     -- function(password)
    on_cancel = nil,
    value = "",
}

local function chars(s)
    local t = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = ch end
    return t
end

function WifiPassword:init()
    self.col = Theme.boldColors(false)
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.hidden = false
    local range = function() return self.dimen end
    self.ges_events = { MHTapOutside = { GestureRange:new{ ges = "tap", range = range } } }
    self:makeInputBox()
    self:build()
end

function WifiPassword:makeInputBox()
    local card = self
    local box = {}
    box.addChars = function(_, s)
        if s == "\n" then UIManager:nextTick(function() card:join() end) return end
        card.value = card.value .. s
        card:rebuild()
    end
    box.delChar = function()
        local t = chars(card.value)
        table.remove(t)
        card.value = table.concat(t)
        card:rebuild()
    end
    box.delToStartOfLine = function() card.value = ""; card:rebuild() end
    box.onCloseKeyboard = function() card:cancel() end
    self.inputbox = box
end

function WifiPassword:build()
    local col = self.col
    local W = self.dimen.w
    local margin = px(Theme.margin_h)
    local card_w = W - 2 * margin
    local inner = card_w - 2 * px(56)
    local shown = self.hidden and string.rep("•", #chars(self.value)) or self.value
    local field_text = C.text(shown, "sans_bold", self.hidden and 52 or 48, col.fg, inner - px(260))
    local caret = C.Rect:new{ w = px(4), h = px(56), color = col.fg }
    local toggle_t = C.text(self.hidden and "Show" or "Hide", "sans_bold", 32, col.fg)
    local toggle = C.tappable(C.box(toggle_t:getSize().w + px(32), px(112), toggle_t, { halign = "center", valign = "center" }),
        function() UIManager:nextTick(function() self.hidden = not self.hidden; self:rebuild() end) end)
    toggle.overlap_align = "right"
    local field_row = OverlapGroup:new{ dimen = Geom:new{ w = inner - px(48), h = px(112) },
        C.box(inner - px(200), px(112), HorizontalGroup:new{ align = "center", field_text, C.space(px(6), 1), caret },
            { valign = "center" }),
        toggle }
    local field = C.box(inner, px(120), field_row, { border = px(4), border_color = col.fg, radius = px(10),
        pad_l = px(32), pad_t = px(4) })
    local half = math.floor((inner - px(28)) / 2)
    local cancel = C.tappable(C.box(half, px(116), C.text("Cancel", "sans_bold", 38, col.fg),
        { border = px(4), border_color = col.fg, radius = px(10), halign = "center", valign = "center" }),
        function() UIManager:nextTick(function() self:cancel() end) end)
    local join = C.tappable(C.box(half, px(116), C.text("Join", "sans_bold", 38, col.bg),
        { bg = col.fg, radius = px(10), halign = "center", valign = "center" }),
        function() UIManager:nextTick(function() self:join() end) end)
    local content = VerticalGroup:new{
        align = "left",
        C.text("Wi-Fi password", "serif_bold", 56, col.fg, inner),
        C.space(1, px(28)), C.text("Network: " .. (self.network and self.network.ssid or ""), "sans_medium", 32, col.muted, inner),
        C.space(1, px(28)), field,
        C.space(1, px(36)), HorizontalGroup:new{ align = "center", cancel, C.space(px(28), 1), join },
    }
    local card_h = content:getSize().h + 2 * px(48)
    self.card_rect = Geom:new{ x = margin, y = px(260), w = card_w, h = card_h }
    self.card = C.box(card_w, card_h, content, { bg = col.bg, border = px(4), border_color = col.fg,
        radius = px(20), pad_l = px(56), pad_t = px(48) })
    self.card.overlap_offset = { margin, px(260) }
    self[1] = OverlapGroup:new{ dimen = Geom:new{ w = W, h = self.dimen.h }, self.card }
end

function WifiPassword:rebuild()
    if self.closed then return end
    if self[1] then self[1]:free() end
    self:build()
    UIManager:setDirty(self, "ui", self.card_rect)
end

function WifiPassword:paintTo(bb, x, y)
    self.card:paintTo(bb, x + self.card_rect.x, y + self.card_rect.y)
end

function WifiPassword:join()
    if self.closed then return end
    if self.value == "" then return end -- a locked network needs one
    local password = self.value
    self:close()
    if self.on_join then self.on_join(password) end
end

function WifiPassword:cancel()
    if self.closed then return end
    self:close()
    if self.on_cancel then self.on_cancel() end
end

function WifiPassword:onMHTapOutside(_, ges)
    local p, r = ges and ges.pos, self.card_rect
    local kb = self.keyboard and self.keyboard.dimen
    local inside = p and p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h
    local on_kb = p and kb and p.y >= kb.y
    if not inside and not on_kb then self:cancel() end
    return true
end

function WifiPassword:show()
    UIManager:show(self, "ui")
    self.keyboard = require("mh/ui/keyboard"):new{
        inputbox = self.inputbox, mode = "alpha", allow_vi = false, action = "Join",
        on_action = function() UIManager:nextTick(function() self:join() end) end,
    }
    self.is_always_active = true
    UIManager:show(self.keyboard)
    return self
end

function WifiPassword:close()
    if self.closed then return end
    self.closed = true
    self.is_always_active = nil
    if self.keyboard then UIManager:close(self.keyboard) end
    UIManager:close(self, "ui")
end

function WifiPassword:onSuspend() self:close() end

function WifiPassword:onClose()
    self:cancel()
    return true
end

function WifiPassword:onCloseWidget()
    self.closed = true
    if self[1] then self[1]:free() end
end

return WifiPassword
