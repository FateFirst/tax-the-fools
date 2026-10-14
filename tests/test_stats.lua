local S = TaxTheFools.Stats

T.test("percentile walks up from the cheapest", function()
  T.eq(S.weightedPercentile({ 30, 10, 40, 20 }, nil, 0), 10, "p0 is the minimum")
  T.eq(S.weightedPercentile({ 30, 10, 40, 20 }, nil, 0.25), 10)
  T.eq(S.weightedPercentile({ 30, 10, 40, 20 }, nil, 0.5), 20, "lower median")
  T.eq(S.weightedPercentile({}, nil, 0.5), nil)
end)

T.test("one cheap unit can't drag a quantity-weighted p25 down", function()
  -- a troll lists 1 at 100, a real seller lists 19 at 200
  T.eq(S.weightedPercentile({ 100, 200 }, { 1, 19 }, 0.25), 200)
end)

T.test("median", function()
  T.eq(S.median({ 5, 1, 3 }), 3)
end)

T.test("coefficient of variation", function()
  T.eq(S.cv({ 100, 100, 100 }), 0)
  T.eq(S.cv({ 100 }), 0, "one value")
  T.near(S.cv({ 50, 150, 50, 150, 50 }), 0.5443, 0.001)
  T.eq(S.cv({ 0, 0 }), 0, "zero mean")
end)
