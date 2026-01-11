local State = require('asyst.State')
local Logger = require('asyst.util.Logger')

local PluginService = require('asyst.services.PluginService')
local GroupService = require('asyst.services.GroupService')
local CharacterService = require('asyst.services.CharacterService')
local CommandService = require('asyst.services.CommandService')

local AutomationEngine = require('asyst.engine.AutomationEngine')
local AsystWindow = require('asyst.ui.AsystWindow')

local App = {}
App.__index = App


function App.new(mq, ImGui)
  local self = setmetatable({}, App)

  self.mq = mq
  self.ImGui = ImGui

  self.state = State.new()

  -- Get character name for per-character log file
  local charName = (mq.TLO.Me.Name and mq.TLO.Me.Name()) or 'Unknown'
  self.logger = Logger.new('[Asyst]', mq.luaDir .. '/asyst_' .. charName .. '.log')

  self._lastGameState = nil

  self.commandService = CommandService.new(mq, self.state, self.logger, self.engine)
  self.characterService = CharacterService.new(mq, self.logger)
  self.pluginService = PluginService.new(mq, self.logger)
  self.groupService = GroupService.new(mq, self.logger)
  
  self.engine = AutomationEngine.new(mq, self.state, self.logger)

  self.window = AsystWindow.new(ImGui, self.state, self.logger)

  return self
end

function App:Initialize()

  -- 1) unload mq2melee if loaded
  self.pluginService:UnloadIfLoaded('mq2melee')

  -- 2) snapshot character
  self.state.character = self.characterService:GetSnapshot()

  -- 3) snapshot group
  self.state.group = self.groupService:GetSnapshot()

  self.commandService:Register()

  self.logger:Info(string.format(
    'Loaded for %s (Level %s %s)',
    self.state.character.name,
    tostring(self.state.character.level),
    self.state.character.className
  ))

  self.state.ui.isOpen = true
  self.state.app.isRunning = true
end

function App:Run()
  
  while self.state.app.isRunning do
    self.engine:Tick()
    self.mq.delay(10)

    -- optional: stop if MQ is unloading / char not present etc.
    -- (stub: you can add a guard here)
  end
end

function App:Shutdown()
  self.logger:Info('Shutdown')
  self.logger:Close()
end

function App:DrawUI()
  if not self.state.ui.isOpen then
    self.state.app.isRunning = false
    return
  end

  local mq = self.mq


  if mq.TLO.MacroQuest.GameState() == 'CHARSELECT' then
    return
  end

  if mq.TLO.NearestSpawn('pc')() == nil then
    return
  end

  local eq = mq.TLO.EverQuest
  
  if eq and eq.ScreenMode and eq.ScreenMode() == 3 then
    return
  end

  self.window:Draw(self.state.character)
end




return App