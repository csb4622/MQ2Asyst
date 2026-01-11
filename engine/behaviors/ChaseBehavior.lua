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

  -- Stuck detection
  self._lastX = nil
  self._lastY = nil
  self._lastZ = nil
  self._lastMovedAtMs = 0
  self._stuckSeconds = 3.0
  self._minMoveDistance = 1.0

  -- Prefer MQ2Nav velocity for movement detection.
  self._minVelocity = 0.10

  -- Grace window after issuing /nav to avoid false stuck during path calc/turn-in-place.
  self._navGraceMs = 1500

  -- If nav doesn't actually start, reissue /nav.
  self._navStartTimeoutMs = 2000
  self._navReissueCooldownMs = 1000
  self._lastNavReissueAtMs = 0

  -- Debounce "not active" before reissuing to avoid thrash during brief nav recalcs.
  self._navNotActiveSinceMs = 0
  self._navNotActiveDebounceMs = 800 -- must be continuously not-active this long
  self._navReissueVelocityMax = 0.15 -- only reissue if essentially not moving

  -- Hysteresis to prevent stop/start thrash at the chase distance boundary.
  -- Enter AtTarget at dist <= chaseDistance; leave AtTarget only when dist >= chaseDistance + hysteresis.
  self._atTargetHysteresis = 5.0

  -- Rate-limited nav-state debug while moving.
  self._lastNavStateLogAtMs = 0
  self._navStateLogIntervalMs = 1000

  -- Our own nav tracking
  self._navActive = false
  self._navTargetId = 0
  self._navIssuedAtMs = 0

  -- FSM state
  self._fsmState = ChaseStatus.None

  return self
end

local function Ok()
  return { ok = true }
end

local function Fail(severity, reason)
  return { ok = false, severity = severity, reason = reason }
end

local function clampNumber(v, minV, maxV)
  v = tonumber(v)
  if not v then return nil end
  if minV ~= nil and v < minV then v = minV end
  if maxV ~= nil and v > maxV then v = maxV end
  return v
end

local function sqr(n) return n * n end
local function dist3(x1, y1, z1, x2, y2, z2)
  return math.sqrt(sqr(x1 - x2) + sqr(y1 - y2) + sqr(z1 - z2))
end

function ChaseBehavior:_nowMs()
  if self.mq and self.mq.gettime then
    local t = self.mq.gettime()
    if t ~= nil then return t end
  end
  return math.floor((os.clock() or 0) * 1000)
end

-- Robust Navigation member read:
-- TLO members are often callable userdata; try calling first, then treat as a value.
function ChaseBehavior:_navMember(name)
  local nav = self.mq and self.mq.TLO and self.mq.TLO.Navigation or nil
  if not nav then return nil end

  local m = nav[name]
  if m == nil then return nil end

  local ok, val = pcall(m)
  if ok then return val end

  return m
end

function ChaseBehavior:_navActiveMq()
  local v = self:_navMember('Active')
  if v == nil then return nil end
  return v and true or false
end

function ChaseBehavior:_navPausedMq()
  local v = self:_navMember('Paused')
  if v == nil then return nil end
  return v and true or false
end

function ChaseBehavior:_navVelocityMq()
  local v = self:_navMember('Velocity')
  if v == nil then return nil end
  return tonumber(v)
end

function ChaseBehavior:_meshLoaded()
  local v = self:_navMember('MeshLoaded')
  if v == nil then return false end
  return v and true or false
end

