local Logger = {}
Logger.__index = Logger

function Logger.new(prefix, logFilePath)
  local self = setmetatable({}, Logger)
  self.prefix = prefix or '[Asyst]'
  self.sink = nil -- optional: function(line)
  self.filePath = logFilePath
  self.file = nil

  if logFilePath then
    -- append mode
    local f, err = io.open(logFilePath, 'a')
    if f then
      self.file = f
      f:write(string.format('\n---- Logger started %s ----\n', os.date()))
      f:flush()
    else
      print(string.format('%s [ERR ] Failed to open log file: %s', self.prefix, tostring(err)))
    end
  end

  return self
end

function Logger:SetSink(fn)
  self.sink = fn
end

function Logger:_emit(level, msg)
  local line = string.format('%s %s %s', self.prefix, level, msg)

  -- console
  print(line)

  -- optional UI sink
  if self.sink then
    self.sink(line)
  end

  -- file
  if self.file then
    self.file:write(line .. '\n')
    self.file:flush()
  end
end

function Logger:Debug(msg) self:_emit('[Debug]', msg) end
function Logger:Info(msg)  self:_emit('[INFO ]', msg) end
function Logger:Warn(msg)  self:_emit('[WARN ]', msg) end
function Logger:Error(msg) self:_emit('[ERR  ]', msg) end

function Logger:Close()
  if self.file then
    self.file:write(string.format('---- Logger closed %s ----\n', os.date()))
    self.file:flush()
    self.file:close()
    self.file = nil
  end
end

return Logger