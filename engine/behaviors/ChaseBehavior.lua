local GuardSeverity = require('asyst.constants.GuardSeverity')
local GuardReason = require('asyst.constants.GuardReason')
local ChaseStatus = require('asyst.constants.ChaseStatus')

local ChaseBehavior = {}
ChaseBehavior.__index = ChaseBehavior

function ChaseBehavior.new(mq, state, logger)
  local self = setmetatable({}, ChaseBehavior)
  self.mq = mq
  self.state = state
  self.logger = logger

  self._accum = 0
  self._interval = 0.25

  self._lastX = nil
  self._lastY = nil
  self._lastZ = nil
  self._lastMovedAt = os.clock()
  self._stuckSeconds = 3.0
  self._minMoveDistance = 1.0

  -- Our own nav tracking (do not treat any nav as ours)
  self._navActive = false
  self._navTargetId = 0
  self._navIssuedAt = 0

  return self
end

local function Ok()
  return { ok = true }
end

local function Fail(severity, reason)
  return { ok = false, severity = severity, reason = reason }
end

local function clampNumber(val, minVal, maxVal)
  if val == nil then return nil end
  local n = tonumber(val)
  if not n then return nil end
  if minVal and n < minVal then return minVal end
  if maxVal and n > maxVal then return maxVal end
  return n
end

function ChaseBehavior:GetGuards()
  local mq = self.mq
  local state = self.state

  return {
    function()
      local me = mq.TLO.Me
      if not me then
        return Fail(GuardSeverity.Stop, GuardReason.NoMe)
      end
      if me.Dead and me.Dead() then
        return Fail(GuardSeverity.Stop, GuardReason.Dead)
      end
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

    function()
      local ma = state.group and state.group.roles and state.group.roles.mainAssist or nil
      if not ma or ma == '' then
        return Fail(GuardSeverity.Stop, GuardReason.NoMainAssist)
      end
      return Ok()
    end,
  }
end

function ChaseBehavior:_writeState(status, maName, maDist)
  local chase = self.state.chase
  local log = self.logger

  if not chase then
    log:Warn('[ChaseBehavior] _writeState() skipped: state.chase is nil')
    return
  end

  chase.nav = chase.nav or { active = false, targetId = 0, issuedAt = 0 }

  local eps = 0.05 -- distance noise tolerance
  local prevStatus = chase.status
  local prevName = chase.mainAssistName
  local prevDist = chase.mainAssistDistance or 0
  local nextDist = maDist or prevDist

  local changed =
    prevStatus ~= status or
    prevName ~= maName or
    math.abs(prevDist - nextDist) > eps or
    chase.nav.active ~= self._navActive or
    chase.nav.targetId ~= self._navTargetId or
    chase.nav.issuedAt ~= self._navIssuedAt

  if not changed then
    return
  end

  chase.status = status or chase.status
  chase.mainAssistName = maName
  chase.mainAssistDistance = nextDist

  chase.nav.active = self._navActive
  chase.nav.targetId = self._navTargetId
  chase.nav.issuedAt = self._navIssuedAt

  log:Debug(string.format(
    '[ChaseBehavior] State updated: status=%s maName=%s maDist=%.2f navActive=%s',
    tostring(chase.status), tostring(maName), nextDist or 0, tostring(self._navActive)
  ))
end

function ChaseBehavior:_stopNav()
  local log = self.logger

  if self._navActive then
    log:Debug('[ChaseBehavior] Stopping navigation')
    self.mq.cmd('/nav stop')
  end

  self._navActive = false
  self._navTargetId = 0
  self._navIssuedAt = 0
end

function ChaseBehavior:_resetChase()
  -- Full chase reset (used when entering/leaving chase, MA missing, etc.)
  self:_stopNav()
  self:_writeState(ChaseStatus.None, nil, 0)
end

function ChaseBehavior:Enter()
  local log = self.logger

  log:Debug('[ChaseBehavior] Enter() called - initializing chase behavior')

  self._accum = 0

  local me = self.mq.TLO.Me
  if me and me.X and me.Y and me.Z then
    self._lastX, self._lastY, self._lastZ = me.X(), me.Y(), me.Z()
    self._lastMovedAt = os.clock()

    log:Debug(string.format(
      '[ChaseBehavior] Initial position: x=%.2f y=%.2f z=%.2f',
      self._lastX, self._lastY, self._lastZ
    ))
  else
    log:Warn('[ChaseBehavior] Could not read initial position')
  end

  self:_resetChase()
  self.logger:Info('Chase mode active')
end

