--[[--
Design tokens for Minimal Home.

Every size in the design is drawn on a 1264 px wide screen (Kindle Oasis).
`Theme.px(n)` converts a design size to real pixels for the current device,
so the layout keeps its proportions on smaller or larger screens.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Screen = Device.screen

local DESIGN_WIDTH = 1264

local Theme = {}

local lfs = require("libs/libkoreader-lfs")

-- Absolute path of the plugin folder. Some KOReader versions put "./fonts/"
-- in front of any font path that isn't absolute, so relative paths break.
-- KOReader's working directory; nil when it can't be found.
local function currentDir()
    local d = lfs.currentdir and lfs.currentdir()
    if not d or d == "" then d = os.getenv("PWD") end
    if d and d ~= "" then return d end
end

local plugin_dir = (debug.getinfo(1, "S").source:match("^@(.*)/mh/theme%.lua$")) or "."
if plugin_dir:sub(1, 1) ~= "/" then
    local cwd = currentDir() or "."
    plugin_dir = cwd .. "/" .. (plugin_dir:gsub("^%./", ""))
end
Theme.plugin_dir = plugin_dir

local function shortSide()
    return math.min(Screen:getWidth(), Screen:getHeight())
end

--- Design pixels -> device pixels.
function Theme.px(n)
    return math.floor(n * shortSide() / DESIGN_WIDTH + 0.5)
end

-- Font:getFace() scales its size with Screen:scaleBySize(), which is roughly
-- shortSide / 600. Pre-divide so a design font size lands at the same pixel
-- height it has in the design.
local function faceSize(design_px)
    return design_px * 600 / DESIGN_WIDTH
end

local font_files = {
    serif = "Literata-Regular.ttf",
    serif_bold = "Literata-SemiBold.ttf",
    sans = "Inter-Regular.ttf",
    sans_medium = "Inter-Medium.ttf",
    sans_bold = "Inter-SemiBold.ttf",
}
-- KOReader's bundled fonts, used if ours are missing.
local font_fallback = {
    serif = "NotoSerif-Regular.ttf",
    serif_bold = "NotoSerif-Bold.ttf",
    sans = "NotoSans-Regular.ttf",
    sans_medium = "NotoSans-Regular.ttf",
    sans_bold = "NotoSans-Bold.ttf",
}

local function splitPath(p)
    local parts = {}
    for seg in p:gmatch("[^/]+") do
        if seg == ".." then table.remove(parts) elseif seg ~= "." then parts[#parts + 1] = seg end
    end
    return parts
end

--- Path of one of our font files as KOReader's Font:getFace() wants it.
--- Some versions (e.g. v2026.07.1) put the font folder ("./fonts/") in front of
--- every path, absolute ones included; a path relative to that folder
--- ("../plugins/minimalhome.koplugin/fonts/X.ttf") works on every version.
--- `path` (absolute, or relative to the working directory) as a path relative
--- to KOReader's font folder.
function Theme.relativeToFonts(path)
    local cwd = currentDir() or "."
    local ok, FontList = pcall(require, "fontlist")
    local fontdir = ok and FontList and FontList.fontdir or "./fonts"
    if fontdir:sub(1, 1) ~= "/" then fontdir = cwd .. "/" .. fontdir end
    if path:sub(1, 1) ~= "/" then path = cwd .. "/" .. path end
    local from, to = splitPath(fontdir), splitPath(path)
    local common = 0
    while common < #from and common < #to - 1 and from[common + 1] == to[common + 1] do common = common + 1 end
    local rel = {}
    for _ = common + 1, #from do rel[#rel + 1] = ".." end
    for i = common + 1, #to do rel[#rel + 1] = to[i] end
    return table.concat(rel, "/")
end

function Theme.fontFile(file)
    return Theme.relativeToFonts(plugin_dir .. "/fonts/" .. file)
end

--- A face for any font file (e.g. a book font, to show its name in its own
--- style), or nil. Tries the path as given and relative to the font folder.
function Theme.fileFace(path, design_px, faceindex)
    if not path then return nil end
    local size = faceSize(design_px)
    for _, name in ipairs({ Theme.relativeToFonts(path), path }) do
        local ok, face = pcall(Font.getFace, Font, name, size, faceindex)
        if ok and face then return face end
    end
end

local resolved = {}
--- Font names to try for a kind, best first. The first that loads wins.
--- Several spellings of the same file, because KOReader versions differ in how
--- they join a font name with their font folder, and the working directory is
--- not always known (lfs.currentdir() can fail, leaving the paths relative).
local function fontCandidates(kind)
    if resolved[kind] then return { resolved[kind] } end
    local file = font_files[kind]
    local list, seen = {}, {}
    local function add(name) if name and not seen[name] then seen[name] = true; list[#list + 1] = name end end
    local folder = plugin_dir:match("([^/]+)$") or "minimalhome.koplugin"
    add(Theme.fontFile(file))
    add("../plugins/" .. folder .. "/fonts/" .. file) -- standard layout: fonts/ and plugins/ side by side
    add(plugin_dir .. "/fonts/" .. file)
    add(font_fallback[kind])
    add("cfont")
    return list
end

--- KOReader's Font:getFace can raise on a font it can't open, so every try is guarded.
local function tryFace(name, size)
    local ok, face = pcall(Font.getFace, Font, name, size)
    if ok and face then return face end
end

--- @param kind "serif"|"serif_bold"|"sans"|"sans_medium"|"sans_bold"
--- @param design_px number font size in design pixels
function Theme.face(kind, design_px)
    local size = faceSize(design_px)
    for _ = 1, 2 do
        for _, name in ipairs(fontCandidates(kind)) do
            local face = tryFace(name, size)
            if face then
                resolved[kind] = name -- remember what works
                return face
            end
        end
        resolved[kind] = nil -- what worked before no longer does: try them all again
    end
    -- never hand a widget a nil face
    return tryFace("cfont", size) or tryFace("infofont", size) or Font:getFace("cfont")
end

--- A font name that loads for `kind`, for KOReader settings that take a font
--- (the reader's status bar). Falls back to KOReader's own font.
function Theme.fontName(kind)
    Theme.face(kind, 24)
    return resolved[kind] or font_fallback[kind]
end

-- Colors. Blitbuffer.gray(x): 0 = white, 1 = black.
function Theme.colors(night)
    if night then
        return {
            bg = Blitbuffer.COLOR_BLACK,
            fg = Blitbuffer.COLOR_WHITE,
            muted = Blitbuffer.gray(0.33),
            line = Blitbuffer.gray(0.73),
            fill = Blitbuffer.gray(0.87),
        }
    end
    return {
        bg = Blitbuffer.COLOR_WHITE,
        fg = Blitbuffer.COLOR_BLACK,
        muted = Blitbuffer.gray(0.67), -- #555555
        line = Blitbuffer.gray(0.2),   -- #CCCCCC
        fill = Blitbuffer.gray(0.1),   -- #E6E6E6
    }
end

--- Darker greys for the home screen: thin light greys wash out on e-ink.
function Theme.boldColors(night)
    local c = Theme.colors(night)
    if night then
        c.muted, c.line, c.fill = Blitbuffer.gray(0.22), Blitbuffer.gray(0.53), Blitbuffer.gray(0.8)
    else
        c.muted = Blitbuffer.gray(0.77) -- #3A3A3A
        c.line = Blitbuffer.gray(0.45)  -- #8C8C8C
        c.fill = Blitbuffer.gray(0.15)  -- #D9D9D9
    end
    return c
end

-- Layout constants (design pixels).
Theme.margin_h = 88
Theme.margin_top = 32

return Theme
