--[[--
Search screen (design: Search – keyboard just opened / typing / no matches /
results / scrolled).

* Fixed on top: status bar, ‹ back, search field (× clears it).
* Below: recent searches (empty field), matches as you type (up to 4, with
  "See all N results"), all matches after Search, or "No matches".
* Minimal Home's keyboard (mh/ui/keyboard): letters / numbers, VI Telex or EN.
  Search (Enter) lowers it; tapping the field brings it back.
* Titles and authors, accents optional (mh/data/search).
--]]

local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local Screen = Device.screen

local C = require("mh/ui/components")
local Prefs = require("mh/data/prefs")
local Search = require("mh/data/search")
local Theme = require("mh/theme")
local Viewport = require("mh/ui/viewport")

local px = Theme.px

local SearchScreen = InputContainer:extend{
    books = nil,      -- the library (Home's list)
    cover_for = nil,  -- function(book, w, h, opts) -> cover widget
    on_open = nil,    -- function(path): open a book
    on_close = nil,
    query = "",
}

SearchScreen.LIVE_MAX = 4
SearchScreen.FLICK = 1.5
SearchScreen.RECENT_MAX = 3

function SearchScreen:init()
    self.covers_fullscreen = true
    self.col = Theme.boldColors(false)
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.query = self.query or ""
    self.submitted = false
    self.matches = {}
    local range = function() return self.dimen end
    self.ges_events = {
        MHTap = { GestureRange:new{ ges = "tap", range = range } },
        MHSwipe = { GestureRange:new{ ges = "swipe", range = range } },
        MHPan = { GestureRange:new{ ges = "pan", range = range } },
        MHPanRelease = { GestureRange:new{ ges = "pan_release", range = range } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self:makeInputBox()
    self:layout()
end

function SearchScreen:contentWidth()
    return self.dimen.w - 2 * px(Theme.margin_h)
end

-- The keyboard types into this small object (KOReader's VirtualKeyboard calls
-- these methods; the Vietnamese Telex layout wraps some of them).
function SearchScreen:makeInputBox()
    local screen = self
    local box = { parent = self }
    box.addChars = function(_, chars)
        if chars == "\n" then UIManager:nextTick(function() screen:submit() end) return end
        screen:setQuery(screen.query .. chars)
    end
    box.delChar = function()
        local ch = Search.chars(screen.query)
        table.remove(ch)
        screen:setQuery(table.concat(ch))
    end
    box.delWord = function()
        screen:setQuery((screen.query:gsub("%s*[^%s]*%s*$", "")))
    end
    box.delToStartOfLine = function() screen:setQuery("") end
    box.clear = function() screen:setQuery("") end
    local noop = function() end
    for _, name in ipairs({ "leftChar", "rightChar", "upLine", "downLine", "scrollUp", "scrollDown",
            "goToStartOfLine", "goToEndOfLine", "unfocus", "onTapTextBox", "onHoldTextBox", "onSwipeTextBox",
            "onSwitchingKeyboardLayout" }) do
        box[name] = noop
    end
    box.onCloseKeyboard = function() screen:keyboardGone() end
    -- the keyboard's own Back key, and a layout with a different height
    function self.onKeyboardClosed() screen:keyboardGone() end
    function self.onKeyboardHeightChanged() screen:refresh() end
    self.inputbox = box
end

-- Keyboard -------------------------------------------------------------------------------

function SearchScreen:keyboardHeight()
    local kb = self.keyboard
    return (kb and self.kb_visible and kb.dimen and kb.dimen.h) or 0
end

function SearchScreen:showKeyboard()
    if self.closed or self.kb_visible then return end
    -- a fresh keyboard each time (it starts on letters, Shift off)
    local ok, kb = pcall(function()
        return require("mh/ui/keyboard"):new{
            inputbox = self.inputbox,
            action = "Search",
            on_action = function() UIManager:nextTick(function() self:submit() end) end,
        }
    end)
    if not ok then
        logger.err("MinimalHome: no keyboard:", kb)
        return
    end
    self.keyboard = kb
    self.kb_visible = true
    -- taps above the keyboard (results, back, field) still reach this screen
    self.is_always_active = true
    UIManager:show(self.keyboard)
    self:refresh()
end

function SearchScreen:hideKeyboard()
    if not self.kb_visible then return end
    self.kb_visible = false
    self.is_always_active = nil
    if self.keyboard then UIManager:close(self.keyboard) end
end

--- The keyboard went away by itself (its Back key).
function SearchScreen:keyboardGone()
    if not self.kb_visible then return end
    self.kb_visible = false
    self.is_always_active = nil
    self:refresh()
end

-- Query ------------------------------------------------------------------------------------

function SearchScreen:setQuery(q)
    self.query = q or ""
    self.submitted = false
    -- several quick keystrokes make one redraw
    if self._pending then UIManager:unschedule(self._pending) end
    self._pending = function()
        self._pending = nil
        self:refresh()
    end
    UIManager:scheduleIn(0.15, self._pending)
end

function SearchScreen:submit()
    if Search.needle(self.query) == "" then return end
    self.submitted = true
    self:remember()
    self:hideKeyboard()
    self:refresh()
end

function SearchScreen:remember()
    Prefs.set("recent_searches", Search.remember(Prefs.get("recent_searches"), self.query, SearchScreen.RECENT_MAX))
end

function SearchScreen:runRecent(q)
    self.query = q
    self.submitted = true
    self:remember()
    self:hideKeyboard()
    self:refresh()
end

function SearchScreen:clearQuery()
    self.query = ""
    self.submitted = false
    if not self.kb_visible then self:showKeyboard() else self:refresh() end
end

--- Open a book straight from here: the loading bar shows at once and the
--- search screen stays up until the reader takes over (no flash of Home).
function SearchScreen:openBook(path, book)
    if book and book.kindle_only then
        if self.on_kindle_only then self.on_kindle_only() end
        return
    end
    if self.opening then return end
    self.opening = true
    if Search.needle(self.query) ~= "" then self:remember() end
    require("mh/loadingbar").show(0.03, true)
    require("mh/ui/snackbar").paintNow("Opening book…")
    UIManager:nextTick(function()
        -- close without a refresh: the reader paints the whole screen next
        if self._pending then UIManager:unschedule(self._pending) end
        if self.kb_visible and self.keyboard then
            self.kb_visible = false
            self.is_always_active = nil
            UIManager:close(self.keyboard)
        end
        self.closed = true
        UIManager:close(self)
        if self.on_close then self.on_close() end
        if self.on_open then self.on_open(path) end
    end)
end

-- Pieces -----------------------------------------------------------------------------------

--- Text with the matching part underlined (and in `hit_color`), within max_w.
local function marked(text, parts, kind, size, color, hit_color, max_w, line_t)
    if not parts then return C.text(text or "", kind, size, color, max_w) end
    local g = HorizontalGroup:new{ align = "top" }
    local room = max_w
    local function add(w)
        g[#g + 1] = w
        room = room - w:getSize().w
    end
    if parts[1] ~= "" then add(C.text(parts[1], kind, size, color, room)) end
    if room > px(20) then
        local hit = C.text(parts[2], kind, size, hit_color, room)
        local hw = hit:getSize().w
        add(VerticalGroup:new{ align = "left", hit, C.hline(hw, px(line_t), hit_color) })
    end
    if room > px(20) and parts[3] ~= "" then add(C.text(parts[3], kind, size, color, room)) end
    return g
end

function SearchScreen:label(text)
    return C.text(text, "sans_bold", 32, self.col.muted)
end

function SearchScreen:header()
    local w = self:contentWidth()
    local back = C.tappable(C.box(px(88), px(112), C.text("‹", "sans_bold", 64, self.col.fg),
        { halign = "center", valign = "center" }), function() self:close() end)
    local field_w = w - px(88) - px(16)
    local inner = field_w - px(26) - px(12)
    local clear_w = self.query ~= "" and px(80) or 0
    local text_w = inner - px(44) - px(18) - clear_w - px(8)
    local text
    if self.query == "" then
        text = C.text("Title or author", "sans_medium", 40, self.col.muted, text_w)
    else
        text = C.text(self.query, "sans_medium", 40, self.col.fg, text_w)
    end
    local row = HorizontalGroup:new{ align = "center", C.icon("appbar.search", px(44)), C.space(px(18), 1) }
    local caret = self.kb_visible and C.Rect:new{ w = px(3), h = px(48), color = self.col.fg }
    if self.query == "" then
        -- empty field: the caret sits at the start, before the placeholder
        if caret then
            table.insert(row, caret)
            table.insert(row, C.space(px(10), 1))
        end
        table.insert(row, text)
    else
        table.insert(row, text)
        if caret then
            table.insert(row, C.space(px(4), 1))
            table.insert(row, caret)
        end
    end
    local content = OverlapGroup:new{ dimen = Geom:new{ w = inner, h = px(104) },
        C.box(inner - clear_w, px(104), row, { valign = "center" }) }
    if clear_w > 0 then
        local clear = C.tappable(C.box(clear_w, px(104), C.text("×", "sans_medium", 56, self.col.fg),
            { halign = "center", valign = "center" }), function() UIManager:nextTick(function() self:clearQuery() end) end)
        clear.overlap_align = "right"
        table.insert(content, clear)
    end
    local field = C.tappable(C.box(field_w, px(112), content,
        { border = px(4), border_color = self.col.fg, radius = px(10), pad_l = px(26), pad_t = px(4) }),
        function()
            UIManager:nextTick(function()
                self.submitted = false
                if self.kb_visible then self:refresh() else self:showKeyboard() end
            end)
        end)
    self.field = field
    return HorizontalGroup:new{ align = "center", back, C.space(px(16), 1), field }
end

function SearchScreen:bookRow(m, index)
    local w = self:contentWidth()
    local b = m.book
    local cover_w, cover_h, gap = px(84), px(122), px(32)
    local text_w = w - cover_w - gap
    local cover = self.cover_for and self.cover_for(b, cover_w, cover_h,
        { compact = true, title_size = 15, border = px(2), radius = px(6), style_index = index, title_lines = 4 })
        or C.space(cover_w, cover_h)
    local texts = VerticalGroup:new{ align = "left",
        marked(b.title, m.title, "serif_bold", 40, self.col.fg, self.col.fg, text_w, 4) }
    if b.authors and b.authors:match("%S") then
        table.insert(texts, C.space(1, px(6)))
        table.insert(texts, marked(b.authors, m.author, "sans_medium", 32, self.col.muted, self.col.fg, text_w, 3))
    end
    local h = math.max(px(168), cover_h + 2 * px(22))
    local content = HorizontalGroup:new{ align = "center", cover, C.space(gap, 1), texts }
    return VerticalGroup:new{ align = "left",
        C.hline(w, px(3), self.col.line),
        C.tappable(C.box(w, h, content, { valign = "center" }),
            function() UIManager:nextTick(function() self:openBook(b.path, b) end) end),
    }
end

function SearchScreen:moreButton(n)
    local t = C.text("See all " .. n .. " results  →", "sans_bold", 34, self.col.fg)
    return C.tappable(C.box(t:getSize().w, px(88), t, { valign = "center" }),
        function() UIManager:nextTick(function() self:submit() end) end)
end

function SearchScreen:noMatches(w)
    return VerticalGroup:new{ align = "center",
        C.space(1, px(160)),
        C.text("No matches", "serif_bold", 52, self.col.fg, w),
        C.space(1, px(20)),
        C.textbox("No title or author in your library matches “" .. self.query .. "”.",
            "sans_medium", 34, self.col.muted, math.min(w, px(880)), 3, 0.25, "center"),
    }
end

function SearchScreen:recentRow(q)
    local w = self:contentWidth()
    local row = OverlapGroup:new{ dimen = Geom:new{ w = w, h = px(112) },
        C.box(w - px(60), px(112), HorizontalGroup:new{ align = "center",
            C.text("↺", "sans_medium", 38, self.col.muted), C.space(px(28), 1),
            C.text(q, "sans_bold", 38, self.col.fg, w - px(160)) }, { valign = "center" }),
    }
    local arrow = C.box(px(40), px(112), C.text("›", "sans_bold", 44, self.col.muted), { valign = "center" })
    arrow.overlap_align = "right"
    table.insert(row, arrow)
    return VerticalGroup:new{ align = "left",
        C.hline(w, px(3), self.col.line),
        C.tappable(row, function() UIManager:nextTick(function() self:runRecent(q) end) end),
    }
end

-- Layout -----------------------------------------------------------------------------------

function SearchScreen:blocks()
    local w = self:contentWidth()
    local list = {}
    local function add(build) list[#list + 1] = build end
    local needle = Search.needle(self.query)
    self.matches = needle ~= "" and Search.find(self.books, self.query) or {}
    local n = #self.matches

    if needle == "" then
        local recent = Prefs.get("recent_searches") or {}
        if #recent > 0 then
            add(function() return VerticalGroup:new{ align = "left", C.space(1, px(72)),
                self:label("RECENT SEARCHES"), C.space(1, px(20)) } end)
            for _, q in ipairs(recent) do add(function() return self:recentRow(q) end) end
        end
        return list
    end
    if n == 0 then
        add(function()
            local g = self:noMatches(w)
            return C.box(w, g:getSize().h, g, { halign = "center" })
        end)
        return list
    end
    local typing = not self.submitted
    local shown = typing and math.min(n, SearchScreen.LIVE_MAX) or n
    local label = typing and "MATCHES AS YOU TYPE" or (n .. (n == 1 and " MATCH" or " MATCHES"))
    add(function() return VerticalGroup:new{ align = "left", C.space(1, px(56)), self:label(label), C.space(1, px(20)) } end)
    for i = 1, shown do
        local m = self.matches[i]
        add(function() return self:bookRow(m, i) end)
    end
    if typing and n > shown then
        add(function() return VerticalGroup:new{ align = "left", C.space(1, px(20)), self:moreButton(n) } end)
    end
    return list
end

function SearchScreen:buildColumn()
    local out, y = {}, 0
    for _, build in ipairs(self:blocks()) do
        local w = build()
        local h = w:getSize().h
        w:free()
        out[#out + 1] = { y = y, h = h, build = build }
        y = y + h
    end
    out[#out + 1] = { y = y, h = px(96), build = function() return C.space(1, px(96)) end }
    return out
end

function SearchScreen:layout(keep_scroll)
    local keep = keep_scroll and self.viewport and self.viewport.scroll or 0
    if self[1] then self[1]:free() end
    local status = C.statusBar(self:contentWidth(), self.col, 36, true, true)
    local fixed = VerticalGroup:new{ align = "left", status, C.space(1, px(20)), self:header() }
    local view_top = px(Theme.margin_top) + fixed:getSize().h + px(12)
    self.view_top = view_top
    local kb_h = self:keyboardHeight()
    self.viewport = Viewport:new{
        x = 0, y = view_top, w = self.dimen.w, h = math.max(px(100), self.dimen.h - view_top - kb_h),
        content_x = px(Theme.margin_h), blocks = self:buildColumn(), bg = self.col.bg,
    }
    self.viewport.scroll = -1
    self.viewport:scrollTo(keep)
    if self.viewport.scroll < 0 then self.viewport.scroll = 0; self.viewport:update() end
    self.viewport.overlap_offset = { 0, view_top }
    local layers = OverlapGroup:new{
        dimen = Geom:new{ w = self.dimen.w, h = self.dimen.h },
        C.box(self.dimen.w, view_top, fixed, { bg = self.col.bg,
            pad_l = px(Theme.margin_h), pad_t = px(Theme.margin_top) }),
        self.viewport,
    }
    self.back_to_top = nil
    if not self.kb_visible and self.viewport.scroll > self.viewport.h * 0.4 then
        local btn = self:backToTop()
        self.back_to_top = btn
        table.insert(layers, btn)
    end
    self[1] = layers
end

function SearchScreen:backToTop()
    local label = C.text("↑  Back to top", "sans_bold", 36, self.col.fg)
    local w = label:getSize().w + 2 * px(44)
    local h = px(112)
    local btn = C.tappable(C.box(w, h, label, { bg = self.col.bg, border = px(4), border_color = self.col.fg,
        radius = math.floor(h / 2), halign = "center", valign = "center" }),
        function() self:scrollTo(0) end)
    btn.overlap_offset = { self.dimen.w - px(Theme.margin_h) - w, self.dimen.h - px(64) - h }
    return btn
end

--- Rebuild and redraw the part above the keyboard (the keyboard redraws itself).
function SearchScreen:refresh()
    if self.closed then return end
    self:layout(false)
    local region = Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.dimen.h - self:keyboardHeight() }
    UIManager:setDirty(self, "ui", region)
end

--- Once the list is scrolled, a grey line separates the fixed header (as on Home).
function SearchScreen:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    if self.viewport and (self.viewport.scroll or 0) > 0 and self.view_top then
        local t = px(4)
        bb:paintRect(x, y + self.view_top - t, self.dimen.w, t, self.col.line)
    end
end

-- Scrolling --------------------------------------------------------------------------------

function SearchScreen:scrollTo(offset)
    if self.viewport:scrollTo(offset) then
        self:layout(true)
        UIManager:setDirty(self, "ui", Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.dimen.h - self:keyboardHeight() })
    end
end

function SearchScreen:scrollBy(dy) self:scrollTo(self.viewport.scroll + dy) end

-- Taps reach the children (field, rows, buttons) first; a tap nowhere does nothing.
function SearchScreen.onMHTap() return true end

function SearchScreen:onMHPan(_, ges)
    if ges and ges.relative then self._pan_dy = ges.relative.y end
    return true
end

function SearchScreen:onMHPanRelease()
    if self._pan_dy then
        self:scrollBy(-self._pan_dy)
        self._pan_dy = nil
    end
    return true
end

function SearchScreen:onMHSwipe(_, ges)
    self._pan_dy = nil
    local dir = ges and ges.direction
    local dist = (ges and ges.distance or 0) * SearchScreen.FLICK
    if dir == "north" then self:scrollBy(dist) return true end
    if dir == "south" then self:scrollBy(-dist) return true end
    if dir == "east" then self:close() return true end -- swipe right: back
    return true
end

-- Open / close -----------------------------------------------------------------------------

function SearchScreen:show()
    UIManager:show(self, "flashui")
    -- the keyboard comes up at once (design: keyboard just opened)
    UIManager:nextTick(function() self:showKeyboard() end)
    return self
end

function SearchScreen:close()
    if self.closed then return end
    if self._pending then UIManager:unschedule(self._pending) end
    self:hideKeyboard()
    self.closed = true
    UIManager:close(self, "flashui")
    if self.on_close then self.on_close() end
end

function SearchScreen:onClose()
    self:close()
    return true
end

function SearchScreen:onSuspend()
    -- waking up shows the results without the keyboard
    self:hideKeyboard()
end

function SearchScreen:onResume()
    self:refresh()
end

function SearchScreen:onCloseWidget()
    self.closed = true
    if self[1] then self[1]:free() end
end

return SearchScreen
