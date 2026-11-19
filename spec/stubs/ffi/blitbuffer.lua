-- Records paint operations instead of drawing pixels.
local list = {}
local ops = { reset = function() list = {} end, list = function() return list end,
    add = function(op) list[#list + 1] = op end }
local function color(v) return { v = v } end
local BB = { _ops = ops,
    COLOR_WHITE = color(0), COLOR_BLACK = color(1), COLOR_GRAY = color(0.5),
    COLOR_DARK_GRAY = color(0.53), COLOR_LIGHT_GRAY = color(0.2),
    gray = function(x) return color(x) end,
    isColor8 = function() return true end }
local mt = {}
mt.__index = mt
local function check(x, y, w, h, what)
    for _, v in ipairs({ x, y, w, h }) do
        if type(v) ~= "number" or v ~= v then error(what .. ": non-numeric geometry " .. tostring(v), 3) end
    end
end
local function emit(bb, op) if bb.offscreen then bb._list[#bb._list + 1] = op else ops.add(op) end end
BB._emit = emit
function mt:paintRect(x, y, w, h, c) check(x, y, w, h, "paintRect"); emit(self, { "rect", x, y, w, h, c and c.v or 1 }) end
function mt:paintRoundedRect(x, y, w, h, c, r) check(x, y, w, h, "paintRoundedRect"); emit(self, { "rect", x, y, w, h, c and c.v or 1, r or 0 }) end
function mt:paintBorder(x, y, w, h, bw, c, r) check(x, y, w, h, "paintBorder"); emit(self, { "border", x, y, w, h, bw, c and c.v or 1, r or 0 }) end
function mt:getWidth() return self.w end
function mt:getHeight() return self.h end
function mt:getType() return 1 end
function mt:free() end
function mt:fill(c) if not self.offscreen then ops.add{ "rect", 0, 0, self.w, self.h, c and c.v or 0 } end end
-- Off-screen buffers keep their own op list; blitFrom copies the ops that land
-- inside the copied window (clipped), the way a real blit would.
function mt:blitFrom(src, dx, dy, sx, sy, w, h)
    for _, op in ipairs(src._list or {}) do
        local oy, oh = op[3], op[1] == "text" and (op[6] or 0) * 1.3 or (op[5] or 0)
        if oy + oh > sy and oy < sy + h then
            local copy = {}
            for i, v in ipairs(op) do copy[i] = v end
            copy[#copy + 1] = { "clip", dx, dy, w, h }
            ops.add(copy)
        end
    end
end
local real_new
function BB.new(w, h)
    local bb = setmetatable({ w = w, h = h }, mt)
    if real_new then -- second and later buffers are off-screen
        bb.offscreen, bb._list = true, {}
    end
    real_new = true
    return bb
end
function BB._resetScreen() real_new = false end
return BB
