T.test("core is ready once saved variables load", function()
  T.ok(TaxTheFools.Core.ready, "VARIABLES_LOADED initialises the core")
end)

T.test("/ttf with no arguments prints help", function()
  SlashCmdList["TAXTHEFOOLS"]("")
  T.ok(T.calledWith("/ttf help"), "help lists itself")
end)

T.test("chat messages carry the TTF prefix", function()
  TaxTheFools.Util.msg("hello")
  T.ok(T.calledWith("TTF:|r hello"), "prefixed")
end)

T.test("Safe switches a part off after an error instead of erroring every frame", function()
  local Core = TaxTheFools.Core
  local calls = 0
  local boom = function() calls = calls + 1 error("bad") end
  Core.Safe("thing", boom)
  Core.Safe("thing", boom)
  T.eq(calls, 1, "second call skipped")
  T.ok(T.calledWith("thing stopped after an error"), "player told once")
end)