function ChaseBehavior:Tick(dt)
  local log = self.logger
  self._accum = self._accum + (dt or 0)

  if self._accum < self._interval then return end
  self._accum = 0

  local mq = self.mq
  local state = self.state
  local chase = state.chase

  if not chase then
    log:Warn('[ChaseBehavior] Tick() early exit: state.chase is nil')
    return
  end

  local chaseDistance = clampNumber(chase.chaseDistance, 5, 500) or 25
  if chase.chaseDistance ~= chaseDistance then
    chase.chaseDistance = chaseDistance
    log:Debug(string.format('[ChaseBehavior] Chase distance: %d', chaseDistance))
  end  

  local maName = state.group and state.group.roles and state.group.roles.mainAssist or nil  -- need to set this with some type of an event instead of polling it every time
  chase.mainAssistName = maName

  if not maName or maName == '' then
    log:Warn('[ChaseBehavior] No main assist defined, resetting chase')
    self:_stopNav()
    self:_writeState(ChaseStatus.NotFound, nil, 0)
    return
  end

  -- Lookup MA spawn by name. (This uses MQ for existence/distance only.)
  local maSpawn = mq.TLO.Spawn('pc ' .. maName)
  local maId = (maSpawn and maSpawn.ID and maSpawn.ID()) or 0
  if maId == 0 then
    log:Warn(string.format('[ChaseBehavior] Main assist %s not found', maName))
    self:_stopNav()
    self:_writeState(ChaseStatus.NotFound, maName, 0)
    return
  end

  local dist = (maSpawn.Distance and maSpawn.Distance()) or 0
  chase.mainAssistDistance = dist
  
  -- Close enough: stop our nav.
  if dist <= chaseDistance then
    log:Debug(string.format('[ChaseBehavior] At target: dist=%.2f <= chaseDistance=%d', dist, chaseDistance))
    self:_stopNav()
    self:_writeState(ChaseStatus.AtTarget, maName, dist)
    return
  end

  -- Can't nav without a mesh.
  if not (mq.TLO.Navigation and mq.TLO.Navigation.MeshLoaded and mq.TLO.Navigation.MeshLoaded()) then
    log:Error('[ChaseBehavior] Navigation mesh not loaded, cannot chase')
    self:_stopNav()
    self:_writeState(ChaseStatus.NotFound, maName, dist)
    return
  end

  -- If we are not currently running *our* nav, start it.
  if not self._navActive then
    log:Debug(string.format(
      '[ChaseBehavior] Starting navigation to MA: targetId=%d distance=%d',
      maId, chaseDistance
    ))

    self._navActive = true
    self._navTargetId = maId
    self._navIssuedAt = os.clock()

    -- Tag is still useful to observers/APIs, but UI does not rely on it.
    mq.cmd(('/nav id %d distance=%d log=off tag=asyst_chase'):format(maId, chaseDistance))

    self:_writeState(ChaseStatus.Moving, maName, dist)
  else
    -- We are "moving" only if our chase behavior believes it's active.
    -- Do NOT mirror any external nav state into the UI.
    log:Debug(string.format('[ChaseBehavior] Navigation already active: targetId=%d', self._navTargetId))
    self:_writeState(ChaseStatus.Moving, maName, dist)
  end

  -- Stuck detection only while our nav is active.
  if self._navActive then
    local me = mq.TLO.Me
    if me and me.X and me.Y and me.Z then
      local x, y, z = me.X(), me.Y(), me.Z()

      if self._lastX and self._lastY and self._lastZ then
        local dx = x - self._lastX
        local dy = y - self._lastY
        local dz = z - self._lastZ
        local moved = math.sqrt(dx * dx + dy * dy + dz * dz)

        if moved >= self._minMoveDistance then
          self._lastMovedAt = os.clock()
          self._lastX, self._lastY, self._lastZ = x, y, z
        else
          local stuckFor = os.clock() - (self._lastMovedAt or os.clock())
          if stuckFor >= self._stuckSeconds then
            log:Warn(string.format('[ChaseBehavior] Detected stuck (%.2fs). Reissuing nav.', stuckFor))
            -- Reissue nav
            self._navIssuedAt = os.clock()
            mq.cmd(('/nav id %d distance=%d log=off tag=asyst_chase'):format(maId, chaseDistance))
            self._lastMovedAt = os.clock()
          end
        end
      else
        self._lastX, self._lastY, self._lastZ = x, y, z
        self._lastMovedAt = os.clock()
      end
    end
  end
end

function ChaseBehavior:Exit()
  local log = self.logger

  log:Debug('[ChaseBehavior] Exit() called - exiting chase behavior')
  self:_resetChase()
end

return ChaseBehavior
