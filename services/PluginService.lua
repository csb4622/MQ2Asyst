local PluginService = {}
PluginService.__index = PluginService

function PluginService.new(mq, logger)
  local self = setmetatable({}, PluginService)
  self.mq = mq
  self.logger = logger
  return self
end

local function isLoaded(mq, pluginName, logger)
  local p = mq.TLO.Plugin(pluginName)
  if not p then
    if logger and logger.Debug then
      logger:Debug(string.format('[PluginService] Plugin(%s): TLO returned nil', tostring(pluginName)))
    end
    return false
  end
  if p.IsLoaded then
    local loaded = p.IsLoaded() == true
    if logger and logger.Debug then
      logger:Debug(string.format('[PluginService] Plugin(%s).IsLoaded=%s', tostring(pluginName), tostring(loaded)))
    end
    return loaded
  end
  if logger and logger.Debug then
    logger:Debug(string.format('[PluginService] Plugin(%s): No IsLoaded method', tostring(pluginName)))
  end
  return false
end

function PluginService:UnloadIfLoaded(pluginName)
  if self.logger and self.logger.Debug then
    self.logger:Debug(string.format('[PluginService] Checking if %s needs unloading', tostring(pluginName)))
  end

  if isLoaded(self.mq, pluginName, self.logger) then
    self.logger:Warn(pluginName .. ' is loaded; unloading it')
    self.mq.cmdf('/plugin unload %s', pluginName)

    if self.logger and self.logger.Debug then
      self.logger:Debug(string.format('[PluginService] Sent unload command for %s, waiting 250ms', tostring(pluginName)))
    end

    self.mq.delay(250) -- give MQ a moment to unload
    return true
  end

  if self.logger and self.logger.Debug then
    self.logger:Debug(string.format('[PluginService] %s is not loaded, no action needed', tostring(pluginName)))
  end

  return false
end

return PluginService