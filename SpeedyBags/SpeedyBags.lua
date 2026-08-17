local ADDON_NAME, ns = ...

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:RegisterEvent("BAG_UPDATE")
bootstrap:RegisterEvent("BANKFRAME_OPENED")
bootstrap:RegisterEvent("BANKFRAME_CLOSED")
bootstrap:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
bootstrap:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED")
bootstrap:RegisterEvent("BANK_TABS_CHANGED")
bootstrap:RegisterEvent("PLAYER_MONEY")
bootstrap:RegisterEvent("CURRENCY_DISPLAY_UPDATE")

-- Coalesces a burst of *_UPDATE events (mass loot, mailbox, vendor sell,
-- unboxing, depositing into the bank) into a single deferred model update
-- per view, so the event handler itself never blocks on a scan -- see
-- DESIGN.md invariant 4. Only runs while that view's frame is visible;
-- view.Show() forces a fresh update on open regardless. One scheduler
-- factory instead of writing this debounce twice (bag view + bank view).
local function MakeScheduler(model, frame)
	local pending = false
	return function()
		if not frame:IsShown() then return end
		if pending then return end
		pending = true
		C_Timer.After(0, function()
			pending = false
			model.Update()
		end)
	end
end

local ScheduleBagUpdate = MakeScheduler(ns.Model, ns.BagView.Frame)
local ScheduleBankUpdate = MakeScheduler(ns.BankModel, ns.BankView.Frame)

bootstrap:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		SpeedyBagsDB = SpeedyBagsDB or {}
		-- SavedVariables boundary (validate before use, per
		-- ~/.claude/CLAUDE.md's foreign-data policy) for UI.lua's
		-- collapsible section headers -- a stale save from before that
		-- feature existed won't have this key.
		SpeedyBagsDB.collapsedSections = SpeedyBagsDB.collapsedSections or {}
	elseif event == "BAG_UPDATE" then
		ScheduleBagUpdate()
	elseif event == "BANKFRAME_OPENED" then
		-- Blizzard's own default bank frame is already suppressed
		-- (Bank.lua's HideDefaultBank, applied once at load) so this is
		-- the only bank window the player sees.
		ns.BankView.Show()
	elseif event == "BANKFRAME_CLOSED" then
		ns.BankView.Hide()
	elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" or event == "BANK_TABS_CHANGED" then
		ScheduleBankUpdate()
	elseif event == "PLAYER_MONEY" or event == "CURRENCY_DISPLAY_UPDATE" then
		ns.Currency.Update()
	end
end)

-- Replace the default bag toggle -- same technique every combined-bag
-- addon uses (Bagnon, Baganator, etc.): these are plain global functions,
-- not secure handlers, so redefining them is safe and standard. Bag-only:
-- the bank view is opened/closed by the BANKFRAME_* events above, never by
-- these.
function ToggleBackpack() ns.Toggle() end
function ToggleAllBags() ns.Toggle() end
function ToggleBag() ns.Toggle() end
function OpenAllBags() if not ns.Frame:IsShown() then ns.Show() end end
function CloseAllBags() if ns.Frame:IsShown() then ns.Hide() end end

SLASH_SPEEDYBAGS1 = "/sbags"
SlashCmdList["SPEEDYBAGS"] = ns.Toggle
