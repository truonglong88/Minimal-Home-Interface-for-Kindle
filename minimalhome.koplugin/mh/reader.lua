--[[--
Reading screen styling.

* Top: clock on the left, battery on the right (drawn by us over the page margin).
* Bottom: KOReader's status bar, reduced to "8 min left in chapter" on the left
  (tap to switch to the whole book) and "47 / 365" on the right.
* New books open with wide margins, airy line spacing and Literata.

The status bar and typography presets are written to KOReader's own settings,
so they also show up (and stay editable) in KOReader's menus. The user's
previous status bar settings are kept and restored if the style is turned off.
--]]

local Widget = require("ui/widget/widget")
local Geom = require("ui/geometry")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")

local C = require("mh/ui/components")
local Model = require("mh/data/model")
local Prefs = require("mh/data/prefs")
local Theme = require("mh/theme")

local Reader = {}

Reader.STYLE_VERSION = 8 -- 5: narrower margins, bigger bars; 6: font path that loads; 7: no page number; 8: smaller, even top / bottom

-- Global defaults for new books (KOReader stores them as copt_<option>).
local TYPOGRAPHY = {
    copt_h_page_margins = { 46, 46 }, -- keep in step with Reader.MARGINS
    copt_t_page_margin = 50, -- keep in step with Reader.MARGINS
    copt_b_page_margin = 14,
    copt_line_spacing = 120,
    copt_status_line = 1, -- 1 = crengine's own top bar off; we draw ours
}

local FOOTER_ITEMS = {
    "page_progress", "pages_left_book", "time", "pages_left", "battery", "percentage",
    "book_time_to_read", "chapter_time_to_read", "frontlight", "mem_usage", "wifi_status",
    "page_turning_inverted", "book_author", "book_title", "book_chapter", "bookmark_count",
    "chapter_progress", "frontlight_warmth", "custom_text", "dynamic_filler", "dynamic_filler2",
    "additional_content",
}
local FOOTER_ON = { chapter_time_to_read = true, dynamic_filler = true } -- no page number

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end

--- Copy our fonts into KOReader's font folder so the book renderer can use them.
--- Takes effect after KOReader restarts.
function Reader.installFonts()
    local dest = "./fonts/minimalhome"
    if lfs.attributes(dest, "mode") ~= "directory" then
        lfs.mkdir(dest)
    end
    for _, name in ipairs({ "Literata-Regular.ttf", "Literata-SemiBold.ttf" }) do
        local src = Theme.plugin_dir .. "/fonts/" .. name
        local dst = dest .. "/" .. name
        if lfs.attributes(dst, "mode") ~= "file" and lfs.attributes(src, "mode") == "file" then
            local fin = io.open(src, "rb")
            local fout = fin and io.open(dst, "wb")
            if fin and fout then
                fout:write(fin:read("*a"))
            else
                logger.warn("MinimalHome: could not copy font", name)
            end
            if fin then fin:close() end
            if fout then fout:close() end
        end
    end
end

--- Write the reading style into KOReader's settings (once per style version).
function Reader.applyStyle(force)
    if not force and (Prefs.get("reader_style_version") or 0) >= Reader.STYLE_VERSION then
        return false
    end
    local footer = G_reader_settings:readSetting("footer")
    if footer and not Prefs.get("footer_backup") then
        Prefs.set("footer_backup", copy(footer))
    end
    footer = footer or {}
    -- start from KOReader's defaults so no setting the status bar expects is missing
    local ok, ReaderFooter = pcall(require, "apps/reader/modules/readerfooter")
    if ok and ReaderFooter.default_settings then
        for k, v in pairs(ReaderFooter.default_settings) do
            if footer[k] == nil then footer[k] = copy(v) end
        end
    end
    for _, item in ipairs(FOOTER_ITEMS) do
        footer[item] = FOOTER_ON[item] or false
    end
    footer.all_at_once = true
    footer.disable_progress_bar = true
    footer.hide_empty_generators = true
    footer.items_separator = "none"
    footer.align = "center"
    footer.item_prefix = "icons" -- (our own items ignore the prefix; "compact" would strip spaces)
    footer.text_font_face = Theme.fontName("sans_medium")
    footer.text_font_size = 15
    footer.text_font_bold = false
    footer.container_height = 24          -- unscaled; room above and below the text
    footer.container_bottom_padding = 12  -- keeps the text off the bottom edge
    footer.order = { "chapter_time_to_read", "dynamic_filler" }
    G_reader_settings:saveSetting("footer", footer)

    for k, v in pairs(TYPOGRAPHY) do
        G_reader_settings:saveSetting(k, copy(v))
    end
    if not G_reader_settings:readSetting("cre_font") then
        G_reader_settings:saveSetting("cre_font", "Literata")
    end
    pcall(Reader.installFonts)
    Prefs.set("reader_style_version", Reader.STYLE_VERSION)
    return true
