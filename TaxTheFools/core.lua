local A = TaxTheFools
local U, D = A.Util, A.Data
local Core = { ready = false, disabled = {} }
A.Core = Core

function Core.ResetState() Core.disabled = {} end

-- Runs fn. With debug off, an error switches that part off for the session
-- instead of throwing every frame; with debug on it throws, for a stack trace.
function Core.Safe(name, fn, a1, a2, a3)
  if Core.disabled[name] then return end
  local s = TaxTheFoolsDB and TaxTheFoolsDB.settings
  if s and s.debug then return fn(a1, a2, a3) end
  local ok, err = pcall(fn, a1, a2, a3)
  if not ok then
    Core.disabled[name] = true
    U.msg(name .. " stopped after an error: " .. tostring(err) .. " (/reload to retry)")
  end
end

function Core.Init()
  Core.ready = true
  U.msg("v" .. D.VERSION .. " loaded. /ttf for commands.")
end

function Core.Command(msg)
  U.msg("commands:")
  U.msg("  /ttf help - this list")
end

SLASH_TAXTHEFOOLS1 = "/ttf"
SLASH_TAXTHEFOOLS2 = "/taxthefools"
SlashCmdList["TAXTHEFOOLS"] = function(msg) Core.Safe("command", Core.Command, msg) end

local frame = CreateFrame("Frame", "TaxTheFoolsCore")
frame:RegisterEvent("VARIABLES_LOADED")
frame:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then Core.Init() end
end)
