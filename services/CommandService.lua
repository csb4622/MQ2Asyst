local CommandService = {}
CommandService.__index = CommandService

local function splitArgs(cmd)
  cmd = tostring(cmd or '')

  -- Trim trailing control characters (e.g. \r \n)
  cmd = cmd:gsub('%c+$', '')

  local args = {}
  for w in cmd:gmatch('%S+') do
    table.insert(args, w)
  end
  return args, cmd
end

function CommandService.new(mq, state, logger, engine)
  local self = setmetatable({}, CommandService)
  self.mq = mq
  self.state = state
  self.logger = logger
  self.engine = engine

  self._handlers = {
    show = function()
       self.logger:Debug('[CommandService] Setting UI open=true')
       self.state.ui.isOpen = true
    end,

    hide = function()
      self.logger:Debug('[CommandService] Setting UI open=false')
      self.state.ui.isOpen = false
    end,

    toggle = function()
      local newState = not self.state.ui.isOpen
      self.logger:Debug(string.format('[CommandService] Toggling UI: %s -> %s', tostring(self.state.ui.isOpen), tostring(newState)))
      self.state.ui.isOpen = newState
    end,

    mode = function(args)
      local n = tonumber(args[2])
      if n == nil then
        self.logger:Warn('Usage: /asyst mode <number>')
        return
      end

      self.state.options.mode = n
      if self.engine and self.engine.RequestMode then
        self.engine:RequestMode(n)
      end

      self.logger:Debug('Requested mode: ' .. tostring(n))
    end,

    pause = function()
      self.state.app.isPaused = true
      self.logger:Info('Plugin paused')
    end,

    resume = function()
      self.state.app.isPaused = false
      self.logger:Info('Plugin resumed')
    end,

    exit = function()
      self.state.app.isRunning = false
      self.logger:Info('Exiting Plugin')
    end,	
  }

  return self
end

function CommandService:Register()
   self.logger:Debug('[CommandService] Registering /asyst command')
 
   self.mq.bind('/asyst', function(...)
    local args = { ... } -- arg1, arg2, arg3...
    local sub = string.lower(tostring(args[1] or ''))

    self.logger:Debug(string.format('[CommandService] Command received: /asyst %s', sub))

    if sub == '' then
      self:PrintHelp()
      return
    end

    local handler = self._handlers[sub]
    if not handler then
      self.logger:Warn('Unknown command: ' .. sub)
      self:PrintHelp()
      return
    end

    if self.logger and self.logger.Debug then
      self.logger:Debug(string.format('[CommandService] Executing handler for: %s', sub))
    end

    handler(args)
  end)
end


function CommandService:PrintHelp()
  self.logger:Info('Usage: /asyst show|hide|toggle|mode <number>|pause|resume|exit')
end

return CommandService