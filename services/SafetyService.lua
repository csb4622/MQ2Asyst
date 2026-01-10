local SafetyService = {}
SafetyService.__index = SafetyService

function SafetyService.new(mq, logger)
  local self = setmetatable({}, SafetyService)
  self.mq = mq
  self.logger = logger
  self._lastReason = nil
  self._lastLogAt = 0
  self._logEverySeconds = 2.0
  return self
end

local function boolVal(x)
  return x == true
end

function SafetyService:Check()
  local mq = self.mq
  local me = mq.TLO.Me
  local log = self.logger

  if log and log.Debug then
    log:Debug('[SafetyService] Check() called')
  end

  -- If Me doesn't exist / no name, we're not in-game yet (char select / loading)
  local myName = (me and me.Name and me.Name()) or nil
  if not myName or myName == '' then
    if log and log.Debug then
      log:Debug(string.format('[SafetyService] Not in game: myName=%s', tostring(myName)))
    end
    return { ok = false, reason = 'Not in game (character not loaded)', severity = 'Stop' }
  end

  -- Zoning / loading screens
  if me.Zoning and boolVal(me.Zoning()) then
    if log and log.Debug then
      log:Debug('[SafetyService] Character is zoning')
    end
    return { ok = false, reason = 'Zoning', severity = 'Pause' }
  end

  -- Dead
  if me.Dead and boolVal(me.Dead()) then
    if log and log.Debug then
      log:Debug('[SafetyService] Character is dead')
    end
    return { ok = false, reason = 'Dead', severity = 'Stop' }
  end

  -- Crowd control / unable to act (treat as Pause)
  if me.Stunned and boolVal(me.Stunned()) then
    if log and log.Debug then
      log:Debug('[SafetyService] Character is stunned')
    end
    return { ok = false, reason = 'Stunned', severity = 'Pause' }
  end
  if me.Mezzed and boolVal(me.Mezzed()) then
    if log and log.Debug then
      log:Debug('[SafetyService] Character is mezzed')
    end
    return { ok = false, reason = 'Mezzed', severity = 'Pause' }
  end
  if me.Charmed and boolVal(me.Charmed()) then
    if log and log.Debug then
      log:Debug('[SafetyService] Character is charmed')
    end
    return { ok = false, reason = 'Charmed', severity = 'Pause' }
  end
  if me.Feared and boolVal(me.Feared()) then
    if log and log.Debug then
      log:Debug('[SafetyService] Character is feared')
    end
    return { ok = false, reason = 'Feared', severity = 'Pause' }
  end

  -- Optional: casting guard (class dependent; start with Pause)
  if me.Casting and boolVal(me.Casting()) then
    if log and log.Debug then
      log:Debug('[SafetyService] Character is casting')
    end
    return { ok = false, reason = 'Casting', severity = 'Pause' }
  end

  if log and log.Debug then
    log:Debug('[SafetyService] All checks passed, character is safe')
  end

  return { ok = true }
end

function SafetyService:ShouldLog(reason)
  local now = os.clock()
  if self._lastReason ~= reason then
    self._lastReason = reason
    self._lastLogAt = now
    return true
  end
  if (now - self._lastLogAt) >= self._logEverySeconds then
    self._lastLogAt = now
    return true
  end
  return false
end

return SafetyService
