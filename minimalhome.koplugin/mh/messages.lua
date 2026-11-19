--[[--
KOReader's own messages and yes / no questions, in our look.

* Messages ("Connecting to Wi-Fi…", errors, …): the snackbar, a third of the
  way up the screen, no (i) icon. Long ones wrap (up to six lines). Tap to
  close, timeout and being closed by the code that opened them all work as
  before; only the look changes.
* "Book can't be opened" messages read "Couldn't open this book".
* Yes / no questions (ConfirmBox with two buttons): our confirm card.
--]]

local logger = require("logger")

local M = {}

M.MAX_CHARS = 400

--- Short enough for a snackbar?
function M.fits(text)
    if type(text) ~= "string" or text == "" or #text > M.MAX_CHARS then return false end
    local _, lines = text:gsub("\n", "")
    return lines <= 5
end

-- KOReader's messages when a book can't be opened.
M.OPEN_FAILED = { "is not supported", "No reader engine for this file", "does not exist%.", "invalid document" }

function M.rewrite(text)
    for _, pat in ipairs(M.OPEN_FAILED) do
        if text:find(pat) then return "Couldn’t open this book" end
    end
    if text:find("^Opening file '") then return "Opening book…" end
    return text
end

--- Painted in place of the message box.
local Holder = {}
Holder.__index = Holder
function Holder:paintTo(bb) self.box:paintTo(bb, self.dimen.x, self.dimen.y) end
function Holder:getSize() return self.dimen end
function Holder:free() if self.box then self.box:free() end end
function Holder.handleEvent() return false end

local function restyle(msg)
    local Snackbar = require("mh/ui/snackbar")
    local text = M.rewrite(msg.text)
    local title, sub = text:match("^([^\n]*)\n+(.*)$")
    local box, d = Snackbar.build(title or text, sub)
    if msg[1] and msg[1].free then msg[1]:free() end
    local holder = setmetatable({ box = box, dimen = d }, Holder)
    msg.movable = holder
    msg[1] = holder
end

--- Our card in place of ConfirmBox's dialog; its buttons do what KOReader's do.
local function restyleConfirm(box)
    local UIManager = require("ui/uimanager")
    local Geom = require("ui/geometry")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local Confirm = require("mh/ui/confirm")
    local title, text = box.text:match("^([^\n]+)\n+(.+)$")
    if not title then
        if #box.text <= 70 then title = box.text else text = box.text end
    end
    local card, rect = Confirm.card({ title = title, text = text, ok_text = box.ok_text,
        cancel_text = box.cancel_text, no_ok = box.no_ok_button },
        function()
            box.cancel_callback()
            UIManager:close(box)
        end,
        function()
            box.ok_callback()
            if not box.keep_dialog_open then UIManager:close(box) end
        end)
    card.overlap_offset = { rect.x, rect.y }
    if box[1] and box[1].free then box[1]:free() end
    local Screen = require("device").screen
    box[1] = OverlapGroup:new{ dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() }, card }
    box.movable = { dimen = rect }
end

function M.install()
    if M.installed then return end
    local ok, err = pcall(function()
        local InfoMessage = require("ui/widget/infomessage")
        local orig_init = InfoMessage.init
        M.orig_init = orig_init
        InfoMessage.init = function(self, ...)
            if not self.image then self.show_icon = false end
            orig_init(self, ...)
            if M.enabled() and not self.image and not self.height and M.fits(self.text) then
                local ok2, err2 = pcall(restyle, self)
                if not ok2 then logger.warn("MinimalHome: message look:", err2) end
            end
        end
    end)
    if not ok then logger.warn("MinimalHome: messages:", err) end
    local ok3, err3 = pcall(function()
        local ConfirmBox = require("ui/widget/confirmbox")
        local orig_init = ConfirmBox.init
        M.orig_confirm_init = orig_init
        ConfirmBox.init = function(self, ...)
            orig_init(self, ...)
            if M.enabled() and not self.other_buttons and not self._added_widgets
                    and type(self.text) == "string" and #self.text <= M.MAX_CHARS then
                local ok2, err2 = pcall(restyleConfirm, self)
                if not ok2 then logger.warn("MinimalHome: question look:", err2) end
            end
        end
    end)
    if not ok3 then logger.warn("MinimalHome: questions:", err3) end
    M.installed = true
end

function M.enabled()
    local Prefs = require("mh/data/prefs")
    return Prefs.get("enabled") or Prefs.get("reader_style")
end

return M
