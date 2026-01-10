local Modes = require('asyst.constants.Modes')


local ModeItems = {
  { value = Modes.Manual, label = 'Manual' },
  { value = Modes.Chase,  label = 'Chase'  },
  { value = Modes.Camp,   label = 'Camp'   },
}


local GeneralTab = {}
GeneralTab.__index = GeneralTab

function GeneralTab.new(ImGui, state, logger)
  local self = setmetatable({}, GeneralTab)
  self.ImGui = ImGui
  self.state = state
  self.logger = logger
  return self
end


local function findModeIndex(modeValue)
  for i = 1, #ModeItems do
    if ModeItems[i].value == modeValue then
      return i
    end
  end
  return 1
end

local function ComboIndex(ImGui, id, currentIndex, labels)
  local ret1, ret2 = ImGui.Combo(id, currentIndex, labels, #labels)

  if type(ret1) == 'boolean' then
    return ret1, ret2
  end
  if type(ret1) == 'number' and type(ret2) == 'boolean' then
    return ret2, ret1
  end
  if type(ret1) == 'number' then
    return (ret1 ~= currentIndex), ret1
  end

  return false, currentIndex
end


function GeneralTab:Draw()
  local ImGui = self.ImGui

  if ImGui.BeginTabItem('General') then
    local ch = self.state.character
    ImGui.Text(('Name: %s'):format(ch.name))
    ImGui.Text(('Level: %s'):format(tostring(ch.level)))
    ImGui.Text(('Class: %s'):format(ch.className))

    ImGui.Separator()

    -- Mode selector
    local opts = self.state.options
    ImGui.Text('Mode')

    -- Build labels array for ImGui.Combo
    local labels = {}
    for i = 1, #ModeItems do
      labels[i] = ModeItems[i].label
    end

    local currentIndex = findModeIndex(opts.mode)

    local changed, newIndex = ComboIndex(ImGui, '##AsystMode', currentIndex, labels)
    if changed and ModeItems[newIndex] then
      local selected = ModeItems[newIndex]
      opts.mode = selected.value

      self.logger:Info('Mode set to: ' .. selected.label)

      -- Stub hooks for later automation engine integration
      if opts.mode == Modes.Manual then
        -- In Manual, do nothing; user controls the character.
        -- Later: stop any running nav/chase logic.
        -- self.mq.cmd('/nav stop') -- (would belong in a service/engine, not UI)
      elseif opts.mode == Modes.Chase then
        -- In Chase, follow Group Main Assist using MQ2Nav (stub).
        -- Later: resolve MA name from state.group.roles.mainAssist and issue /nav id <name> or /nav spawn <name>.
      elseif opts.mode == Modes.Camp then
        -- hold position / return to camp (stub)
        -- Later: record camp location and use nav to return if displaced.
      end
    end

    ImGui.Separator()
    ImGui.Text('Automation status: (stub)')

    ImGui.EndTabItem()
  end
end

return GeneralTab