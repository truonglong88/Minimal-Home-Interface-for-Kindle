return {
    is_wifi_on = true, is_connected = true,
    getWifiState = function(self) return self.is_wifi_on end,
    getConnectionState = function(self) return self.is_connected end,
    isWifiOn = function(self) return self.is_wifi_on end,
    toggleWifiOn = function(self, cb) self.is_wifi_on = true if cb then cb() end end,
    toggleWifiOff = function(self, cb) self.is_wifi_on = false self.is_connected = false if cb then cb() end end,
}
