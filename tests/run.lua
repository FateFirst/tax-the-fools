dofile("tests/wow_stub.lua")
WoW.reset()

-- Load addon files in TOC order, exactly as the client does.
local toc = io.open("TaxTheFools/TaxTheFools.toc")
local files = {}
for line in toc:lines() do
  local _, _, f = string.find(line, "^([%w_]+%.lua)%s*$")
  if f then table.insert(files, f) end
end
toc:close()
for _, f in ipairs(files) do dofile("TaxTheFools/" .. f) end
WoW.fire("VARIABLES_LOADED")

-- Lua 5.0 has no io.popen by default: the Makefile passes the test files as arguments.
for i = 1, table.getn(arg) do dofile(arg[i]) end

print(string.format("%d passed, %d failed", T.passed, T.failed))
for _, f in ipairs(T.failures) do print("FAIL " .. f) end
if T.failed > 0 then os.exit(1) end
