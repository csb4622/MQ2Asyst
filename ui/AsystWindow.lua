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

  self.state.ui.isOpen, shouldDraw = ImGui.Begin('Asyst', self.state.ui.isOpen)
  if shouldDraw then
    -- Header
    local header = 'Asyst - ' .. (characterSnapshot.className or 'Unknown')
    ImGui.Text(header)
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
end

return AsystWindow