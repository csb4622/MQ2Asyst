local GuardSeverity = require('asyst.constants.GuardSeverity')
local GuardReason = require('asyst.constants.GuardReason')

local HunterBehavior = {}
HunterBehavior.__index = HunterBehavior

function HunterBehavior.new(mq, state, logger)
  local self = setmetatable({}, HunterBehavior)
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

function HunterBehavior:GetGuards()
  local mq = self.mq
  local state = self.state
  local log = self.logger

  if log and log.Debug then
    log:Debug('[HunterBehavior] GetGuards() called')
  end

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

    -- Needs a Main Assist name to hunt targets (Stop)
    function()
      local ma = state.group and state.group.roles and state.group.roles.mainAssist or nil
      if not ma or ma == '' then
        return Fail(GuardSeverity.Stop, GuardReason.NoMainAssist)
      end
      return Ok()
    end,
  }
end

function HunterBehavior:Enter()
  local log = self.logger

  if log and log.Debug then
    log:Debug('[HunterBehavior] Enter() called - initializing hunter behavior')
  end

  self._accum = 0
  self.logger:Info('Hunter mode active')
end

function HunterBehavior:Tick(dt)
  local log = self.logger

  self._accum = self._accum + dt
  if self._accum < self._interval then return end
  self._accum = 0

  if log and log.Debug then
    log:Debug('[HunterBehavior] Tick() processing hunter logic')
  end

  -- Hunter behavior execution will come later (target acquisition / engagement logic).
  if log and log.Debug then
    log:Debug('[HunterBehavior] Hunter logic placeholder - will be implemented')
  end
end

function HunterBehavior:Exit()
  local log = self.logger

  if log and log.Debug then
    log:Debug('[HunterBehavior] Exit() called - exiting hunter behavior')
  end

  -- Later: stop hunting / disengage
end

return HunterBehavior
