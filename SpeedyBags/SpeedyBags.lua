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
-- Warband Bank's own deposited-gold balance (UI.lua's bank-view currency
-- row, "warbandGoldOnly" mode) -- separate from the player's own
-- GetMoney(), which PLAYER_MONEY already covers.
bootstrap:RegisterEvent("ACCOUNT_MONEY")

-- Coalesces a burst of *_UPDATE events (mass loot, mailbox, vendor sell,
-- unboxing, depositing into the bank) into a single deferred model.Update()
-- per model, so the event handler itself never blocks on a scan -- see
-- DESIGN.md invariant 4.
--
-- Deliberately NOT gated on the owning view's visibility (corrected
-- 2026-08-17, user correction: opening the window used to force a full
-- Update() -- a full re-scan -- every single time, which is exactly the
-- "recompute it every time you open the container" cost this addon exists
-- to NOT have; other bag addons being slow to open is this project's
-- founding complaint, per DESIGN.md's own Purpose section). Scanning is
-- cheap (a GetContainerItemInfo loop, no widget creation), so it keeps
-- running in the background regardless of whether the window is open --
-- exactly like Currency.lua's own PLAYER_MONEY/CURRENCY_DISPLAY_UPDATE
-- handling always has. The expensive part (UI.lua's Refresh -- building
-- and positioning hundreds of widgets) still only runs while its frame is
-- actually shown (Refresh's own IsShown() guard) -- that split is the
-- whole point: by the time the player opens the window, the data is
-- already current, so Show() only has to pay for one render pass, not a
-- scan AND a render.
local function MakeScheduler(model)
	local pending = false
	return function()
		if pending then return end
		pending = true
		C_Timer.After(0, function()
			pending = false
			model.Update()
		end)
	end
end

local ScheduleBagUpdate = MakeScheduler(ns.Model)
-- Personal (character) and Warband (account) bank each get their own
-- scheduler -- Bank.lua's two models replaced the old single merged
-- ns.BankModel (see its own header comment for why: combining their
-- empty-slot counts was actively misleading). PLAYERBANKSLOTS_CHANGED and
-- PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED are themselves already
-- bank-type-specific (Character vs Account), so each routes to just the
-- one model it actually affects; BANK_TABS_CHANGED (a tab purchased)
-- doesn't say which type, so it updates both to be safe.
local SchedulePersonalBankUpdate = MakeScheduler(ns.PersonalBankModel)
local ScheduleWarbandBankUpdate = MakeScheduler(ns.WarbandBankModel)

bootstrap:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		SpeedyBagsDB = SpeedyBagsDB or {}
		-- SavedVariables boundary (validate before use, per
		-- ~/.claude/CLAUDE.md's foreign-data policy) for UI.lua's
		-- collapsible section headers -- a stale save from before that
		-- feature existed won't have this key.
		SpeedyBagsDB.collapsedSections = SpeedyBagsDB.collapsedSections or {}
		-- Same boundary, for UI.lua's real bank tabs (opts.name ->
		-- selected group index) -- a stale save from before tabs existed
		-- won't have this key either.
		SpeedyBagsDB.selectedGroup = SpeedyBagsDB.selectedGroup or {}
	elseif event == "BAG_UPDATE" then
		ScheduleBagUpdate()
	elseif event == "BANKFRAME_OPENED" then
		-- Unlike bags (always with the player, so BAG_UPDATE keeps
		-- ns.Model warm continuously regardless of location -- see
		-- MakeScheduler above), bank contents genuinely aren't available
		-- until this exact moment: there's no equivalent event that could
		-- have pre-warmed ns.PersonalBankModel/ns.WarbandBankModel before
		-- the player physically reached a banker, so both are still sitting
		-- on their initial empty state the very first time this fires.
		-- Fixed 2026-08-17, user report (both bank tabs showing empty on
		-- open) -- an explicit forced Update() here, exactly once per
		-- actual bank visit, isn't the "recompute every time you open the
		-- window" cost the scan/render decoupling above was fixed to avoid
		-- (BANKFRAME_OPENED fires on arriving at a banker, not on toggling
		-- our own UI -- closing and reopening SpeedyBags' own bank window
		-- without leaving the banker doesn't re-fire this at all).
		ns.PersonalBankModel.Update()
		ns.WarbandBankModel.Update()
		-- Blizzard's own default bank frame is already suppressed
		-- (Bank.lua's HideDefaultBank, applied once at load) so this is
		-- the only bank window the player sees.
		ns.BankView.Show()
	elseif event == "BANKFRAME_CLOSED" then
		ns.BankView.Hide()
	elseif event == "PLAYERBANKSLOTS_CHANGED" then
		SchedulePersonalBankUpdate()
	elseif event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" then
		ScheduleWarbandBankUpdate()
	elseif event == "BANK_TABS_CHANGED" then
		SchedulePersonalBankUpdate()
		ScheduleWarbandBankUpdate()
	elseif event == "PLAYER_MONEY" or event == "CURRENCY_DISPLAY_UPDATE" then
		ns.Currency.Update()
	elseif event == "ACCOUNT_MONEY" then
		ns.BankView.Refresh()
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
