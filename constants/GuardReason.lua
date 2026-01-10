local GuardReason = {
  None          = 0,

  -- Chase-specific (for now)
  Stunned         = 10,
  Mezzed          = 11,
  Charmed         = 12,
  Feared          = 13,
  NoMainAssist    = 20,
  CampNoPosition  = 32,
}

return GuardReason
