local Modes = require('asyst.constants.Modes')
local GuardSeverity = require('asyst.constants.GuardSeverity')
local GuardReason = require('asyst.constants.GuardReason')
local GuardReasonLabels = require('asyst.constants.GuardReasonLabels')

local SafetyService = require('asyst.services.SafetyService')

local ManualBehavior = require('asyst.engine.behaviors.ManualBehavior')
local ChaseBehavior  = require('asyst.engine.behaviors.ChaseBehavior')
local CampBehavior   = require('asyst.engine.behaviors.CampBehavior')
local HunterBehavior = require('asyst.engine.behaviors.HunterBehavior')

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
    [Modes.Hunter] = HunterBehavior.new(mq, state, logger),
  }

  self.safety = SafetyService.new(mq, logger)
  self._isPausedBySafety = false

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

  -- Check if manually paused
  if self.state.app.isPaused then
    return
  end

  local safety = self.safety:Check()
  if not safety.ok then
    if not self._isPausedBySafety then
      self:EmergencyStopAll()
    end
    self._isPausedBySafety = true

    if safety.reason and self.safety:ShouldLog(safety.reason) then
      self.logger:Warn('Safety: ' .. safety.reason)
    end

    if safety.severity == 'Stop' then
      self.state.options.mode = Modes.Manual
      self._pendingMode = nil
      self:_applyMode(Modes.Manual)
    end

    return
  end

  self._isPausedBySafety = false

  local desired = self.state.options.mode

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

  if desired ~= nil then
    if desired ~= self._activeMode and desired ~= self._pendingMode then
      self:RequestMode(desired)
    end
  end

  if self._pendingMode ~= nil then
    local elapsed = now - self._modeChangeRequestedAt
    if elapsed >= self._modeDebounceSeconds then
      local modeToApply = self._pendingMode
      self._pendingMode = nil
      self:_applyMode(modeToApply)
    end
  end

  if self._activeMode == nil then
    self:_applyMode(Modes.Manual)
  end

  local behavior = self.behaviors[self._activeMode]
  if not behavior then
    self:_applyMode(Modes.Manual)
    return
  end

  -- Behavior-specific guards (expects GuardSeverity + GuardReason + GuardReasonLabels + _shouldLogGuard)
  if behavior.GetGuards then
    local guards = behavior:GetGuards()
    if guards then
      for _, guard in ipairs(guards) do
        local result = guard()
        if result and result.ok == false then
          if not self._isPausedByGuards then
            self:EmergencyStopAll()
          end
          self._isPausedByGuards = true

          local reason = result.reason or GuardReason.None
          if self:_shouldLogGuard(reason) then
            local label = GuardReasonLabels and (GuardReasonLabels[reason] or tostring(reason)) or tostring(reason)
            self.logger:Warn('Guard: ' .. label)
          end

          if result.severity == GuardSeverity.Stop then
            self.state.options.mode = Modes.Manual
            self._pendingMode = nil
            self:_applyMode(Modes.Manual)
          end

          return
        end
      end
    end
  end

  self._isPausedByGuards = false

  behavior:Tick(dt)
end


return AutomationEngine