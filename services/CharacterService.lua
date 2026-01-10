local CharacterService = {}
CharacterService.__index = CharacterService

function CharacterService.new(mq, logger)
  local self = setmetatable({}, CharacterService)
  self.mq = mq
  self.logger = logger
  return self
end

-- Requirement: get basic info on load and store it
function CharacterService:GetSnapshot()
  local me = self.mq.TLO.Me
  local log = self.logger

  if log and log.Debug then
    log:Debug('[CharacterService] GetSnapshot() called')
  end

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

  if log and log.Debug then
    log:Debug(string.format(
      '[CharacterService] Snapshot: name=%s level=%s class=%s shortName=%s',
      tostring(name), tostring(level), tostring(className), tostring(classShortName)
    ))
  end

  return {
    name = name,
    level = level,
    className = className,
    classShortName = classShortName,
  }
end

return CharacterService