local StubSection = {}
StubSection.__index = StubSection

function StubSection.new(ImGui, state, logger, text)
  local self = setmetatable({}, StubSection)
  self.ImGui = ImGui
  self.state = state
  self.logger = logger
  self.text = text or 'Automation status: (stub)'
  return self
end

function StubSection:Draw()
  local ImGui = self.ImGui
  ImGui.Separator()
  ImGui.Text(self.text)
end

return StubSection