end

--- Put the user's own status bar back.
function Reader.restoreStyle()
    local backup = Prefs.get("footer_backup")
    if backup then
        G_reader_settings:saveSetting("footer", backup)
        Prefs.set("footer_backup", nil)
    end
    Prefs.set("reader_style_version", 0)
end

-- Live reader hooks ------------------------------------------------------------

-- Top bar drawn over the page, inside the top margin.
local Header = Widget:extend{ ui = nil }

-- unscaled, like KOReader's own margin values. Top: our status bar (≈ 36) plus a
-- small gap; bottom: the same small gap, KOReader's status bar (36) comes on top,
-- so the text has the same room above and below.
Reader.MARGINS = { h = 46, t = 50, b = 14 }
Reader.OLD_H_MARGIN = 70 -- what earlier versions set; replaced by the narrower one
Reader.BAR_MARGIN = 72 -- design px: side margin of the top bar and the status bar

function Header.paintTo(self, bb, x, y)
    local m = self.ui and self.ui.typeset and self.ui.typeset.unscaled_margins
    if m and (m[2] or 0) < 50 then return end -- book uses a small top margin: don't draw over text
    -- never let our top bar take the reader down with it
    local ok, err = pcall(function()
        local w = bb:getWidth()
        -- same size and place as the status bar on Home and Settings
        local margin = Theme.px(Theme.margin_h)
        local bar = C.statusBar(w - 2 * margin, Theme.boldColors(false), 36, true, false, true)
        bar:paintTo(bb, x + margin, y + Theme.px(Theme.margin_top))
        bar:free()
    end)
    if not ok and not self._warned then
        self._warned = true
        logger.warn("MinimalHome: top bar not drawn:", err)
    end
end

function Header.getSize(_)
    return Geom:new{ w = 0, h = 0 }
end

-- The page is only redrawn on page turns, so the clock in the top bar would
-- stand still while reading one page, and show the old time after waking up.
-- Redraw just the top strip on every minute change and on resume.
local clock = { ui = nil, tick = nil }

function Reader.refreshClock()
    local ui = clock.ui
    if not (ui and ui.document and ui.rolling and Prefs.get("reader_style")) then return end
    local UIManager = require("ui/uimanager")
    local Screen = require("device").screen
    UIManager:setDirty(ui, "ui", Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Theme.px(110) })
end

function Reader.stopClock()
    if clock.tick then require("ui/uimanager"):unschedule(clock.tick) end
    clock.ui, clock.tick = nil, nil
end

local function scheduleClock()
    if not clock.tick then return end
    local UIManager = require("ui/uimanager")
    UIManager:unschedule(clock.tick)
    local sec = tonumber(os.date("%S")) or 0
    UIManager:scheduleIn(60 - sec + 0.2, clock.tick)
end

function Reader.startClock(ui)
    Reader.stopClock()
    clock.ui = ui
    clock.tick = function()
        Reader.refreshClock()
        scheduleClock()
    end
    scheduleClock()
end

function Reader.onResume()
    if not clock.ui then return end
    Reader.refreshClock()
    scheduleClock()
end

function Reader.onSuspend()
    if clock.tick then require("ui/uimanager"):unschedule(clock.tick) end
end

local function secondsPerPage(ui)
    local st = ui.statistics
    if st and st.settings and st.settings.is_enabled and st.avg_time and st.avg_time == st.avg_time then
        return st.avg_time
    end
end

