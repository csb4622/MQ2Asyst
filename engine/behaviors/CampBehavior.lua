local GuardSeverity = require('asyst.constants.GuardSeverity')
local GuardReason   = require('asyst.constants.GuardReason')

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

local function Ok()
  return { ok = true }
end

local function Fail(severity, reason)
  return { ok = false, severity = severity, reason = reason }
end

local function canReadPosition(mq)
  local me = mq.TLO.Me
  if not me then return false end

  local id = (me.ID and me.ID()) or 0
  if id == 0 then return false end

  local name = (me.Name and me.Name()) or ''
  if name == '' then return false end

  if not (me.X and me.Y and me.Z) then return false end
  if not (mq.TLO.Zone and mq.TLO.Zone.ID) then return false end

  local zid = mq.TLO.Zone.ID() or 0
  if zid == 0 then return false end

  return true
end

function CampBehavior:_setCampHere()
  local mq = self.mq
  local me = mq.TLO.Me
  local log = self.logger

  self.state.camp.x = me.X()
  self.state.camp.y = me.Y()
  self.state.camp.z = me.Z()
  self.state.camp.zoneId = mq.TLO.Zone.ID()

  if log and log.Debug then
    log:Debug(string.format(
      '[CampBehavior] Camp set at position: x=%.2f y=%.2f z=%.2f zoneId=%d',
      self.state.camp.x, self.state.camp.y, self.state.camp.z, self.state.camp.zoneId
    ))
  end
end

function CampBehavior:_isCampInitialized()
  local c = self.state.camp
  local log = self.logger

  if not c then
    if log and log.Debug then
      log:Debug('[CampBehavior] Camp not initialized: state.camp is nil')
    end
    return false
  end

  if (c.zoneId or 0) == 0 then
    if log and log.Debug then
      log:Debug('[CampBehavior] Camp not initialized: zoneId is 0')
    end
    return false
  end

  -- If you want stricter, also require non-zero coords; but coords can be 0 in some zones.
  if log and log.Debug then
    log:Debug('[CampBehavior] Camp is initialized')
  end
  return true
end

function CampBehavior:_ensureCampInitialized()
  local log = self.logger

  if log and log.Debug then
    log:Debug('[CampBehavior] _ensureCampInitialized() called')
  end

  if not canReadPosition(self.mq) then
    if log and log.Debug then
      log:Debug('[CampBehavior] Cannot read position, camp initialization failed')
    end
    return false
  end

  local currentZone = self.mq.TLO.Zone.ID()

  -- If camp not initialized yet OR zone changed, set/reset camp
  if (not self:_isCampInitialized()) or self.state.camp.zoneId ~= currentZone then
    if log and log.Debug then
      log:Debug(string.format(
        '[CampBehavior] Camp needs initialization: initialized=%s currentZone=%d campZone=%d',
        tostring(self:_isCampInitialized()),
        currentZone,
        (self.state.camp and self.state.camp.zoneId) or 0
      ))
    end

    self:_setCampHere()
    self.logger:Info('Camp set at current location')
  end

  return true
end

function CampBehavior:GetGuards()
  local mq = self.mq
  local log = self.logger

  if log and log.Debug then
    log:Debug('[CampBehavior] GetGuards() called')
  end

  return {
    -- Can't act guards (Pause) - same as Chase
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

    -- Must be able to read position/zone, otherwise Camp mode cannot function (Stop)
    function()
      if not canReadPosition(mq) then
        return Fail(GuardSeverity.Stop, GuardReason.CampNoPosition)
      end
      return Ok()
    end,
  }
end

function CampBehavior:Enter()
  local log = self.logger

  if log and log.Debug then
    log:Debug('[CampBehavior] Enter() called - initializing camp behavior')
  end

  self._accum = 0

  -- Attempt immediate camp set. If not possible, Stop guard will force Manual.
  -- If possible, this will initialize camp right away.
  local initialized = self:_ensureCampInitialized()

  if log and log.Debug then
    log:Debug(string.format('[CampBehavior] Camp initialization result: %s', tostring(initialized)))
  end

  self.logger:Info('Camp mode active')
end

function CampBehavior:Tick(dt)
  local log = self.logger

  self._accum = self._accum + dt
  if self._accum < self._interval then return end
  self._accum = 0

  if log and log.Debug then
    log:Debug('[CampBehavior] Tick() processing camp enforcement')
  end

  -- GUARANTEE camp is initialized before any enforcement logic runs
  if not self:_ensureCampInitialized() then
    -- This should not happen because the Stop guard should have kicked us out,
    -- but keep it defensive.
    if log and log.Debug then
      log:Debug('[CampBehavior] Tick() early exit: camp initialization failed')
    end
    return
  end

  -- Camp enforcement (radius/nav) comes next
  if log and log.Debug then
    log:Debug('[CampBehavior] Camp enforcement placeholder - will be implemented')
  end
end

function CampBehavior:Exit()
  local log = self.logger

  if log and log.Debug then
    log:Debug('[CampBehavior] Exit() called - exiting camp behavior')
  end

  -- Later: stop nav if needed
end

return CampBehavior