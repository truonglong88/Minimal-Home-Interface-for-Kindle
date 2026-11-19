-- Smoke test for the reading-screen hooks with a fake reader.
-- Usage: luajit spec/smoke_reader.lua /path/to/koreader
local KO = arg[1] or error("pass the path to a KOReader checkout")
package.path = table.concat({ "spec/stubs/?.lua", "minimalhome.koplugin/?.lua", KO .. "/frontend/?.lua", package.path }, ";")
require("stubs_env")
local Reader = require("mh/reader")
local Prefs = require("mh/data/prefs")

local failed = 0
local function check(cond, msg) if not cond then failed = failed + 1; print("FAIL " .. msg) end end

-- apply the style to an empty settings store
Reader.installFonts = function() end
check(Reader.applyStyle() == true, "style applied the first time")
check(Reader.applyStyle() == false, "style applied only once")
local footer_settings = G_reader_settings:readSetting("footer")
check(footer_settings.chapter_time_to_read and not footer_settings.page_progress, "footer: time left on, page number off")
check(footer_settings.time == false and footer_settings.battery == false, "other footer items off")
check(footer_settings.progress_bar_position == "alongside", "missing defaults filled in")
check(footer_settings.item_prefix == "icons", "footer keeps spaces between words")
check(G_reader_settings:readSetting("copt_line_spacing") == 120, "typography defaults written")

-- attach to a fake reader
local module
local footer
footer = {
    pageno = 10,
    textGeneratorMap = { chapter_time_to_read = function() return "original" end },
    updateFooterTextGenerator = function() end,
    updateFooterContainer = function() end,
    resetLayout = function() end,
    onUpdateFooter = function() end,
    TapFooter = function() return "orig-tap" end,
    view = { flipping_visible = false },
}
local ui = {
    rolling = true,
    view = { footer = footer, registerViewModule = function(_, _, w) module = w end },
    statistics = { settings = { is_enabled = true }, avg_time = 30 },
    toc = { getChapterPagesLeft = function() return 16 end },
    document = { getTotalPagesLeft = function() return 270 end },
}
footer.ui = ui
Reader.attach(ui)
check(module ~= nil, "header registered")
local gen = footer.textGeneratorMap.chapter_time_to_read
check(gen(footer) == "8 min left in chapter", "chapter time: " .. tostring(gen(footer)))
-- cycle: book → chapter → nothing → book; the default is chapter
footer:TapFooter({})
check(gen(footer) == "", "nothing after tap: " .. tostring(gen(footer)))
footer:TapFooter({})
check(gen(footer) == "2 h 15 min left in book", "book time after second tap: " .. tostring(gen(footer)))
footer:TapFooter({})
check(gen(footer) == "8 min left in chapter", "chapter after third tap")

local bb = require("ffi/blitbuffer").new(1264, 1680)
bb.getWidth = function() return 1264 end
local ok, err = pcall(function() module:paintTo(bb, 0, 0) end)
check(ok, "header paints: " .. tostring(err))

