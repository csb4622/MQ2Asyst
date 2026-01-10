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

  -- Stuck detection: if we issue nav and aren't moving, mark stuck.
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
  if not chase then return end

  chase.status = status or chase.status
  chase.mainAssistName = maName
  chase.mainAssistDistance = maDist or chase.mainAssistDistance

  chase.nav = chase.nav or { active = false, targetId = 0, issuedAt = 0 }
  chase.nav.active = self._navActive
  chase.nav.targetId = self._navTargetId
  chase.nav.issuedAt = self._navIssuedAt
end

function ChaseBehavior:_resetChase()
  if self._navActive then
    self.mq.cmd('/nav stop')
  end

  self._navActive = false
  self._navTargetId = 0
  self._navIssuedAt = 0

  self:_writeState(ChaseStatus.None)
end

function ChaseBehavior:Enter()
  self._accum = 0

  local me = self.mq.TLO.Me
  if me and me.X and me.Y and me.Z then
    self._lastX, self._lastY, self._lastZ = me.X(), me.Y(), me.Z()
    self._lastMovedAt = os.clock()
  else
    self._lastX, self._lastY, self._lastZ = nil, nil, nil
    self._lastMovedAt = os.clock()
  end

  self:_resetChase()
end

function ChaseBehavior:Tick(dt)
  self._accum = self._accum + dt
  if self._accum < self._interval then return end
  self._accum = 0

  local mq = self.mq
  local state = self.state
  local chase = state.chase

  if not chase then return end

  local chaseDistance = clampNumber(chase.chaseDistance, 5, 500) or 25
  chase.chaseDistance = chaseDistance

  -- MA name comes ONLY from state to avoid subtle MQ/group-role mismatches.
  local maName = state.group and state.group.roles and state.group.roles.mainAssist or nil
  chase.mainAssistName = maName

  if not maName or maName == '' then
    self:_resetChase()
    self:_writeState(ChaseStatus.NotFound, nil, 0)
    return
  end

  -- Lookup MA spawn by name. (This uses MQ for existence/distance only.)
  local maSpawn = mq.TLO.Spawn('pc ' .. maName)
  local maId = (maSpawn and maSpawn.ID and maSpawn.ID()) or 0
  if maId == 0 then
    self:_resetChase()
    self:_writeState(ChaseStatus.NotFound, maName, 0)
    return
  end

  local dist = (maSpawn.Distance and maSpawn.Distance()) or 0
  chase.mainAssistDistance = dist

  -- Close enough: stop our nav.
  if dist <= chaseDistance then
    self:_resetChase()
    self:_writeState(ChaseStatus.AtTarget, maName, dist)
    return
  end

  -- Can't nav without a mesh.
  if not (mq.TLO.Navigation and mq.TLO.Navigation.MeshLoaded and mq.TLO.Navigation.MeshLoaded()) then
    self:_resetChase()
    self:_writeState(ChaseStatus.NotFound, maName, dist)
    return
  end

  -- If we are not currently running *our* nav, start it.
  if not self._navActive then
    self._navActive = true
    self._navTargetId = maId
    self._navIssuedAt = os.clock()

    -- Tag is still useful to observers/APIs, but UI does not rely on it.
    mq.cmd(('/nav id %d distance=%d log=off tag=asyst_chase'):format(maId, chaseDistance))

    self:_writeState(ChaseStatus.Moving, maName, dist)
  else
    -- We are "moving" only if our chase behavior believes it's active.
    -- Do NOT mirror any external nav state into the UI.
    self:_writeState(ChaseStatus.Moving, maName, dist)
  end

  -- Stuck detection only while our nav is active.
  if self._navActive then
    local me = mq.TLO.Me
    if me and me.X and me.Y and me.Z then
      local x, y, z = me.X(), me.Y(), me.Z()

      if self._lastX == nil then
        self._lastX, self._lastY, self._lastZ = x, y, z
        self._lastMovedAt = os.clock()
      else
        local moved = dist3(x, y, z, self._lastX, self._lastY, self._lastZ)
        if moved >= self._minMoveDistance then
          self._lastX, self._lastY, self._lastZ = x, y, z
          self._lastMovedAt = os.clock()
        else
          if (os.clock() - (self._lastMovedAt or 0)) >= self._stuckSeconds then
            mq.cmd('/nav stop')
            self._navActive = false
            self:_writeState(ChaseStatus.Stuck, maName, dist)
          end
        end
      end
    end
  end
end

function ChaseBehavior:Exit()
  self:_resetChase()
end

return ChaseBehavior
