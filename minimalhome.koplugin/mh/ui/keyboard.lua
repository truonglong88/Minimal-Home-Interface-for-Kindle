--[[--
Minimal Home's own on-screen keyboard (design: "Keyboard – letters", "Keyboard –
numbers and symbols"), for every text field we open: search, page number, …

* letters:  q–p / a–l / ⇧ z–m ⌫ / ?123 · VI|EN · space · . · Action
* symbols:  1–0 / - / : ; ( ) & @ " # / % * + = _ , ? ! ' ⌫ / ABC · VI|EN · space · . · Action
* numpad:   1 2 3 / 4 5 6 / 7 8 9 / ⌫ 0 Action (numbers only, e.g. page numbers)
* ⇧ makes the next letter a capital.
* VI types Vietnamese with Telex, using KOReader's own Telex engine (it works on
  the text field, so it needs no keyboard of its own); EN types plain letters.
* The black key is the field's action ("Search", "Go", …).

It types into `inputbox`, an object with addChars(text) and delChar() (the same
calls KOReader's keyboard makes), and calls `on_action` for the black key.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Screen = Device.screen

local C = require("mh/ui/components")
local Prefs = require("mh/data/prefs")
local Theme = require("mh/theme")
local px = Theme.px

local Keyboard = InputContainer:extend{
    inputbox = nil,
    action = "Search",
    on_action = nil,
    mode = "alpha",      -- "alpha" | "symbols"
    allow_vi = true,     -- false for numbers-only fields
}

Keyboard.HEIGHT = 600 -- design px
Keyboard.ROWS = {
    alpha = {
        { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
        { "a", "s", "d", "f", "g", "h", "j", "k", "l", indent = 58 },
        { "⇧", "z", "x", "c", "v", "b", "n", "m", "⌫" },
        { "?123", "lang", "space", ".", "action" },
    },
    symbols = {
        { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
        { "-", "/", ":", ";", "(", ")", "&", "@", "\"", "#" },
        { "%", "*", "+", "=", "_", ",", "?", "!", "'", "⌫" },
        { "ABC", "lang", "space", ".", "action" },
    },
    -- numbers only (page numbers): three big columns, the action key bottom right
    numpad = {
        { "1", "2", "3" },
        { "4", "5", "6" },
        { "7", "8", "9" },
        { "⌫", "0", "action" },
    },
}
local WIDTH = { ["⇧"] = 1.5, ["⌫"] = 1.5, ["?123"] = 1.5, ABC = 1.5, lang = 1.3, space = 4.2, action = 2.2 }
local FN = { ["⇧"] = true, ["⌫"] = true, ["?123"] = true, ABC = true, lang = true }

function Keyboard:init()
    self.col = Theme.boldColors(false)
    local W, H = Screen:getWidth(), Screen:getHeight()
    local h = px(Keyboard.HEIGHT)
    self.dimen = Geom:new{ x = 0, y = H - h, w = W, h = h }
    self.shift = false
    self.lang = self.allow_vi and (Prefs.get("keyboard_lang") or "EN") or "EN"
    self.ges_events = {
        MHKey = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        MHHoldKey = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self:applyLang()
    self:layoutKeys()
end

-- Vietnamese Telex -------------------------------------------------------------------------

function Keyboard:applyLang()
    if self.unwrap then
        pcall(self.unwrap)
        self.unwrap = nil
    end
    if self.lang ~= "VI" or not self.inputbox then return end
    local ok, err = pcall(function()
        local vi = require("ui/data/keyboardlayouts/vi_keyboard")
        if vi.wrapInputBox then self.unwrap = vi.wrapInputBox(self.inputbox) end
    end)
    if not ok then
        logger.warn("MinimalHome: Telex not available:", err)
        self.lang = "EN"
    end
end

-- Layout -----------------------------------------------------------------------------------

function Keyboard:labelFor(k)
    if k == "lang" then return self.lang end
    if k == "space" then return self.lang == "VI" and "dấu cách" or "space" end
    if k == "action" then return self.action end
    if self.mode == "alpha" and self.shift and #k == 1 then return k:upper() end
    return k
end

--- Work out where every key is (screen coordinates).
function Keyboard:layoutKeys()
    local W = self.dimen.w
    local pad_t, pad_h, gap_v, gap_h = px(24), px(20), px(14), px(12)
    local key_h = px(112)
    self.keys = {}
    local y = self.dimen.y + px(3) + pad_t
    for _, row in ipairs(Keyboard.ROWS[self.mode]) do
        local indent = px(row.indent or 0)
        local units = 0
        local function width(k) return self.mode == "numpad" and 1 or (WIDTH[k] or 1) end
        for _, k in ipairs(row) do units = units + width(k) end
        local avail = W - 2 * pad_h - 2 * indent - (#row - 1) * gap_h
        local unit = avail / units
        local x = pad_h + indent
        for _, k in ipairs(row) do
            local w = math.floor(unit * width(k) + 0.5)
            self.keys[#self.keys + 1] = { key = k, rect = Geom:new{ x = math.floor(x), y = y, w = w, h = key_h } }
            x = x + w + gap_h
        end
        y = y + key_h + gap_v
    end
end

function Keyboard:paintTo(bb)
    local d = self.dimen
    bb:paintRect(d.x, d.y, d.w, d.h, Blitbuffer.gray(0.07)) -- #EDEDED
    bb:paintRect(d.x, d.y, d.w, px(3), self.col.line)
    for _, k in ipairs(self.keys) do
        local r = k.rect
        local key = k.key
        local bg, fg, border = self.col.bg, self.col.fg, self.col.line
        if key == "action" or (key == "⇧" and self.shift) then
            bg, fg, border = self.col.fg, self.col.bg, self.col.fg
        elseif FN[key] then
            bg = self.col.fill or Blitbuffer.gray(0.15)
        end
        if k.pressed then bg, fg = fg, bg end
        local label = self:labelFor(key)
        local kind, size = "sans_medium", 44
        if FN[key] or key == "space" then kind, size = "sans_bold", 32 end
        if key == "action" then kind, size = "sans_bold", 34 end
        if self.mode == "numpad" and key:match("^%d$") then kind, size = "sans_bold", 52 end
        local t = C.text(label, kind, size, fg, r.w - px(8))
        local box = C.box(r.w, r.h, t, { bg = bg, border = px(3), border_color = border, radius = px(12),
            halign = "center", valign = "center" })
        box:paintTo(bb, r.x, r.y)
        box:free()
    end
end

-- Input ------------------------------------------------------------------------------------

function Keyboard:keyAt(pos)
    if not pos then return nil end
    for _, k in ipairs(self.keys) do
        local r = k.rect
        -- the gaps between keys count for the nearest key
        if pos.x >= r.x - px(6) and pos.x < r.x + r.w + px(6) and pos.y >= r.y - px(7) and pos.y < r.y + r.h + px(7) then
            return k
        end
    end
end

function Keyboard:redraw()
    UIManager:setDirty(self, "ui", self.dimen)
end

--- A short flash of the key that was hit, so a tap is seen at once on e-ink.
function Keyboard:flash(k)
    k.pressed = true
    UIManager:setDirty(self, "fast", k.rect)
    UIManager:scheduleIn(0.12, function()
        k.pressed = nil
        if not self.closed then UIManager:setDirty(self, "ui", k.rect) end
    end)
end

function Keyboard:press(key)
    local box = self.inputbox
    if key == "⇧" then
        self.shift = not self.shift
        self:redraw()
    elseif key == "⌫" then
        if box then box:delChar() end
    elseif key == "?123" or key == "ABC" then
        self.mode = key == "?123" and "symbols" or "alpha"
        self.shift = false
        self:layoutKeys()
        self:redraw()
    elseif key == "lang" then
        if not self.allow_vi then return end
        self.lang = self.lang == "VI" and "EN" or "VI"
        Prefs.set("keyboard_lang", self.lang)
        self:applyLang()
        self:redraw()
    elseif key == "action" then
        if self.on_action then self.on_action() elseif box then box:addChars("\n") end
    else
        local ch = key == "space" and " " or self:labelFor(key)
        if box then box:addChars(ch) end
        if self.shift then
            self.shift = false
            self:redraw()
        end
    end
end

function Keyboard:onMHKey(_, ges)
    local k = self:keyAt(ges and ges.pos)
    if k then
        self:flash(k)
        self:press(k.key)
    end
    return true
end

--- Hold ⌫ to clear the field.
function Keyboard:onMHHoldKey(_, ges)
    local k = self:keyAt(ges and ges.pos)
    if k and k.key == "⌫" and self.inputbox and self.inputbox.delToStartOfLine then
        self.inputbox:delToStartOfLine()
    end
    return true
end

function Keyboard:onClose()
    local box = self.inputbox
    UIManager:close(self)
    if box and box.onCloseKeyboard then box:onCloseKeyboard() end
    return true
end

function Keyboard:onCloseWidget()
    self.closed = true
    if self.unwrap then pcall(self.unwrap); self.unwrap = nil end
end

return Keyboard