-- per-book margins, once
local events, saved = {}, {}
ui.typeset = { unscaled_margins = { 10, 15, 10, 15 } }
ui.document.configurable = {}
ui.doc_settings = { isTrue = function(_, k) return saved[k] == true end, makeTrue = function(_, k) saved[k] = true end }
ui.handleEvent = function(_, ev) events[#events + 1] = ev end
package.loaded["ui/event"] = { new = function(_, name, a) return { name = name, arg = a } end }
Reader.styleBook(ui)
check(#events == 2 and ui.document.configurable.t_page_margin == 50 and ui.document.configurable.b_page_margin == 14
    and events[2].name == "SetPageTopAndBottomMargin", "book margins set: " .. #events)
Reader.styleBook(ui)
check(#events == 2, "book margins set only once")

-- reading menu overlay
local zones
ui.registerTouchZones = function(_, z) zones = z end
Reader.registerMenuZones(ui)
check(zones and #zones == 9, "menu tap zones registered")
local by_id = {}
for _, z in ipairs(zones or {}) do by_id[z.id] = z end
check(by_id.minimalhome_screenshot and by_id.minimalhome_screenshot.ges == "hold", "screenshot zone registered")
-- a slow drag down (pan) opens our panel too, ahead of KOReader's menu
local pan = by_id.minimalhome_quickpanel_pan
check(pan and pan.ges == "pan", "pull-down pan zone registered")
local overrides = {}
for _, o in ipairs(pan and pan.overrides or {}) do overrides[o] = true end
check(overrides.readermenu_pan and overrides.readermenu_ext_pan, "pan zone overrides KOReader's menu pan")
-- swipe / drag up from the bottom: Home, ahead of KOReader's bottom menu
local up = by_id.minimalhome_home_swipe
check(up and up.ges == "swipe" and up.screen_zone.ratio_y == 4 / 5, "swipe-up zone at the bottom")
local upo = {}
for _, o in ipairs(up and up.overrides or {}) do upo[o] = true end
check(upo.readerconfigmenu_swipe and upo.readerconfigmenu_ext_swipe, "swipe-up overrides KOReader's bottom menu")
check(by_id.minimalhome_home_pan and by_id.minimalhome_home_pan.ges == "pan", "drag-up zone")
check(up.handler({ direction = "south" }) == false, "swipe down at the bottom is left alone")
-- swipe down from the top while reading opens the quick panel without an error
do
    local UIManager = require("ui/uimanager")
    local shown, orig = nil, UIManager.show
    UIManager.show = function(_, w) shown = w end
    local logger = require("logger")
    local errs = {}
    local orig_err = logger.err
    logger.err = function(...) errs[#errs + 1] = table.concat({ ... }, " ") end
    local qz = zones[3]
    check(qz.id == "minimalhome_quickpanel", "quick panel zone registered")
    check(qz.handler({ direction = "south" }) == true, "swipe down handled")
    check(#errs == 0, "quick panel opened in the reader without error: " .. tostring(errs[1]))
    check(shown and shown.panel_h, "quick panel shown")
    UIManager.show, logger.err = orig, orig_err
end
ui.doc_props = { display_title = "Truyện Kiều", authors = "Nguyễn Du" }
ui.getCurrentPage = function() return 3 end
ui.document.getPageCount = function() return 312 end
local toggled = 0
ui.bookmark = { isPageBookmarked = function() return toggled % 2 == 1 end, onToggleBookmark = function() toggled = toggled + 1 end }
package.loaded["device"].hasFrontlight = function() return true end
local ReaderMenu = require("mh/ui/readermenu")
local menu = ReaderMenu:new{ ui = ui }
local mbb = require("ffi/blitbuffer").new(1264, 1680)
local ok2, err2 = pcall(function() menu:paintTo(mbb) end)
check(ok2, "reading menu paints: " .. tostring(err2))
check(menu.top_rect.h > 0 and menu.bottom_rect.y > menu.top_rect.h, "bars do not overlap")
menu:rebuild()
check(toggled == 0, "rebuild alone does not toggle")
_G.MH_MENU = menu

-- page slider: drag shows the page under the knob, release goes there
do
    menu:paintTo(mbb)
    local r = menu._track_rect
    check(r ~= nil, "track position known after paint")
    if r then
        local went
        local orig = ui.handleEvent
        ui.handleEvent = function(_, ev) if ev.name == "GotoPage" then went = ev.arg end end
        local y = r.y + math.floor(r.h / 2)
        menu:onMHPan(nil, { start_pos = { x = r.x + 2, y = y }, pos = { x = r.x + math.floor(r.w / 2), y = y } })
        check(menu._preview_page == 156, "drag previews the middle page: " .. tostring(menu._preview_page))
        menu:paintTo(mbb)
        menu:onMHPanRelease(nil, { pos = { x = r.x + r.w, y = y } })
        check(went == 312, "release goes to the page under the finger: " .. tostring(went))
        check(not menu.closed, "menu stays open after dragging the slider")
        ui.handleEvent = orig
    end
end

Prefs.set("reader_style", false)
check(gen(footer) == "original", "style off falls back to KOReader's text")

-- KOReader's own menus and the Gestures plugin's zones do nothing; page turns stay
do
    local h = function() return true end
    local zui = { _zones = {
        readermenu_tap = { handler = h }, readerconfigmenu_tap = { handler = h }, readerfooter_hold = { handler = h },
        tap_top_left_corner = { handler = h }, multiswipe = { handler = h }, two_finger_swipe_east = { handler = h },
        tap_forward = { handler = h }, rolling_swipe = { handler = h }, readerhighlight_hold = { handler = h },
        minimalhome_menu_center = { handler = h },
    } }
    local n = Reader.muteKOReaderZones(zui)
    check(n == 6, "muted: " .. n)
    check(zui._zones.readermenu_tap.handler() == false and zui._zones.multiswipe.handler() == false, "menus muted")
    check(zui._zones.tap_forward.handler() == true and zui._zones.readerhighlight_hold.handler() == true
        and zui._zones.minimalhome_menu_center.handler() == true, "page turns, long-press and ours kept")
    check(Reader.muteKOReaderZones(zui) == 0, "muting twice changes nothing")
end

print(failed == 0 and "reader hooks OK" or (failed .. " checks failed"))
os.exit(failed == 0 and 0 or 1)
