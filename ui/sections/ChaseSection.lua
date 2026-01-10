local ChaseStatus = require('asyst.constants.ChaseStatus')

local ChaseSection = {}
ChaseSection.__index = ChaseSection

function ChaseSection.new(ImGui, state, logger)
  local self = setmetatable({}, ChaseSection)
  self.ImGui = ImGui
  self.state = state
  self.logger = logger
  return self
end

local function InputIntValue(ImGui, id, currentValue)
  -- MQ ImGui bindings vary in return signature; normalize.
  local r1, r2 = ImGui.InputInt(id, currentValue)

  if type(r1) == 'boolean' then
    return r1, r2
  end
  if type(r1) == 'number' and type(r2) == 'boolean' then
    return r2, r1
  end
  if type(r1) == 'number' then
    return (r1 ~= currentValue), r1
  end

  return false, currentValue
end

function ChaseSection:Draw()
  local ImGui = self.ImGui
  local state = self.state
  local chase = state.chase or {}

  ImGui.Separator()
  ImGui.Text('Chase')

  local maName = chase.mainAssistName or (state.group and state.group.roles and state.group.roles.mainAssist) or 'None'
  if maName == '' then maName = 'None' end
  ImGui.Text(('MA: %s'):format(maName))

  local dist = tonumber(chase.mainAssistDistance) or 0
  ImGui.Text(('Distance to MA: %.1f'):format(dist))

  local cur = tonumber(chase.chaseDistance) or 25
  local changed, val = InputIntValue(ImGui, 'Chase distance##AsystChaseDistance', cur)
  if changed then
    if val < 5 then val = 5 end
    chase.chaseDistance = val
    state.chase = chase
  end

  local status = chase.status
  ImGui.Text(('Status: %s'):format(ChaseStatus.ToLabel(status)))

  -- Only shows chase-created nav tracking.
  local nav = chase.nav or {}
  local navActive = nav.active and 'true' or 'false'
  local targetId = tonumber(nav.targetId) or 0
  ImGui.Text(('ChaseNav active: %s  targetId: %d'):format(navActive, targetId))
end

return ChaseSection