local GuardSeverity = require('asyst.constants.GuardSeverity')
local GuardReason = require('asyst.constants.GuardReason')

local ChaseBehavior = {}
ChaseBehavior.__index = ChaseBehavior

function ChaseBehavior.new(mq, state, logger)
  local self = setmetatable({}, ChaseBehavior)
  self.mq = mq
  self.state = state
  self.logger = logger

  self._accum = 0
  self._interval = 0.25

  return self
end

local function Ok()
  return { ok = true }
end

local function Fail(severity, reason)
  return { ok = false, severity = severity, reason = reason }
end

function ChaseBehavior:GetGuards()
  local mq = self.mq
  local state = self.state

  return {
    -- Crowd control / unable to act (Pause)
    function()
      local me = mq.TLO.Me
      if me.Stunned and me.Stunned() then
        return Fail(GuardSeverity.Pause, GuardReason.Stunned)
      end
      if me.Mezzed and me.Mezzed() then
        return Fail(GuardSeverity.Pause, GuardReason.Mezzed)
      end
      if me.Charmed and me.Charmed() then
        return Fail(GuardSeverity.Pause, GuardReason.Charmed)
      end
      if me.Feared and me.Feared() then
        return Fail(GuardSeverity.Pause, GuardReason.Feared)
      end
      return Ok()
    end,

    -- Needs a Main Assist name to chase (Stop)
    function()
      local ma = state.group and state.group.roles and state.group.roles.mainAssist or nil
      if not ma or ma == '' then
        return Fail(GuardSeverity.Stop, GuardReason.NoMainAssist)
      end
      return Ok()
    end,
  }
end

function ChaseBehavior:Enter()
  self._accum = 0
  self.logger:Info('Chase mode active')
end

function ChaseBehavior:Tick(dt)
  self._accum = self._accum + dt
  if self._accum < self._interval then return end
  self._accum = 0

  -- Chase behavior execution will come later (MQ2Nav integration).
end

function ChaseBehavior:Exit()
  -- Later: stop nav
end

return ChaseBehavior
