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
  local log = self.logger

  if log and log.Debug then
    log:Debug('[ManualBehavior] Enter() called - initializing manual behavior')
  end

  -- Later: stop any active nav, clear targets, etc.
  -- Example (when you decide): self.mq.cmd('/nav stop')
  self.logger:Info('Manual mode active')
end

function ManualBehavior:Tick(dt)
  local log = self.logger

  -- Do nothing. User controls character.
  -- Note: Debug logging intentionally minimal for manual mode to reduce noise
end

function ManualBehavior:Exit()
  local log = self.logger

  if log and log.Debug then
    log:Debug('[ManualBehavior] Exit() called - exiting manual behavior')
  end

  -- Usually nothing
end

return ManualBehavior