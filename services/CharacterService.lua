local CharacterService = {}
CharacterService.__index = CharacterService

function CharacterService.new(mq)
  local self = setmetatable({}, CharacterService)
  self.mq = mq
  return self
end

-- Requirement: get basic info on load and store it
function CharacterService:GetSnapshot()
  local me = self.mq.TLO.Me

  local name = (me.Name and me.Name()) or 'Unknown'
  local level = (me.Level and me.Level()) or 0

  local className = 'Unknown'
  local classShortName = 'UNK'
  if me.Class and me.Class.Name then
    className = me.Class.Name() or 'Unknown'
  end
  if me.Class and me.Class.ShortName then
    classShortName = me.Class.ShortName() or 'UNK'
  end

  return {
    name = name,
    level = level,
    className = className,
    classShortName = classShortName,
  }
end

return CharacterService