local function timeLeftText(footer)
    local ui = footer.ui
    local per = secondsPerPage(ui)
    if Reader.timeScope() == "none" then return nil end
    if not per or not footer.pageno then return nil end
    if Reader.timeScope() == "book" then
        return Model.timeLeftLabel(ui.document:getTotalPagesLeft(footer.pageno) * per, "book")
    end
    local left = ui.toc and ui.toc:getChapterPagesLeft(footer.pageno, true)
    if left then
        return Model.timeLeftLabel(left * per, "chapter")
    end
    return Model.timeLeftLabel(ui.document:getTotalPagesLeft(footer.pageno) * per, "book")
end

-- Tapping the time left cycles: book → chapter → nothing → book …
Reader.TIME_SCOPES = { "book", "chapter", "none" }

function Reader.timeScope()
    local s = Prefs.get("time_scope")
    for _, v in ipairs(Reader.TIME_SCOPES) do if v == s then return s end end
    return "chapter"
end

function Reader.nextTimeScope()
    local cur = Reader.timeScope()
    for i, v in ipairs(Reader.TIME_SCOPES) do
        if v == cur then
            local nxt = Reader.TIME_SCOPES[i % #Reader.TIME_SCOPES + 1]
            Prefs.set("time_scope", nxt)
            return nxt
        end
    end
end

--- Give a book our margins the first time it is opened with the style on.
--- After that the book keeps whatever the user sets in KOReader's menus.
function Reader.styleBook(ui)
    if not Prefs.get("reader_style") or not ui.rolling or not ui.doc_settings then return end
    if ui.doc_settings:isTrue("minimalhome_styled_v3") then return end
    local ok, err = pcall(function()
        local Event = require("ui/event")
        local conf = ui.document.configurable
        local M = Reader.MARGINS
        local m = ui.typeset and ui.typeset.unscaled_margins or {}
        -- narrower than before: replace our old margin, or anything tighter than ours
        if (m[1] or 0) < M.h or m[1] == Reader.OLD_H_MARGIN then
            conf.h_page_margins = { M.h, M.h }
            ui:handleEvent(Event:new("SetPageHorizMargins", { M.h, M.h }))
        end
        -- top and bottom: ours, so they match (books opened before get them once too)
        if m[2] ~= M.t or m[4] ~= M.b then
            conf.t_page_margin, conf.b_page_margin = M.t, M.b
            ui:handleEvent(Event:new("SetPageTopAndBottomMargin", { M.t, M.b }))
        end
        ui.doc_settings:makeTrue("minimalhome_styled_v3")
    end)
    if not ok then logger.warn("MinimalHome: could not set book margins:", err) end
end

--- Tap zones: the middle of the page, and the top and bottom strips where KOReader
--- would open its own menus, now open ours. Left / right edges still turn pages,
--- and swiping down from the top / up from the bottom still opens KOReader's menus.
function Reader.registerMenuZones(ui)
    if not ui.registerTouchZones then return end
    ui._minimalhome_zones = true
    local function show()
        if not Prefs.get("reader_style") then return false end
        require("mh/ui/readermenu"):new{ ui = ui }:show()
        return true
    end
    ui:registerTouchZones({
        {
            id = "minimalhome_menu_center",
            ges = "tap",
            screen_zone = { ratio_x = 0.3, ratio_y = 0.15, ratio_w = 0.4, ratio_h = 0.65 },
            overrides = { "tap_forward", "tap_backward" },
            handler = function() return show() end,
        },
        {
            id = "minimalhome_menu_top",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 / 8 },
            overrides = { "readermenu_tap", "readermenu_ext_tap", "tap_forward", "tap_backward" },
            handler = function() return show() end,
        },
        {
            -- swipe down from the top edge: quick settings
            id = "minimalhome_quickpanel",
            ges = "swipe",
            -- as tall as KOReader's own menu swipe zone and its centre extension (1/5)
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 / 5 },
            overrides = { "readermenu_swipe", "readermenu_ext_swipe" },
            handler = function(ges) return Reader.pullDown(ui, ges) end,
        },
        {
            -- a slower drag down is a "pan", which KOReader also turns into its menu
            id = "minimalhome_quickpanel_pan",
            ges = "pan",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 / 5 },
            overrides = { "readermenu_pan", "readermenu_ext_pan" },
            handler = function(ges) return Reader.pullDown(ui, ges) end,
        },
        {
            -- swipe up from the bottom edge: back to Home (like an iPhone's home bar)
            id = "minimalhome_home_swipe",
            ges = "swipe",
            -- as tall as KOReader's own bottom menu zone and its centre extension (1/5)
            screen_zone = { ratio_x = 0, ratio_y = 4 / 5, ratio_w = 1, ratio_h = 1 / 5 },
            overrides = { "readerconfigmenu_swipe", "readerconfigmenu_ext_swipe" },
            handler = function(ges) return Reader.pullUp(ui, ges) end,
        },
        {
            id = "minimalhome_home_pan",
            ges = "pan",
            screen_zone = { ratio_x = 0, ratio_y = 4 / 5, ratio_w = 1, ratio_h = 1 / 5 },
            overrides = { "readerconfigmenu_pan", "readerconfigmenu_ext_pan" },
            handler = function(ges) return Reader.pullUp(ui, ges) end,
        },
        {
            -- bottom-left corner: same as tapping the time left (KOReader toggles
            -- the front light here by default, which is easy to hit by mistake)
            id = "minimalhome_corner_bottom_left",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 7 / 8, ratio_w = 1 / 8, ratio_h = 1 / 8 },
            overrides = { "tap_left_bottom_corner", "readerfooter_tap", "tap_backward", "tap_forward" },
            handler = function()
                if not Prefs.get("reader_style") then return false end
                Reader.nextTimeScope()
                local footer = ui.view and ui.view.footer
                if footer and footer.onUpdateFooter then footer:onUpdateFooter(true) end
                return true
            end,
        },
        {
            id = "minimalhome_screenshot",
            ges = "hold",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 / 12 },
            overrides = { "readerhighlight_hold" },
            handler = function() return require("mh/screenshot").take(ui) end,
        },
        {
            id = "minimalhome_menu_bottom",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0.8, ratio_w = 1, ratio_h = 0.15 },
            overrides = { "readerconfigmenu_tap", "readerconfigmenu_ext_tap", "tap_forward", "tap_backward" },
            handler = function() return show() end,
        },
    })
