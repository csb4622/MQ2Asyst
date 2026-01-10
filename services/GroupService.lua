local GroupService = {}
GroupService.__index = GroupService

function GroupService.new(mq)
  local self = setmetatable({}, GroupService)
  self.mq = mq
  return self
end

local function safeCall(tloFunc)
  if not tloFunc then return nil end
  local ok, val = pcall(tloFunc)
  if not ok then return nil end
  return val
end

local function tloValue(obj, memberName)
  -- reads obj.<memberName>() if it exists, else nil
  if not obj then return nil end
  local f = obj[memberName]
  if type(f) ~= 'function' then return nil end
  return safeCall(f)
end

function GroupService:GetSnapshot()
  local mq = self.mq
  local group = mq.TLO.Group
  local me = mq.TLO.Me

  local snapshot = {
    members = {},
    roles = {
      mainTank = nil,
      mainAssist = nil,
      puller = nil,
      markNPC = nil,
    }
  }

  -- Members
  -- Prefer Group.Members() if present, otherwise fall back to Me.GroupSize()
  local memberCount = tloValue(group, 'Members')
  if type(memberCount) ~= 'number' then
    memberCount = tloValue(me, 'GroupSize') or 0
  end

  for i = 1, memberCount do
    local m = group.Member(i)
    if m then
      local name = tloValue(m, 'Name') or 'Unknown'
      local level = tloValue(m, 'Level') or 0

      local className = 'Unknown'
      local cls = m.Class
      if cls and cls.Name then
        className = safeCall(cls.Name) or 'Unknown'
      end

      table.insert(snapshot.members, {
        name = name,
        level = level,
        className = className,
      })

      -- Per-member role flags (only if these exist in your MQ build)
      -- These names vary by build/plugins; this is defensive.
      if not snapshot.roles.mainTank and tloValue(m, 'IsMainTank') then
        snapshot.roles.mainTank = name
      end
      if not snapshot.roles.mainAssist and tloValue(m, 'IsMainAssist') then
        snapshot.roles.mainAssist = name
      end
      if not snapshot.roles.puller and tloValue(m, 'IsPuller') then
        snapshot.roles.puller = name
      end
      if not snapshot.roles.markNPC and tloValue(m, 'IsMarkNPC') then
        snapshot.roles.markNPC = name
      end
    end
  end

  -- Group-level role TLOs (some builds expose these as Group.MainTank(), etc.)
  -- If present, they override per-member discovery.
  local mt = tloValue(group, 'MainTank')
  if mt and mt ~= '' then snapshot.roles.mainTank = mt end

  local ma = tloValue(group, 'MainAssist')
  if ma and ma ~= '' then snapshot.roles.mainAssist = ma end

  local pl = tloValue(group, 'Puller')
  if pl and pl ~= '' then snapshot.roles.puller = pl end

  local mk = tloValue(group, 'MarkNPC')
  if mk and mk ~= '' then snapshot.roles.markNPC = mk end

  -- if not grouped, self-assign all roles
  -- Depending on MQ, GroupSize may be 0 when solo; sometimes Members() returns 0.
  if memberCount == 0 or memberCount == 1 then
    local myName = (me.Name and me.Name()) or 'Unknown'
    snapshot.roles.mainTank = myName
    snapshot.roles.mainAssist = myName
    snapshot.roles.puller = myName
    snapshot.roles.markNPC = myName

    -- Optional: also make sure members list contains self for consistency
    if #snapshot.members == 0 then
      local level = (me.Level and me.Level()) or 0
      local className = (me.Class and me.Class.Name and me.Class.Name()) or 'Unknown'
      table.insert(snapshot.members, { name = myName, level = level, className = className })
    end
  end

  return snapshot
end

return GroupService