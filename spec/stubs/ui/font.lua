-- Behaves like KOReader v2026.07.1 (seen in a device log): "./fonts/" is put in
-- front of every path, absolute ones included, so "/mnt/..." fails while a path
-- relative to the font folder ("../plugins/...") works.
local Font = { fontmap = { cfont = "NotoSerif-Regular.ttf" }, fail_plugin_fonts = false }
function Font:getFace(path, size)
    assert(type(path) == "string", "font path must be a string")
    -- KOReader's named UI fonts have a default size
    local named = { infofont = 24, cfont = 24, smallinfofont = 22, x_smallinfofont = 20, infont = 22, ffont = 20, tfont = 26,
        smalltfont = 24, x_smalltfont = 22, smallinfofontbold = 22 }
    size = size or named[path]
    assert(type(size) == "number" and size > 0, "font size must be positive")
    if path:sub(1, 1) == "/" then return nil end
    if self.fail_plugin_fonts and path:find("minimalhome") then return nil end
    local px = math.ceil(size * 1264 / 600)
    return { path = path, size = px, orig_size = size, orig_font = path }
end
return Font
