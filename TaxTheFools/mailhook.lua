TaxTheFools = TaxTheFools or {}
local DB, U = TaxTheFools.DB, TaxTheFools.Util
local MailHook = { open = false, keepOpen = false, pending = false, hooked = false, switching = false,
                   noticed = false, window = nil }
TaxTheFools.MailHook = MailHook

function MailHook.ResetState()
  MailHook.open, MailHook.keepOpen, MailHook.pending = false, false, false
  MailHook.switching, MailHook.hooked, MailHook.noticed = false, false, false
end

-- Replacing is on and TurtleMail isn't loaded: the one test for "our mailbox is in charge".
function MailHook.Enabled()
  if not DB.S().replaceBlizzardMail then return false end
  if IsAddOnLoaded and IsAddOnLoaded("TurtleMail") then return false end
  return true
end

function MailHook.Active()
  return MailHook.Enabled() and MailHook.window ~= nil and MailHook.window:IsShown() and true or false
end

-- MailFrame's OnHide calls CloseMail(): wrapped to do nothing while our window holds the mailbox open.
function MailHook.Hook()
  if MailHook.hooked or not MailFrame then return end
  MailHook.hooked = true
  local orig = MailFrame:GetScript("OnHide")
  MailFrame:SetScript("OnHide", function()
    if MailHook.keepOpen then return end
    if orig then orig() end
  end)
  local b = CreateFrame("Button", "TaxTheFoolsMailBackButton", MailFrame, "UIPanelButtonTemplate")
  b:SetWidth(110)
  b:SetHeight(20)
  b:SetText("Tax the Fools")
  b:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -40, -14)
  b:SetScript("OnClick", function() MailHook.ShowOurs() end)
end

function MailHook.OnShow()
  MailHook.open = true
  if IsAddOnLoaded and IsAddOnLoaded("TurtleMail") then
    if not MailHook.noticed then
      MailHook.noticed = true
      U.msg("TurtleMail is loaded, so TTF's mailbox is off. Disable TurtleMail to use it.")
    end
    return
  end
  if DB.S().replaceBlizzardMail then
    MailHook.pending = true
  else
    MailHook.Hook()
  end
end

-- Blizzard's handler for the same event shows MailFrame; hiding it inside that would close the
-- mailbox, so the swap happens on the next frame.
function MailHook.Tick()
  if not MailHook.pending then return end
  MailHook.pending = false
  if not MailFrame then return end
  MailHook.Hook()
  MailHook.ShowOurs()
end

function MailHook.ShowOurs()
  MailHook.Hook()
  MailHook.keepOpen = true
  if MailFrame and MailFrame:IsShown() then MailFrame:Hide() end
  if MailHook.window then MailHook.window:Show() end
  if not (IsBagOpen and IsBagOpen(0)) then OpenBackpack() end
end

function MailHook.ShowBlizzard()
  -- the engine's chain belongs to our window; Blizzard's would race it
  if TaxTheFools.Mailbox then TaxTheFools.Mailbox.Stop() end
  MailHook.switching = true
  if MailHook.window then MailHook.window:Hide() end
  MailHook.switching = false
  MailHook.keepOpen = false
  if MailFrame then MailFrame:Show() end
end

-- Our window's OnHide: closing it ends the visit, unless we are only switching windows.
function MailHook.OnWindowHidden()
  if MailHook.switching then return end
  MailHook.keepOpen = false
  if MailHook.open then
    MailHook.open = false
    CloseMail()
  end
end

-- MAIL_CLOSED (the engine's own Mailbox.OnClosed is routed separately by core.lua).
function MailHook.OnClosed()
  MailHook.open, MailHook.keepOpen, MailHook.pending = false, false, false
  if MailHook.window and MailHook.window:IsShown() then MailHook.window:Hide() end
end
