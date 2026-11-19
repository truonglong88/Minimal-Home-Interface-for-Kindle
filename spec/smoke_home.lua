--[[ Smoke test: builds and paints the home screen with KOReader's real layout
     widgets (from a KOReader checkout) and stubs for everything that needs
     the device, fonts or C libraries. Catches runtime errors in our layout
     code; it is NOT a pixel-accurate preview.

     Usage: luajit spec/smoke_home.lua /path/to/koreader [out.json]
]]
local KO = arg[1] or error("pass the path to a KOReader checkout")
local OUT = arg[2]
package.path = table.concat({
    "spec/stubs/?.lua",
    "minimalhome.koplugin/?.lua",
    KO .. "/frontend/?.lua",
    package.path,
}, ";")

require("stubs_env")      -- installs global stubs (G_reader_settings, …)
local ops = require("ffi/blitbuffer")._ops
local Fake = require("fake_library")
local scenarios = {
    { name = "reading",  books = Fake.library("reading") },
    { name = "finished", books = Fake.library("finished") },
    { name = "start",    books = Fake.library("start") },
    { name = "empty",    books = {} },
}

local Library = require("mh/data/library")
local Prefs = require("mh/data/prefs")
local Home = require("mh/ui/home")
local Blitbuffer = require("ffi/blitbuffer")
local results, failed = {}, 0
for _, sc in ipairs(scenarios) do
    Library.load = function() return sc.books, {} end
    Library.secondsPerPage = function() return 90 end
    for page, scroll in ipairs({ 0, 900, 1e6 }) do
        local ok, err = pcall(function()
            Blitbuffer._resetScreen()
            local bb = Blitbuffer.new(1264, 1680)
            local home = Home:new{ ui = { filesearcher = {}, menu = {} } }
            home:scrollTo(scroll)
            -- a slow drag up by 300 px, then a flick down
            home:onMHPan(nil, { relative = { y = -300 } }); home:onMHPanRelease()
            home:onMHSwipe(nil, { direction = "south", distance = 200 })
            ops.reset()
            home:paintTo(bb, 0, 0)
            -- open the sort menu, pick "Title", then reverse it
            if home.sort_button and home.sort_button.dimen then
                local menu = require("mh/ui/sortmenu"):new{ anchor = home.sort_button.dimen,
                    sort_key = home.sort_key, sort_asc = home.sort_asc, col = home.col,
                    on_pick = function(k, a) Prefs.set("sort_key", k) Prefs.set("sort_asc", a) end }
                menu:paintTo(Blitbuffer.new(1264, 1680))
                assert(menu.card_rect.y >= 0 and menu.card_rect.y + menu.card_rect.h <= 1680, "sort menu on screen")
                Prefs.set("sort_key", "recent") Prefs.set("sort_asc", true)
            end
            results[#results + 1] = { scenario = sc.name, page = page, scroll = home.viewport.scroll,
                max = home.viewport:maxScroll(), ops = ops.list() }
            home:onClose()
        end)
        if not ok then
            failed = failed + 1
            print("FAIL " .. sc.name .. " page " .. page .. ": " .. tostring(err))
        end
    end
end
-- turning the device: landscape and back, on a scrolled home screen
local ok_rot, err_rot = pcall(function()
    Library.load = function() return Fake.library("reading"), {} end
    local home = Home:new{ ui = {} }
    home:scrollTo(900)
    home:onSetRotationMode(1)
    assert(home.dimen.w == 1680 and home.dimen.h == 1264, "home follows landscape")
    Blitbuffer._resetScreen()
    home:paintTo(Blitbuffer.new(1680, 1264), 0, 0)
    home:onSetRotationMode(0)
    assert(home.dimen.w == 1264, "home back to portrait")
end)
if not ok_rot then failed = failed + 1; print("FAIL rotation: " .. tostring(err_rot)) end

-- clock refresh (every minute, and on wake-up)
local ok_clk, err_clk = pcall(function()
    Library.load = function() return Fake.library("reading"), {} end
    local home = Home:new{ ui = {} }
    local before = home.status_box[1]
    home:onSuspend()
    home:onResume()
    assert(home.status_box[1] ~= before, "status bar rebuilt on resume")
    home:onCloseWidget()
end)
if not ok_clk then failed = failed + 1; print("FAIL clock: " .. tostring(err_clk)) end

-- a device where our fonts cannot be loaded at all must still show the home screen
require("ui/font").fail_plugin_fonts = true
package.loaded["mh/theme"] = nil
local ok_fb, err_fb = pcall(function()
    Library.load = function() return Fake.library("reading"), {} end
    Blitbuffer._resetScreen()
    local bb = Blitbuffer.new(1264, 1680)
    local home = Home:new{ ui = {} }
    home:paintTo(bb, 0, 0)
end)
if not ok_fb then failed = failed + 1; print("FAIL font fallback: " .. tostring(err_fb)) end
require("ui/font").fail_plugin_fonts = false

print(string.format("%d screens painted, %d failed", #results, failed))
if OUT then
    local f = io.open(OUT, "w")
    f:write(require("json_min").encode(results))
    f:close()
end
os.exit(failed == 0 and 0 or 1)