end

function Reader.showQuickPanel(ui)
    if Reader._panel_open then return end
    Reader._panel_open = true
    require("mh/ui/quickpanel"):new{
        ui = ui,
        on_settings = function() require("mh/ui/settings").openPage(ui) end,
        on_close = function() Reader._panel_open = nil end,
    }:show()
end

--- Swipe or drag up from the bottom of the page: close the book, back to Home.
function Reader.pullUp(ui, ges)
    if not Prefs.get("reader_style") or not ges or ges.direction ~= "north" then return false end
    if ui._minimalhome_leaving then return true end -- a drag sends many pans
    ui._minimalhome_leaving = true
    pcall(function() ui:handleEvent(require("ui/event"):new("HandledAsSwipe")) end)
    -- the rest of this drag must not scroll Home once it is up
    pcall(function() require("device").input:inhibitInputUntil(true) end)
    require("ui/uimanager"):nextTick(function()
        ui:handleEvent(require("ui/event"):new("Home"))
    end)
    return true
end

--- Swipe or drag down from the top of the page: our quick panel, not KOReader's menu.
function Reader.pullDown(ui, ges)
    if not Prefs.get("reader_style") or not ges or ges.direction ~= "south" then return false end
    -- never let the panel take the reader down
    local ok, err = pcall(Reader.showQuickPanel, ui)
    if not ok then
        Reader._panel_open = nil
        logger.err("MinimalHome: quick panel failed:", err)
        require("mh/ui/snackbar").show("Quick settings failed", 4, tostring(err))
    end
    -- KOReader may have started scrolling the page with this pan: cancel it
    pcall(function() ui:handleEvent(require("ui/event"):new("HandledAsSwipe")) end)
    return true
end

