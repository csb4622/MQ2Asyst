local GuardReason = require('asyst.constants.GuardReason')

local Labels = {
  [GuardReason.None] = 'None',
  [GuardReason.Stunned] = 'Stunned',
  [GuardReason.Mezzed] = 'Mezzed',
  [GuardReason.Charmed] = 'Charmed',
  [GuardReason.Feared] = 'Feared',
  [GuardReason.NoMainAssist] = 'No Main Assist',
  [GuardReason.CampNoPosition] = 'CantGetPosition',
}

return Labels