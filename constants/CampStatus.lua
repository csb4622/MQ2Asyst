local CampStatus = {
  Resting   = 0,
  Waiting   = 1,
  Preparing = 2,
  Fighting  = 3,
}

CampStatus.Labels = {
  [CampStatus.Resting]   = 'Resting',
  [CampStatus.Waiting]   = 'Waiting',
  [CampStatus.Preparing] = 'Preparing',
  [CampStatus.Fighting]  = 'Fighting',
}

function CampStatus.ToLabel(value)
  return CampStatus.Labels[value] or 'Resting'
end

return CampStatus
