local Logger = {}
Logger.__index = Logger

function Logger.new(prefix)
  local self = setmetatable({}, Logger)
  self.prefix = prefix or '[Asyst]'
  self.sink = nil -- optional: set to a function(line) to also push into console
  return self
end

function Logger:SetSink(fn)
  self.sink = fn
end

function Logger:_emit(level, msg)
  local line = string.format('%s %s %s', self.prefix, level, msg)
  print(line)
  if self.sink then self.sink(line) end
end

function Logger:Debug(msg) self:_emit('[Debug]', msg) end
function Logger:Info(msg) self:_emit('[INFO]', msg) end
function Logger:Warn(msg) self:_emit('[WARN]', msg) end
function Logger:Error(msg) self:_emit('[ERR ]', msg) end

return Logger