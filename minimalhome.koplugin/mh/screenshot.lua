--[[--
Long-press the clock (top of the screen) to take a screenshot. Easier than
KOReader's two-finger diagonal tap, which needs both fingers right in the corners.
Uses KOReader's own Screenshoter, so files land in koreader/screenshots/.
--]]
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Shot = {}

-- Save the screen, then show a short note that closes on its own (no buttons:
-- KOReader's own dialog asks the user to choose Delete / View / Close).
local function shoot(ui, shooter)
    local Device = require("device")
    local _ = require("gettext")
    local prefix = shooter.prefix or "Screenshot"
    local file = ui.document and ui.document.file
    if file then
        prefix = prefix .. "_" .. require("ffi/util").basename(file)
    end
    local name = os.date(shooter:getScreenshotDir() .. "/" .. prefix .. "_%Y-%m-%d_%H%M%S.png")
    -- Depending on the KOReader version, shot() returns true, or nothing at
    -- all on success; judge by whether the file was actually written.
    local called, ret, err = pcall(Device.screen.shot, Device.screen, name)
    local lfs = require("libs/libkoreader-lfs")
    local ok = called and ret ~= false and lfs.attributes(name, "mode") == "file"
    if not called then err = ret end
    if not ok and err == nil then err = name end
    require("mh/ui/snackbar").show(ok and _("Screenshot saved") or (_("Screenshot failed:") .. " " .. tostring(err)), 2)
end

function Shot.take(ui)
    local shooter = ui and ui.screenshot
    if not shooter then
        logger.warn("MinimalHome: no screenshot module")
        return false
    end
    -- let the long-press feedback clear before grabbing the screen
    UIManager:scheduleIn(0.3, function()
        local ok, err = pcall(shoot, ui, shooter)
        if not ok then logger.err("MinimalHome: screenshot failed:", err) end
    end)
    return true
end

return Shot
