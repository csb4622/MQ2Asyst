local ChaseStatus = {
    None         = 0,
    Moving       = 1,
    AtTarget     = 2,
    Stuck        = 3,
    NotFound     = 4,
    Paused       = 5,
}

ChaseStatus.Labels = {
  [ChaseStatus.None]   = 'None',
  [ChaseStatus.Moving]   = 'Moving',
  [ChaseStatus.AtTarget]  = 'At Target',
  [ChaseStatus.Stuck]    = 'Stuck',
  [ChaseStatus.NotFound] = 'Not Found',
  [ChaseStatus.Paused] = 'Paused',
}

function ChaseStatus.ToLabel(value)
  return ChaseStatus.Labels[value] or 'None'
end

return ChaseStatus
