local util = {}
function util.splitFilePathName(p) return p:match("^(.*/)([^/]*)$") end
function util.splitFileNameSuffix(f) return f:match("^(.*)%.([^.]*)$") end
function util.getFileNameSuffix(f) return f:match("%.([^.]*)$") end
-- copied from KOReader's util.lua (used by the Telex keyboard)
local WrappedFunction_mt = {
    __call = function(self, ...)
        if self.before_callback then
            self.before_callback(self.target_table, ...)
        end
        if self.func then
            return self.func(...)
        end
    end,
}

--- Wrap (or replace) a table method with a custom method, in a revertable way.
-- This allows you extend the features of an existing module by modifying its
-- internal methods, and then revert them back to normal later if necessary.
--
-- The most notable use-case for this is VirtualKeyboard's inputbox method
-- wrapping to allow keyboards to add more complicated state-machines to modify
-- how characters are input.
--
-- The returned table is the same table `target_table[target_field_name]` is
-- set to. In addition to being callable, the new method has two sub-methods:
--
--  * `:revert()` will un-wrap the method and revert it to the original state.
--
--    Note that if a method is wrapped multiple times, reverting it will revert
--    it to the state of the method when util.wrapMethod was called (and if
--    called on the table returned from util.wrapMethod, that is the state when
--    that particular util.wrapMethod was called).
--
--  * `:raw_call(...)` will call the original method with the given arguments
--    and return whatever it returns.
--
--    This makes it more ergonomic to use the wrapped table methods in the case
--    where you've replaced the regular function with your own implementation
--    but you need to call the original functions inside your implementation.
--
--  * `:raw_method_call(...)` will call the original method with the arguments
--    `(target_table, ...)` and return whatever it returns. Note that the
--    target_table used is the one associated with the util.wrapMethod call.
--
--    This makes it more ergonomic to use the wrapped table methods in the case
--    where you've replaced the regular function with your own implementation
--    but you need to call the original functions inside your implementation.
--
--    This is effectively short-hand for `:raw_call(target_table, ...)`.
--
-- This is loosely based on busted/luassert's spies implementation (MIT).
--   <https://github.com/Olivine-Labs/luassert/blob/v1.7.11/src/spy.lua>
--
-- @tparam table target_table The table whose method will be wrapped.
-- @tparam string target_field_name The name of the field to wrap.
-- @tparam nil|func new_func If non-nil, this function will be called instead of the original function after wrapping.
-- @tparam nil|func before_callback If non-nil, this function will be called (with the arguments (target_table, ...)) before the function is called.
function util.wrapMethod(target_table, target_field_name, new_func, before_callback)
    local old_func = target_table[target_field_name]
    local wrapped = setmetatable({
        target_table = target_table,
        target_field_name = target_field_name,
        old_func = old_func,

        before_callback = before_callback,
        func = new_func or old_func,

        revert = function(self)
            if not self.reverted then
                self.target_table[self.target_field_name] = self.old_func
                self.reverted = true
            end
        end,

        raw_call = function(self, ...)
            if self.old_func then
                return self.old_func(...)
            end
        end,

        raw_method_call = function(self, ...)
            return self:raw_call(self.target_table, ...)
        end,
    }, WrappedFunction_mt)
    target_table[target_field_name] = wrapped
    return wrapped
end

function util.splitToChars(text)
    local t = {}
    if text then for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = ch end end
    return t
end
function util.arrayContains(t, v)
    for i, x in ipairs(t) do if x == v then return i end end
    return false
end

function util.tableDeepCopy(o, seen)
  seen = seen or {}
  if o == nil then return nil end
  if seen[o] then return seen[o] end

  local no
  if type(o) == "table" then
    no = {}
    seen[o] = no

    for k, v in next, o, nil do
      no[util.tableDeepCopy(k, seen)] = util.tableDeepCopy(v, seen)
    end
    setmetatable(no, util.tableDeepCopy(getmetatable(o), seen))
  else -- number, string, boolean, etc
    no = o
  end
  return no
end

return util
