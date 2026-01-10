local CampBehavior = {}
CampBehavior.__index = CampBehavior

function CampBehavior.new(mq, state, logger)
  local self = setmetatable({}, CampBehavior)
  self.mq = mq
  self.state = state
  self.logger = logger

  self._accum = 0
  self._interval = 0.25

  return self
end

function CampBehavior:Enter()
  self._accum = 0
  self.logger:Info('Camp mode active')
end

function CampBehavior:Tick(dt)
  self._accum = self._accum + dt
  if self._accum < self._interval then
    return
  end
  self._accum = 0

  -- Future:
  -- if camp not set: set camp at current position or idle
  -- else: if too far, nav back
end

function CampBehavior:Exit()
  -- Future: stop nav/return
end

return CampBehavior
