local GuardSeverity = require('asyst.constants.GuardSeverity')
local GuardReason   = require('asyst.constants.GuardReason')
local CampStatus    = require('asyst.constants.CampStatus')

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

  -- Initialize status
  self.state.camp.status = CampStatus.Resting

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

  -- Update camp status based on enemies and combat criteria
  self:_updateCampStatus()

  -- Camp enforcement (radius/nav) comes next
  if log and log.Debug then
    log:Debug('[CampBehavior] Camp enforcement placeholder - will be implemented')
  end
end

-- Helper function to get distance between two points
function CampBehavior:_getDistance(x1, y1, z1, x2, y2, z2)
  local dx = x2 - x1
  local dy = y2 - y1
  local dz = z2 - z1
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Check if character is the main assist
function CampBehavior:_isMainAssist()
  local me = self.mq.TLO.Me
  if not me then return false end

  local myName = me.Name()
  if not myName or myName == '' then return false end

  local roles = self.state.group and self.state.group.roles
  if not roles then return false end

  local maName = roles.mainAssist
  return maName and maName == myName
end

-- Get enemies from xtarget list
function CampBehavior:_getXTargetEnemies()
  local mq = self.mq
  local enemies = {}

  local xtCount = mq.TLO.Me.XTarget() or 0
  if xtCount == 0 then return enemies end

  for i = 1, xtCount do
    local xt = mq.TLO.Me.XTarget(i)
    if xt and xt.ID and xt.ID() and xt.ID() > 0 then
      local targetType = xt.TargetType and xt.TargetType() or ''
      -- Only include actual enemies (Auto Hated or Targeted)
      if targetType == 'Auto Hated' or targetType == 'Target' then
        local spawn = mq.TLO.Spawn(xt.ID())
        if spawn and spawn.Type and spawn.Type() == 'NPC' then
          table.insert(enemies, {
            id = xt.ID(),
            spawn = spawn,
            distance = spawn.Distance and spawn.Distance() or 999999,
            x = spawn.X and spawn.X() or 0,
            y = spawn.Y and spawn.Y() or 0,
            z = spawn.Z and spawn.Z() or 0,
            pctHPs = spawn.PctHPs and spawn.PctHPs() or 100,
          })
        end
      end
    end
  end

  return enemies
end

-- Check if any enemy in xtarget is within camp radius
function CampBehavior:_getEnemiesInCampRadius(enemies)
  local campX = self.state.camp.x
  local campY = self.state.camp.y
  local campZ = self.state.camp.z
  local campRadius = self.state.camp.campRadius or 40

  local inRadius = {}

  for _, enemy in ipairs(enemies) do
    local dist = self:_getDistance(campX, campY, campZ, enemy.x, enemy.y, enemy.z)
    if dist <= campRadius then
      table.insert(inRadius, enemy)
    end
  end

  return inRadius
end

-- Check if combat criteria is met
function CampBehavior:_isCombatCriteriaMet(enemiesInRadius)
  if #enemiesInRadius == 0 then return false end

  -- If character is MA, criteria is just having enemy in camp radius
  if self:_isMainAssist() then
    return true
  end

  -- Otherwise, check if any enemy's HP is below assist at percentage
  local assistAtPercent = self.state.options.assistAtPercent or 98

  for _, enemy in ipairs(enemiesInRadius) do
    if enemy.pctHPs <= assistAtPercent then
      return true
    end
  end

  return false
end

-- Update camp status based on current conditions
function CampBehavior:_updateCampStatus()
  local log = self.logger

  -- Get all enemies on xtarget
  local enemies = self:_getXTargetEnemies()

  -- No enemies = Resting
  if #enemies == 0 then
    self.state.camp.status = CampStatus.Resting
    if log and log.Debug then
      log:Debug('[CampBehavior] Status: Resting (no enemies on xtarget)')
    end
    return
  end

  -- Check which enemies are in camp radius
  local enemiesInRadius = self:_getEnemiesInCampRadius(enemies)

  -- Enemies exist but none in camp radius = Waiting
  if #enemiesInRadius == 0 then
    self.state.camp.status = CampStatus.Waiting
    if log and log.Debug then
      log:Debug('[CampBehavior] Status: Waiting (enemies on xtarget but none in camp radius)')
    end
    return
  end

  -- Enemies in radius, check combat criteria
  local criteriaMet = self:_isCombatCriteriaMet(enemiesInRadius)

  if criteriaMet then
    self.state.camp.status = CampStatus.Fighting
    if log and log.Debug then
      log:Debug('[CampBehavior] Status: Fighting (enemies in radius and criteria met)')
    end
  else
    self.state.camp.status = CampStatus.Preparing
    if log and log.Debug then
      log:Debug('[CampBehavior] Status: Preparing (enemies in radius but criteria not met)')
    end
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