local GroupTab = {}
GroupTab.__index = GroupTab

function GroupTab.new(ImGui, state, logger)
  local self = setmetatable({}, GroupTab)
  self.ImGui = ImGui
  self.state = state
  self.logger = logger
  return self
end

function GroupTab:Draw()
  local ImGui = self.ImGui

  if ImGui.BeginTabItem('Group') then
    ImGui.Text('Group automation: (stub)')
    ImGui.Separator()

    local g = self.state.group
    ImGui.Text(('Members: %d'):format(#g.members))
    for _, m in ipairs(g.members) do
      ImGui.BulletText(('%s (%s %s)'):format(m.name, tostring(m.level), m.className))
    end

    ImGui.Separator()
    ImGui.Text('Roles:')
    ImGui.Text(('Main Tank: %s'):format(g.roles.mainTank or '(none)'))
    ImGui.Text(('Main Assist: %s'):format(g.roles.mainAssist or '(none)'))
    ImGui.Text(('Puller: %s'):format(g.roles.puller or '(none)'))

    ImGui.EndTabItem()
  end
end

return GroupTab