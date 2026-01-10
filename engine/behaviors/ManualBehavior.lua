local ManualBehavior = {}
ManualBehavior.__index = ManualBehavior

function ManualBehavior.new(mq, state, logger)
  local self = setmetatable({}, ManualBehavior)
  self.mq = mq
  self.state = state
  self.logger = logger
  return self
end

function ManualBehavior:Enter()
  -- Later: stop any active nav, clear targets, etc.
  -- Example (when you decide): self.mq.cmd('/nav stop')
  self.logger:Info('Manual mode active')
end

function ManualBehavior:Tick(dt)
  -- Do nothing. User controls character.
end

function ManualBehavior:Exit()
  -- Usually nothing
end

return ManualBehavior