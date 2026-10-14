TaxTheFools = TaxTheFools or {}
local S = {}
TaxTheFools.Stats = S

-- The value at fraction p (0..1) of the total weight, walking up from the
-- cheapest. Weighting by quantity is what stops one cheap single unit from
-- setting the price of a market full of stacks. weights may be nil (all 1).
function S.weightedPercentile(values, weights, p)
  local n = table.getn(values)
  if n == 0 then return nil end
  local idx = {}
  for i = 1, n do idx[i] = i end
  table.sort(idx, function(a, b) return values[a] < values[b] end)
  local total = 0
  for i = 1, n do total = total + (weights and weights[i] or 1) end
  local target = p * total
  local cum = 0
  for _, i in ipairs(idx) do
    cum = cum + (weights and weights[i] or 1)
    if cum >= target then return values[i] end
  end
  return values[idx[n]]
end

function S.median(values) return S.weightedPercentile(values, nil, 0.5) end

-- Spread relative to the mean; 0 when there is nothing to compare.
function S.cv(values)
  local n = table.getn(values)
  if n < 2 then return 0 end
  local sum = 0
  for _, v in ipairs(values) do sum = sum + v end
  local mean = sum / n
  if mean == 0 then return 0 end
  local sq = 0
  for _, v in ipairs(values) do sq = sq + (v - mean) * (v - mean) end
  return math.sqrt(sq / n) / mean
end
