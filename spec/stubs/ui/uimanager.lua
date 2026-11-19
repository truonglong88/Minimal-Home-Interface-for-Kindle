local U = {}
function U:show() end
function U:close() end
function U:setDirty() end
function U:scheduleIn() end
function U:nextTick(f) end
function U:unschedule() end
function U:broadcastEvent() end
function U:sendEvent() end
function U:getRefreshRate() return G_reader_settings:readSetting("full_refresh_count") or 6 end
function U:setRefreshRate() end
function U:forceRePaint() end
function U:restartKOReader() end
function U:quit() end
return U
