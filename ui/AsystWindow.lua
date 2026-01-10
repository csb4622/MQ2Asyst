local GeneralTab = require('asyst.ui.tabs.GeneralTab')
local GroupTab   = require('asyst.ui.tabs.GroupTab')
local OptionsTab = require('asyst.ui.tabs.OptionsTab')
local ConsoleTab = require('asyst.ui.tabs.ConsoleTab')

local AsystWindow = {}
AsystWindow.__index = AsystWindow

function AsystWindow.new(ImGui, state, logger)
  local self = setmetatable({}, AsystWindow)
  self.ImGui = ImGui
  self.state = state
  self.logger = logger

  self.tabs = {
    GeneralTab.new(ImGui, state, logger),
    GroupTab.new(ImGui, state, logger),
    OptionsTab.new(ImGui, state, logger),
    ConsoleTab.new(ImGui, state, logger),
  }

  -- wire logger to console (optional but useful)
  self.logger:SetSink(function(line)
    local c = self.state.console
    table.insert(c.lines, line)
    if #c.lines > c.maxLines then
      table.remove(c.lines, 1)
    end
  end)

  return self
end

function AsystWindow:Draw(characterSnapshot)
  local ImGui = self.ImGui

  -- Track if we pushed a style color
  local pushedStyle = false

  -- Apply red background when paused
  if self.state.app.isPaused then
    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0.3, 0.0, 0.0, 1.0)
    pushedStyle = true
  end

  self.state.ui.isOpen, shouldDraw = ImGui.Begin('Asyst', self.state.ui.isOpen)
  if shouldDraw then
    -- Header
    local header = 'Asyst - ' .. (characterSnapshot.className or 'Unknown')
    ImGui.Text(header)
    ImGui.Separator()

    -- Pause/Resume button above tabs
    local buttonText = self.state.app.isPaused and "Resume" or "Pause"
    if ImGui.Button(buttonText) then
      self.state.app.isPaused = not self.state.app.isPaused
      if self.state.app.isPaused then
        self.logger:Info('Plugin paused')
      else
        self.logger:Info('Plugin resumed')
      end
    end
    ImGui.Separator()

    -- Tabs
    if ImGui.BeginTabBar('AsystTabs') then
      for _, tab in ipairs(self.tabs) do
        tab:Draw()
      end
      ImGui.EndTabBar()
    end
  end
  ImGui.End()

  -- Pop style color if we pushed it
  if pushedStyle then
    ImGui.PopStyleColor()
  end
end

return AsystWindow