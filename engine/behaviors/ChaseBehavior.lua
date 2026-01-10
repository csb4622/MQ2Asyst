local ChaseBehavior = {}
ChaseBehavior.__index = ChaseBehavior

function ChaseBehavior.new(mq, state, logger)
  local self = setmetatable({}, ChaseBehavior)
  self.mq = mq
  self.state = state
  self.logger = logger

  self._accum = 0
  self._interval = 0.25 -- seconds between chase evaluations

  return self
end

function ChaseBehavior:Enter()
  self._accum = 0
  self.logger:Info('Chase mode active')
end

function ChaseBehavior:Tick(dt)
  self._accum = self._accum + dt
  if self._accum < self._interval then
    return
  end
  self._accum = 0

  -- Future:
  -- 1) resolve MA from state.group.roles.mainAssist
  -- 2) ensure mq2nav loaded
  -- 3) issue nav follow command
  -- For now: no-op
end

function ChaseBehavior:Exit()
  -- Future: stop nav
  -- self.mq.cmd('/nav stop')
end

return ChaseBehavior