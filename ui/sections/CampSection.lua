local CampStatus = require('asyst.constants.CampStatus')

local CampSection = {}
CampSection.__index = CampSection

function CampSection.new(ImGui, state, logger)
  local self = setmetatable({}, CampSection)
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

function CampSection:Draw()
  local ImGui = self.ImGui
  local state = self.state
  local camp = state.camp or {}

  ImGui.Separator()
  ImGui.Text('Camp')

  -- Camp position display
  local campX = tonumber(camp.x) or 0
  local campY = tonumber(camp.y) or 0
  local campZ = tonumber(camp.z) or 0
  ImGui.Text(('Camp Position: X=%.1f Y=%.1f Z=%.1f'):format(campX, campY, campZ))

  -- Camp radius input
  local curCampRadius = tonumber(camp.campRadius) or 40
  local changed, val = InputIntValue(ImGui, 'Camp Radius##AsystCampRadius', curCampRadius)
  if changed then
    if val < 5 then val = 5 end
    if val > 500 then val = 500 end
    camp.campRadius = val
    state.camp = camp
  end

  -- Return to exact spot checkbox
  local returnToExact = camp.returnToExactSpot or false
  changed, camp.returnToExactSpot = ImGui.Checkbox('Return to Exact Spot##AsystReturnToExactSpot', returnToExact)
  if changed then
    state.camp = camp
  end

  -- Rest radius input (only show if not returning to exact spot)
  if not camp.returnToExactSpot then
    local curRestRadius = tonumber(camp.restRadius) or 10
    changed, val = InputIntValue(ImGui, 'Rest Radius##AsystRestRadius', curRestRadius)
    if changed then
      if val < 0 then val = 0 end
      if val > 500 then val = 500 end
      camp.restRadius = val
      state.camp = camp
    end
  end

  -- Camp status display
  local status = camp.status
  ImGui.Text(('Status: %s'):format(CampStatus.ToLabel(status)))
end

return CampSection
