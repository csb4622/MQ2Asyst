-- services/GroupService.lua

local GroupService = {}
GroupService.__index = GroupService

function GroupService.new(mq, logger)
  local self = setmetatable({}, GroupService)
  self.mq = mq
  self.logger = logger
  return self
end

local function typeStr(v)
  if v == nil then return 'nil' end
  return type(v)
end

local function safeCall(func)
  if type(func) ~= 'function' then return nil end
  local ok, val = pcall(func)
  if not ok then return nil end
  return val
end

local function memberValue(obj, memberName)
  -- Reads obj.<memberName> whether it's a function (call it) or a property (return it).
  if not obj then return nil end
  local v = obj[memberName]
  if v == nil then return nil end
  if type(v) == 'function' then
    return safeCall(v)
  end
  return v
end

local function toNumber(v, default)
  if v == nil then return default end
  if type(v) == 'number' then return v end
  local n = tonumber(tostring(v))
  if n == nil then return default end
  return n
end

local function normalizeName(v)
  if v == nil then return nil end
  local s = tostring(v)
  if not s or s == '' or s == 'NULL' then return nil end
  return s
end

local function getGroupMember(mq, idx)
  -- Based on your logs: this is the working accessor in your build.
  if not (mq and mq.TLO and mq.TLO.Group and mq.TLO.Group.Member) then return nil end
  local ok, val = pcall(function() return mq.TLO.Group.Member(idx) end)
  if not ok then return nil end
  if val == nil or tostring(val) == 'NULL' then return nil end
  return val
end

local function spawnToName(spawnObj, log, label)
  -- Mirrors rgmercs pattern: TLO is a Spawn-like object, call it, validate ID, use CleanName.
  if not spawnObj then
    if log and log.Debug then log:Debug(string.format('[GroupService] %s: spawnObj=nil', label)) end
    return nil
  end

  local okAlive, aliveOrVal = pcall(function()
    -- many MQ TLO objects are callable for validity
    return spawnObj()
  end)

  if not okAlive or not aliveOrVal then
    if log and log.Debug then
      log:Debug(string.format('[GroupService] %s: spawnObj() invalid (ok=%s val=%s type=%s)',
        label, tostring(okAlive), tostring(aliveOrVal), typeStr(aliveOrVal)))
    end
    return nil
  end

  local id = 0
  if spawnObj.ID then
    local ok, v = pcall(function() return spawnObj.ID() end)
    if ok then id = toNumber(v, 0) end
  end

  if id <= 0 then
    if log and log.Debug then
      log:Debug(string.format('[GroupService] %s: ID=%s (not set)', label, tostring(id)))
    end
    return nil
  end

  if spawnObj.Dead then
    local ok, dead = pcall(function() return spawnObj.Dead() end)
    if ok and dead then
      if log and log.Debug then log:Debug(string.format('[GroupService] %s: Dead()=true', label)) end
      return nil
    end
  end

  local name = nil
  if spawnObj.CleanName then
    local ok, v = pcall(function() return spawnObj.CleanName() end)
    if ok then name = normalizeName(v) end
  end
  if not name and spawnObj.Name then
    local ok, v = pcall(function() return spawnObj.Name() end)
    if ok then name = normalizeName(v) end
  end

  if log and log.Debug then
    log:Debug(string.format('[GroupService] %s: resolved name=%s (ID=%d)', label, tostring(name), id))
  end

  return name
end

function GroupService:GetSnapshot()
  local mq = self.mq
  local log = self.logger

  local me = mq.TLO.Me

  local snapshot = {
    members = {},
    roles = {
      mainTank = nil,
      mainAssist = nil,
      puller = nil,
    }
  }

  -- Member count: your build returns Me.GroupSize as userdata like "6"
  local rawGroupSize = memberValue(me, 'GroupSize')
  local memberCount = toNumber(rawGroupSize, 0)

  if log and log.Debug then
    log:Debug(string.format(
      '[GroupService] Count probes: Me.GroupSize=%s(%s) => memberCount=%d',
      tostring(rawGroupSize), typeStr(rawGroupSize),
      memberCount
    ))
  end

  -- Enumerate members via mq.TLO.Group.Member(i)
  for i = 1, memberCount do
    local m = getGroupMember(mq, i)
    if not m then
      if log and log.Debug then
        log:Debug(string.format('[GroupService] Member(%d): nil/NULL -> stopping enumeration', i))
      end
      break
    end

    local rawName = memberValue(m, 'Name')
    local name = normalizeName(rawName)

    local rawLevel = memberValue(m, 'Level')
    local level = toNumber(rawLevel, 0)

    local className = 'Unknown'
    local cls = m.Class
    if cls then
      className = normalizeName(memberValue(cls, 'Name')) or 'Unknown'
    end

    if log and log.Debug then
      log:Debug(string.format(
        '[GroupService] Member(%d): m=%s Name=%s(%s) normalizedName=%s Level=%s(%s) class=%s',
        i,
        tostring(m),
        tostring(rawName), typeStr(rawName),
        tostring(name),
        tostring(rawLevel), typeStr(rawLevel),
        tostring(className)
      ))
    end

    if name then
      table.insert(snapshot.members, {
        name = name,
        level = level,
        className = className,
      })
    end
  end

  -- Roles: use rgmercs-style Spawn TLOs off mq.TLO.Group (NOT mq.TLO.Group())
  -- These are Spawn-like objects; use CleanName() when possible.
  snapshot.roles.mainTank = spawnToName(mq.TLO.Group and mq.TLO.Group.MainTank or nil, log, 'Group.MainTank')
  snapshot.roles.mainAssist = spawnToName(mq.TLO.Group and mq.TLO.Group.MainAssist or nil, log, 'Group.MainAssist')
  snapshot.roles.puller = spawnToName(mq.TLO.Group and mq.TLO.Group.Puller or nil, log, 'Group.Puller')

  if log and log.Debug then
    log:Debug(string.format(
      '[GroupService] Roles resolved: MT=%s MA=%s Puller=%s',
      tostring(snapshot.roles.mainTank),
      tostring(snapshot.roles.mainAssist),
      tostring(snapshot.roles.puller)
    ))
    log:Debug('[GroupService] Snapshot members=' .. tostring(#snapshot.members))
  end

  -- If solo/unknown, include self for consistency and self-assign roles
  if #snapshot.members == 0 then
    local myName = normalizeName(memberValue(me, 'Name')) or 'Unknown'
    local myLevel = toNumber(memberValue(me, 'Level'), 0)
    local myClass = 'Unknown'
    if me.Class then myClass = normalizeName(memberValue(me.Class, 'Name')) or 'Unknown' end
    table.insert(snapshot.members, { name = myName, level = myLevel, className = myClass })

    snapshot.roles.mainTank = snapshot.roles.mainTank or myName
    snapshot.roles.mainAssist = snapshot.roles.mainAssist or myName
    snapshot.roles.puller = snapshot.roles.puller or myName
  end

  return snapshot
end

return GroupService