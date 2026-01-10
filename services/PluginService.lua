local PluginService = {}
PluginService.__index = PluginService

function PluginService.new(mq, logger)
  local self = setmetatable({}, PluginService)
  self.mq = mq
  self.logger = logger
  return self
end

local function isLoaded(mq, pluginName)
  local p = mq.TLO.Plugin(pluginName)
  if not p then return false end
  if p.IsLoaded then
    return p.IsLoaded() == true
  end
  return false
end

function PluginService:UnloadIfLoaded(pluginName)
  if isLoaded(self.mq, pluginName) then
    self.logger:Warn(pluginName .. ' is loaded; unloading it')
    self.mq.cmdf('/plugin unload %s', pluginName)
    self.mq.delay(250) -- give MQ a moment to unload
    return true
  end
  return false
end

return PluginService