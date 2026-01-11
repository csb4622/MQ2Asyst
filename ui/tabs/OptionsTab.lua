local OptionsTab = {}
OptionsTab.__index = OptionsTab

function OptionsTab.new(ImGui, state, logger)
  local self = setmetatable({}, OptionsTab)
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

function OptionsTab:Draw()
  local ImGui = self.ImGui
  if ImGui.BeginTabItem('Options') then
    local opts = self.state.options

    ImGui.Text('Character Options')
    ImGui.Separator()

    -- Assist at percentage
    local curAssistAt = tonumber(opts.assistAtPercent) or 98
    local changed, val = InputIntValue(ImGui, 'Assist At %##AsystAssistAtPercent', curAssistAt)
    if changed then
      if val < 1 then val = 1 end
      if val > 100 then val = 100 end
      opts.assistAtPercent = val
      self.state.options = opts
      self.logger:Info('Assist at % changed: ' .. tostring(val))
    end

    ImGui.Separator()
    ImGui.Text('Stub Options')

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