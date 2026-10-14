TaxTheFools = TaxTheFools or {}
local U = {}
TaxTheFools.Util = U

U.PREFIX = "|cff52c722TTF:|r "

function U.msg(text)
  DEFAULT_CHAT_FRAME:AddMessage(U.PREFIX .. tostring(text))
end

function U.debug(text)
  if TaxTheFoolsDB and TaxTheFoolsDB.settings and TaxTheFoolsDB.settings.debug then
    U.msg("|cff888888" .. tostring(text) .. "|r")
  end
end

function U.trim(s)
  local _, _, r = string.find(s or "", "^%s*(.-)%s*$")
  return r or ""
end

function U.words(s)
  local t = {}
  for w in string.gfind(s or "", "%S+") do table.insert(t, w) end
  return t
end

function U.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end