--- Called by main.lua when a book is opened.
--- KOReader registers its own menu zones again when the book is ready and on
--- every rotation; register ours again after it so they stay in front.
-- KOReader's own reader gestures that stay: turning pages (tap the left / right
-- edge, swipe, page buttons), links and footnotes, and long-press on a word
-- (dictionary, highlight). Everything else KOReader or its Gestures plugin
-- puts on the page (its top / bottom menus, the status bar menu, corner taps,
-- edge swipes for the light, multiswipes, two-finger gestures…) is switched
-- off: only Minimal Home's gestures open anything.
Reader.KEEP_ZONES = {
    tap_forward = true, tap_backward = true,
    paging_swipe = true, rolling_swipe = true,
    paging_pan = true, paging_pan_release = true, rolling_pan = true, rolling_pan_release = true,
    tap_link = true, swipe_link = true,
    readerhighlight_hold = true, readerhighlight_hold_pan = true, readerhighlight_hold_release = true,
    readerhighlight_tap = true, readerhighlight_tap_select_mode = true,
    inertial_scrolling_tap = true, inertial_scrolling_touch = true,
}

local function mutedHandler() return false end

--- Mute every touch zone that is neither ours nor kept. Muted zones stay
--- registered (KOReader re-registers its own) but do nothing, so the gesture
--- goes on to the zones below (usually a page turn).
function Reader.muteKOReaderZones(ui)
    local zones = ui and ui._zones
    if type(zones) ~= "table" then return 0 end
    local n = 0
    for id, z in pairs(zones) do
        if type(id) == "string" and not id:find("^minimalhome_") and not Reader.KEEP_ZONES[id]
                and type(z) == "table" and z.handler ~= mutedHandler then
            z.handler = mutedHandler
            n = n + 1
        end
    end
    return n
end

function Reader.reassertZones(ui)
    if not (ui and ui._minimalhome_zones) then return end
    require("ui/uimanager"):nextTick(function()
        local ok, err = pcall(Reader.registerMenuZones, ui)
        if not ok then logger.warn("MinimalHome: could not re-register touch zones:", err) end
        pcall(Reader.muteKOReaderZones, ui)
    end)
end

function Reader.attach(ui)
    if not Prefs.get("reader_style") then return end
    if (Prefs.get("reader_style_version") or 0) < Reader.STYLE_VERSION then return end

    local ok, err = pcall(function()
        local view = ui.view
        -- Top bar: reflowable books only (EPUB, FB2…); PDF pages use the full screen.
        if ui.rolling and view and view.registerViewModule then
            view:registerViewModule("minimalhome_header", Header:new{ ui = ui })
            Reader.startClock(ui)
        end

        local footer = view and view.footer
        if not footer then return end

        -- Our wording for the "time left" item.
        local map = footer.textGeneratorMap
        if map and not map._minimalhome then
            local original = map.chapter_time_to_read
            map.chapter_time_to_read = function(f)
                if Prefs.get("reader_style") then
                    return timeLeftText(f) or ""
                end
                return original(f)
            end
            map._minimalhome = true
        end
        -- the footer caches its generator functions: rebuild them
        if footer.updateFooterTextGenerator then footer:updateFooterTextGenerator() end

        -- Line the status bar up with the text margins.
        footer.horizontal_margin = Theme.px(Reader.BAR_MARGIN)
        if footer.updateFooterContainer then footer:updateFooterContainer() end
        if footer.resetLayout then footer:resetLayout(true) end

        -- Tapping the page opens our reading menu instead of KOReader's.
        Reader.registerMenuZones(ui)
        pcall(Reader.muteKOReaderZones, ui)

        -- End of the book: our Finished screen instead of KOReader's pop-up.
        local status = ui.status
        if status and status.onEndOfBook and not status._minimalhome then
            local original = status.onEndOfBook
            status.onEndOfBook = function(st, ...)
                if Prefs.get("reader_style")
                        and require("mh/ui/finished").showFor(ui) then
                    return true
                end
                return original(st, ...)
            end
            status._minimalhome = true
        end

        -- Tap the status bar: time left for the book, the chapter, or nothing.
        local tap = footer.TapFooter
        footer.TapFooter = function(f, ges)
            if f.view and f.view.flipping_visible then
                return tap(f, ges)
            end
            Reader.nextTimeScope()
            f:onUpdateFooter(true)
            return true
        end
    end)
    if not ok then
        logger.warn("MinimalHome: reading style not applied:", err)
    end
end

return Reader