function ChaseBehavior:GetGuards()
  local mq = self.mq
  local state = self.state

  return {
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

  chase.status = status or chase.status
  chase.mainAssistName = maName
  chase.mainAssistDistance = maDist or chase.mainAssistDistance

  chase.nav = chase.nav or { active = false, targetId = 0, issuedAt = 0 }
  chase.nav.active = self._navActive
  chase.nav.targetId = self._navTargetId
  chase.nav.issuedAt = self._navIssuedAtMs

  log:Debug(string.format(
    '[ChaseBehavior] State updated: status=%s maName=%s maDist=%.2f navActive=%s',
    tostring(status), tostring(maName), maDist or 0, tostring(self._navActive)
  ))
end

function ChaseBehavior:_writeTelemetry(maName, maDist)
  local chase = self.state.chase
  if not chase then return end

  chase.mainAssistName = maName
  chase.mainAssistDistance = maDist

  chase.nav = chase.nav or { active = false, targetId = 0, issuedAt = 0 }
  chase.nav.active = self._navActive
  chase.nav.targetId = self._navTargetId
  chase.nav.issuedAt = self._navIssuedAtMs
end

function ChaseBehavior:_stopNav()
  local log = self.logger

  if self._navActive then
    log:Debug('[ChaseBehavior] Stopping navigation')
    self.mq.cmd('/nav stop')
  end

  self._navActive = false
  self._navTargetId = 0
  self._navIssuedAtMs = 0
  self._navNotActiveSinceMs = 0
end

function ChaseBehavior:_issueNav(targetId, chaseDistance, reason)
  local mq = self.mq
  local log = self.logger

  if reason then
    log:Debug(string.format('[ChaseBehavior] Issuing /nav (%s): targetId=%d distance=%d', reason, targetId, chaseDistance))
  else
    log:Debug(string.format('[ChaseBehavior] Issuing /nav: targetId=%d distance=%d', targetId, chaseDistance))
  end

  self._navActive = true
  self._navTargetId = targetId
  self._navIssuedAtMs = self:_nowMs()

  -- Reset debounce tracking on each issuance.
  self._navNotActiveSinceMs = 0

  mq.cmd(('/nav id %d distance=%d log=off tag=asyst_chase'):format(targetId, chaseDistance))
end

function ChaseBehavior:_startNav(targetId, chaseDistance)
  self.logger:Debug(string.format(
    '[ChaseBehavior] Starting navigation to MA: targetId=%d distance=%d',
    targetId, chaseDistance
  ))
  self:_issueNav(targetId, chaseDistance, 'start')
end

function ChaseBehavior:_resetStuckTracking()
  self._lastX, self._lastY, self._lastZ = nil, nil, nil
  self._lastMovedAtMs = self:_nowMs()
end

function ChaseBehavior:_logNavStateIfNeeded()
  local nowMs = self:_nowMs()
  if self._lastNavStateLogAtMs > 0 and (nowMs - self._lastNavStateLogAtMs) < self._navStateLogIntervalMs then
    return
  end
  self._lastNavStateLogAtMs = nowMs

  local a = self:_navActiveMq()
  local p = self:_navPausedMq()
  local v = self:_navVelocityMq()
  self.logger:Debug(string.format(
    '[ChaseBehavior] NavState: Active=%s Paused=%s Velocity=%s',
    tostring(a), tostring(p), tostring(v)
  ))
end

-- Ensure nav actually starts; if Active is false/unknown for long enough, reissue with cooldown.
-- Debounced to avoid reissue churn when Active briefly flips false during recalculation.
function ChaseBehavior:_ensureNavRunning(facts)
  if not self._navActive or self._navTargetId == 0 then return end

  local nowMs = self:_nowMs()

  -- Give /nav some time to start.
  if self._navIssuedAtMs > 0 and (nowMs - self._navIssuedAtMs) < self._navStartTimeoutMs then
    return
  end

  local activeMq = self:_navActiveMq()
  local pausedMq = self:_navPausedMq()
  local vel = self:_navVelocityMq() or 0

  -- If MQ says it's active, reset debounce tracking and we're done.
  if activeMq == true then
    self._navNotActiveSinceMs = 0
    return
  end

  -- If paused, don't thrash; also reset debounce so we don't immediately reissue after pause clears.
  if pausedMq == true then
    self._navNotActiveSinceMs = 0
    return
  end

  -- Only reissue if we're essentially not moving (prevents reissue while running).
  if vel > self._navReissueVelocityMax then
    self._navNotActiveSinceMs = 0
    return
  end

  -- Start / continue debounce window for "not active/unknown".
  if self._navNotActiveSinceMs == 0 then
    self._navNotActiveSinceMs = nowMs
    return
  end

  if (nowMs - self._navNotActiveSinceMs) < self._navNotActiveDebounceMs then
    return
  end

  if self._lastNavReissueAtMs > 0 and (nowMs - self._lastNavReissueAtMs) < self._navReissueCooldownMs then
    return
  end

  self._lastNavReissueAtMs = nowMs
  self._navNotActiveSinceMs = 0

  local reason = (activeMq == nil) and 'reissue_active_unknown_debounced' or 'reissue_not_active_debounced'
  self:_issueNav(self._navTargetId, facts.chaseDistance, reason)
end

function ChaseBehavior:_checkStuckWhileMoving()
  local mq = self.mq
  local log = self.logger

  if not self._navActive then return false end

  local nowMs = self:_nowMs()

  if self._navIssuedAtMs > 0 and (nowMs - self._navIssuedAtMs) < self._navGraceMs then
    return false
  end

  local activeMq = self:_navActiveMq()
  local pausedMq = self:_navPausedMq()

  if activeMq == false then
    return false
  end

  if pausedMq == true then
    return false
  end

  local v = self:_navVelocityMq()
  if v ~= nil and v >= self._minVelocity then
    self._lastMovedAtMs = nowMs
    return false
  end

  local me = mq.TLO.Me
  if not (me and me.X and me.Y and me.Z) then return false end

  local x, y, z = me.X(), me.Y(), me.Z()

  if self._lastX == nil then
    self._lastX, self._lastY, self._lastZ = x, y, z
    self._lastMovedAtMs = nowMs
    log:Debug(string.format('[ChaseBehavior] Stuck detection: x=%.2f y=%.2f z=%.2f', x, y, z))
    return false
  end

  local moved = dist3(x, y, z, self._lastX, self._lastY, self._lastZ)
  if moved >= self._minMoveDistance then
    self._lastX, self._lastY, self._lastZ = x, y, z
    self._lastMovedAtMs = nowMs
    log:Debug(string.format('[ChaseBehavior] Movement detected: moved=%.2f', moved))
    return false
  end

  local stuckMs = nowMs - (self._lastMovedAtMs or nowMs)
  local stuckThresholdMs = math.floor((self._stuckSeconds or 3.0) * 1000)
  if stuckMs >= stuckThresholdMs then
    log:Debug(string.format(
      '[ChaseBehavior] Stuck detected: stuckTime=%.2f >= %.2f seconds',
      stuckMs / 1000.0, self._stuckSeconds
    ))
    return true
  end

  return false
end

function ChaseBehavior:_transitionTo(nextState, facts)
  local prev = self._fsmState
  if prev == nextState then return end

  self.logger:Debug(string.format('[ChaseBehavior] Transition: %s -> %s', tostring(prev), tostring(nextState)))
  self._fsmState = nextState

  if nextState == ChaseStatus.None then
    self:_stopNav()
    self:_resetStuckTracking()
    self:_writeState(ChaseStatus.None, facts.maName, facts.dist)

  elseif nextState == ChaseStatus.NotFound then
    self:_stopNav()
    self:_resetStuckTracking()
    self:_writeState(ChaseStatus.NotFound, facts.maName, facts.dist)

  elseif nextState == ChaseStatus.AtTarget then
    self:_stopNav()
    self:_resetStuckTracking()
    self:_writeState(ChaseStatus.AtTarget, facts.maName, facts.dist)

  elseif nextState == ChaseStatus.Moving then
    self:_resetStuckTracking()
    self:_startNav(facts.maId, facts.chaseDistance)
    self:_writeState(ChaseStatus.Moving, facts.maName, facts.dist)

  elseif nextState == ChaseStatus.Stuck then
    self:_stopNav()
    self:_resetStuckTracking()
    self:_writeState(ChaseStatus.Stuck, facts.maName, facts.dist)

  else
    self:_stopNav()
    self:_resetStuckTracking()
    self:_writeState(ChaseStatus.None, facts.maName, facts.dist)
  end
end

function ChaseBehavior:Enter()
  local log = self.logger

  log:Debug('[ChaseBehavior] Enter() called - initializing chase behavior')
  self._accum = 0

  local me = self.mq.TLO.Me
  if me and me.X and me.Y and me.Z then
    self._lastX, self._lastY, self._lastZ = me.X(), me.Y(), me.Z()
    self._lastMovedAtMs = self:_nowMs()
    log:Debug(string.format(
      '[ChaseBehavior] Initial position: x=%.2f y=%.2f z=%.2f',
      self._lastX, self._lastY, self._lastZ
    ))
  else
    self._lastX, self._lastY, self._lastZ = nil, nil, nil
    self._lastMovedAtMs = self:_nowMs()
    log:Warn('[ChaseBehavior] Could not read initial position')
  end

  self._fsmState = ChaseStatus.None
  self:_stopNav()
  self:_writeState(ChaseStatus.None, nil, 0)

  log:Info('Chase mode active')
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

  local facts = {
    chaseDistance = chaseDistance,
    maName = nil,
    maId = 0,
    dist = 0,
    meshLoaded = false,
  }

  facts.maName = state.group and state.group.roles and state.group.roles.mainAssist or nil
  if not facts.maName or facts.maName == '' then
    self:_writeTelemetry(nil, 0)
    self:_transitionTo(ChaseStatus.NotFound, facts)
    return
  end

  local maSpawn = mq.TLO.Spawn('pc ' .. facts.maName)
  facts.maId = (maSpawn and maSpawn.ID and maSpawn.ID()) or 0
  if facts.maId == 0 then
    self:_writeTelemetry(facts.maName, 0)
    self:_transitionTo(ChaseStatus.NotFound, facts)
    return
  end

  facts.dist = (maSpawn.Distance and maSpawn.Distance()) or 0
  facts.meshLoaded = self:_meshLoaded()

  self:_writeTelemetry(facts.maName, facts.dist)

  local nextState

  -- Hysteresis for AtTarget:
  -- If currently AtTarget, only leave it once we're beyond chaseDistance + hysteresis.
  if self._fsmState == ChaseStatus.AtTarget then
    local leaveDist = facts.chaseDistance + (self._atTargetHysteresis or 0)
    if facts.dist <= leaveDist then
      nextState = ChaseStatus.AtTarget
    else
      -- beyond hysteresis band: move again if possible
      if not facts.meshLoaded then
        log:Error('[ChaseBehavior] Navigation mesh not loaded, cannot chase')
        nextState = ChaseStatus.NotFound
      else
        nextState = ChaseStatus.Moving
      end
    end
  else
    -- Normal entry condition into AtTarget
    if facts.dist <= facts.chaseDistance then
      nextState = ChaseStatus.AtTarget
    else
      if not facts.meshLoaded then
        log:Error('[ChaseBehavior] Navigation mesh not loaded, cannot chase')
        nextState = ChaseStatus.NotFound
      else
        if self._fsmState == ChaseStatus.Moving and self:_checkStuckWhileMoving() then
          nextState = ChaseStatus.Stuck
        else
          nextState = ChaseStatus.Moving
        end
      end
    end
  end

  self:_transitionTo(nextState, facts)

  if self._fsmState == ChaseStatus.Moving then
    self:_logNavStateIfNeeded()
    self:_ensureNavRunning(facts)

    if self:_checkStuckWhileMoving() then
      self:_transitionTo(ChaseStatus.Stuck, facts)
    end
  end
end

function ChaseBehavior:Exit()
  local log = self.logger

  log:Debug('[ChaseBehavior] Exit() called - exiting chase behavior')
  self:_stopNav()
  self._fsmState = ChaseStatus.None
  self:_writeState(ChaseStatus.None, nil, 0)
end

return ChaseBehavior