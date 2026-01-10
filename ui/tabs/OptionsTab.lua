local OptionsTab = {}
OptionsTab.__index = OptionsTab

function OptionsTab.new(ImGui, state, logger)
  local self = setmetatable({}, OptionsTab)
  self.ImGui = ImGui
  self.state = state
  self.logger = logger
  return self
end

function OptionsTab:Draw()
  local ImGui = self.ImGui
  if ImGui.BeginTabItem('Options') then
    -- Stub options (you can replace with real settings)
    local opts = self.state.options

    local changed
    changed, opts.followEnabled = ImGui.Checkbox('Enable Follow (stub)', opts.followEnabled)
    if changed then
      self.logger:Info('Follow option changed: ' .. tostring(opts.followEnabled))
    end

    changed, opts.assistEnabled = ImGui.Checkbox('Enable Assist (stub)', opts.assistEnabled)
    if changed then
      self.logger:Info('Assist option changed: ' .. tostring(opts.assistEnabled))
    end

    ImGui.EndTabItem()
  end
end

return OptionsTab