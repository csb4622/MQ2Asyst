local Modes = require('asyst.constants.Modes')

local ManualBehavior = require('asyst.engine.behaviors.ManualBehavior')
local ChaseBehavior  = require('asyst.engine.behaviors.ChaseBehavior')
local CampBehavior   = require('asyst.engine.behaviors.CampBehavior')

local AutomationEngine = {}
AutomationEngine.__index = AutomationEngine

function AutomationEngine.new(mq, state, logger)
  local self = setmetatable({}, AutomationEngine)

  self.mq = mq
  self.state = state
  self.logger = logger

  self.behaviors = {
    [Modes.Manual] = ManualBehavior.new(mq, state, logger),
    [Modes.Chase]  = ChaseBehavior.new(mq, state, logger),
    [Modes.Camp]   = CampBehavior.new(mq, state, logger),
  }

  self._activeMode = nil

  -- Debounce / coalesce
  self._pendingMode = nil
  self._modeChangeRequestedAt = 0
  self._modeDebounceSeconds = 0.15

  -- Dwell (minimum time a mode must remain active)
  self._modeDwellSeconds = 0.15
  self._modeAppliedAt = 0

  -- Invalid-mode tracking (warn once)
  self._lastInvalidMode = nil

  -- Tick timing
  self._lastTickClock = os.clock()

  return self
end

-- Safe stop hook for future nav / movement
function AutomationEngine:EmergencyStopAll()
  -- When wired:
  -- self.mq.cmd('/nav stop')
end

function AutomationEngine:RequestMode(mode)
  if mode == nil then return end

  -- Clamp unknown modes
  if self.behaviors[mode] == nil then
    mode = Modes.Manual
  end

  -- No-op if already active and nothing pending
  if self._pendingMode == nil and self._activeMode == mode then
    return
  end

  -- Enforce dwell
  if self._activeMode ~= nil then
    local now = os.clock()
    local inModeFor = now - (self._modeAppliedAt or 0)
    if inModeFor < self._modeDwellSeconds then
      return
    end
  end

  self._pendingMode = mode
  self._modeChangeRequestedAt = os.clock()

  self:EmergencyStopAll()
end

function AutomationEngine:_applyMode(newMode)
  if newMode == nil then return end
  if self._activeMode == newMode then return end

  local oldB = self.behaviors[self._activeMode]
  if oldB and oldB.Exit then
    oldB:Exit()
  end

  local newB = self.behaviors[newMode]
  if not newB then
    newMode = Modes.Manual
    newB = self.behaviors[newMode]
  end

  if newB and newB.Enter then
    newB:Enter()
  end

  self._activeMode = newMode
  self._modeAppliedAt = os.clock()
end

function AutomationEngine:Tick()
  local now = os.clock()
  local dt = now - self._lastTickClock
  self._lastTickClock = now

  -- Desired mode from UI / commands
  local desired = self.state.options.mode

  -- Clamp invalid desired so we don't spam requests forever
  if desired ~= nil and self.behaviors[desired] == nil then
    if self._lastInvalidMode ~= desired then
      self.logger:Warn('Invalid mode ' .. tostring(desired) .. '; reverting to Manual')
      self._lastInvalidMode = desired
    end
    self.state.options.mode = Modes.Manual
    desired = Modes.Manual
  else
    self._lastInvalidMode = nil
  end

  -- Request mode changes (coalesced)
  if desired ~= nil then
    if desired ~= self._activeMode and desired ~= self._pendingMode then
      self:RequestMode(desired)
    end
  end

  -- Apply pending mode after debounce
  if self._pendingMode ~= nil then
    local elapsed = now - self._modeChangeRequestedAt
    if elapsed >= self._modeDebounceSeconds then
      local modeToApply = self._pendingMode
      self._pendingMode = nil
      self:_applyMode(modeToApply)
    end
  end

  -- Ensure an active mode exists (startup)
  if self._activeMode == nil then
    self:_applyMode(Modes.Manual)
  end

  -- Tick active behavior
  local behavior = self.behaviors[self._activeMode]
  if not behavior then
    self:_applyMode(Modes.Manual)
    return
  end

  behavior:Tick(dt)
end

return AutomationEngine