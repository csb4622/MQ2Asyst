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
      self.state.ui.isOpen = true
    end,

    hide = function()
      self.state.ui.isOpen = false
    end,

    toggle = function()
      self.state.ui.isOpen = not self.state.ui.isOpen
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
  }

  return self
end

function CommandService:Register()
  self.mq.bind('/asyst', function(...)
    local args = { ... } -- arg1, arg2, arg3...
    local sub = string.lower(tostring(args[1] or ''))

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

    handler(args)
  end)
end


function CommandService:PrintHelp()
  self.logger:Info('Usage: /asyst show|hide|toggle|mode <number>')
end

return CommandService