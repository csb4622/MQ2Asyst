local ConsoleTab = {}
ConsoleTab.__index = ConsoleTab

function ConsoleTab.new(ImGui, state, logger)
  local self = setmetatable({}, ConsoleTab)
  self.ImGui = ImGui
  self.state = state
  self.logger = logger
  return self
end

function ConsoleTab:Draw()
  local ImGui = self.ImGui
  if ImGui.BeginTabItem('Console') then
    local c = self.state.console

    if ImGui.Button('Clear') then
      c.lines = {}
    end
    ImGui.Separator()

    -- Basic scrollable log area
    ImGui.BeginChild('AsystConsoleChild', 0, 0, true)
    for i = 1, #c.lines do
      ImGui.TextUnformatted(c.lines[i])
    end
    ImGui.EndChild()

    ImGui.EndTabItem()
  end
end

return ConsoleTab