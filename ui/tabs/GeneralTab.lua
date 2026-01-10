local Modes = require('asyst.constants.Modes')

local StubSection = require('asyst.ui.sections.StubSection')
local ChaseSection = require('asyst.ui.sections.ChaseSection')

local ModeItems = {
  { value = Modes.Manual, label = 'Manual' },
  { value = Modes.Chase,  label = 'Chase'  },
  { value = Modes.Camp,   label = 'Camp'   },
  { value = Modes.Hunter, label = 'Hunter' },
}

local GeneralTab = {}
GeneralTab.__index = GeneralTab

function GeneralTab.new(ImGui, state, logger)
  local self = setmetatable({}, GeneralTab)
  self.ImGui = ImGui
  self.state = state
  self.logger = logger

  self.sections = {
    [Modes.Chase] = ChaseSection.new(ImGui, state, logger),
    [Modes.Manual] = StubSection.new(ImGui, state, logger, 'Automation status: (stub)'),
    [Modes.Camp] = StubSection.new(ImGui, state, logger, 'Automation status: (stub)'),
  }

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

    local opts = self.state.options
    ImGui.Text('Mode')

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
    end

    local section = self.sections[opts.mode] or self.sections[Modes.Manual]
    if section and section.Draw then
      section:Draw()
    end

    ImGui.EndTabItem()
  end
end

return GeneralTab