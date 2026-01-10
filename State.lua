local Modes = require('asyst.constants.Modes')
local ChaseStatus = require('asyst.constants.ChaseStatus')

local State = {}
State.__index = State

function State.new()
  local self = setmetatable({}, State)

  self.app = {
    isRunning = false,
    isPaused = false,
  }

  self.ui = {
    isOpen = false,
  }

  self.character = {
    name = 'Unknown',
    level = 0,
    className = 'Unknown',
    classShortName = 'UNK',
  }

  self.options = {
    -- stub options
    followEnabled = false,
    assistEnabled = false,

    mode = Modes.Manual,
  }

  self.group = {
    members = {}, -- array of {name, level, className}
    roles = {
      mainTank = nil,
      mainAssist = nil,
      puller = nil,
      markNPC = nil,
    }
  }

  self.camp = {
    x = 0, y = 0, z = 0,
    zoneId = 0,
  }

  -- Chase configuration + runtime status (written by ChaseBehavior, read by UI)
  self.chase = {
    chaseDistance = 25,

    mainAssistName = nil,
    mainAssistDistance = 0,

    status = ChaseStatus.None,

    -- "Only our nav" tracking (UI must not read Navigation.Active directly)
    nav = {
      active = false,
      targetId = 0,
      issuedAt = 0,
    }
  }

  self.console = {
    lines = {},
    maxLines = 200,
  }

  return self
end

return State
