local _, ns = ...

-- Bank bag IDs aren't static like ns.BAG_IDS -- which tabs exist depends on
-- which the player has actually purchased, and that can change mid-session
-- (buying a new tab at the banker). C_Bank.FetchPurchasedBankTabIDs
-- returns exactly the purchased Enum.BagIndex values for a given
-- Enum.BankType, already gated on purchase state -- Blizzard's own bank
-- frame checks this before touching a tab rather than blindly scanning a
-- fixed CharacterBankTab_1..6 / AccountBankTab_1..5 range and hoping
-- unpurchased tabs return 0 slots harmlessly, so this does the same.
--
-- The old standalone Reagent Bank has no separate BagIndex in the modern
-- client -- it was folded into the regular character-bank tabs -- so no
-- extra list is needed for it here.
--
-- Personal (character) and Warband (account) bank are two SEPARATE models
-- now, not one merged scan -- corrected 2026-08-17 after the user pointed
-- out that combining their empty-slot counts into one number actively
-- misleads: warband bank space is shared across every character on the
-- account, personal bank space isn't accessible to any of them, so "you
-- have N empty slots" meant something different depending which number
-- was hiding inside that one combined total. Splitting the models also
-- naturally keeps them visually distinct in UI.lua (its own section/
-- subcategory grouping per bank, like Blizzard's own tabs), which the
-- user asked for directly -- one merged Scan couldn't do both without
-- inventing a second grouping axis Data.lua never needed before.
--
-- Bank content itself is driven entirely off C_Bank/C_Container, never by
-- reading state back off the BankFrame/BankPanel objects -- see
-- HideDefaultBank below for the one place this module does touch them.
function ns.GetPersonalBankBagIDs()
	if not C_Bank then return {} end
	return C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character)
end

function ns.GetWarbandBankBagIDs()
	if not C_Bank then return {} end
	return C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account)
end

ns.PersonalBankModel = ns.NewModel(ns.GetPersonalBankBagIDs)
ns.WarbandBankModel = ns.NewModel(ns.GetWarbandBankBagIDs)

-- Warband Bank's own deposited-gold balance -- a real, separate pool from
-- the player's own GetMoney(), unlike the personal bank (which has no
-- currency store of its own; it's just character gold, already shown in
-- the bag view's currency row). Used by UI.lua's bank-view currency row
-- instead of the bag view's full pinned-currency list: per the user's own
-- reasoning, a bank can't hold any currency other than what it actually,
-- literally stores -- Artisan's Mettle/Delve currencies etc. aren't bank
-- content at all, showing them on the bank view implied otherwise.
function ns.GetWarbandBankGold()
	if not C_Bank then return 0 end
	return C_Bank.FetchDepositedMoney(Enum.BankType.Account)
end

-- Equivalent to Blizzard's old "Deposit Reagents" button, which
-- disappeared from view once HideDefaultBank (below) suppressed the
-- default bank frame entirely -- the user asked for it back somewhere in
-- our own chrome. C_Bank.AutoDepositItemsIntoBank(bankType) deposits
-- whatever's flagged for auto-deposit on that bank type's purchased tabs
-- (UpdateBankTabSettings' depositFlags -- the same setting Blizzard's own
-- tab-management UI controls, e.g. a tab flagged to auto-accept crafting
-- reagents); it's the modern equivalent now that the old standalone
-- Reagent Bank was folded into regular tabs.
--
-- Takes a specific bankType now -- corrected 2026-08-17, user correction:
-- an earlier version tried both bank types unconditionally on the
-- assumption "whichever one has the flag" was an unambiguous answer, but
-- the user has a reagent-deposit tab configured on BOTH banks, so it
-- genuinely wasn't. UI.lua's button now passes whichever bank is
-- currently the selected tab.
function ns.DepositReagents(bankType)
	if InCombatLockdown() or not C_Bank or not bankType then return end
	if C_Bank.DoesBankTypeSupportAutoDeposit(bankType) then
		C_Bank.AutoDepositItemsIntoBank(bankType)
	end
end

---------------------------------------------------------------
-- Suppressing Blizzard's own default bank window
---------------------------------------------------------------
-- User asked to look at how Baganator does this rather than leaving
-- SpeedyBags' bank view opening alongside Blizzard's default one.
-- Baganator's real, shipped code (references/Baganator/ViewManagement/
-- Initialize.lua's HideDefaultBank, called unconditionally from
-- ViewManagement.Initialize() at addon load) reparents BankFrame onto a
-- hidden frame and clears its OnHide/OnEvent/OnShow scripts -- in
-- production, for a widely-used addon, with no reported taint fallout.
-- That corrects DESIGN.md's earlier, more cautious note (grounded in
-- BetterBags' own patterns-taint.md, which reads broader than what
-- actually causes trouble): SetParent/SetScript(nil) on BankFrame itself
-- doesn't taint UseContainerItem in practice. What DESIGN.md's taint note
-- is really about -- reading state like BankFrame:GetActiveBankType() from
-- a tainted call chain -- SpeedyBags never does, since the Get*BankBagIDs
-- functions above are driven entirely off C_Bank/C_Container instead. Not independently
-- verified in-game by us yet; adopted on the strength of Baganator's own
-- production use, per the user's explicit direction to follow that
-- pattern.
local hidden = CreateFrame("Frame")
hidden:Hide()

local function HideDefaultBank()
	BankFrame:SetParent(hidden)
	BankFrame:SetScript("OnHide", nil)
	BankFrame:SetScript("OnEvent", nil)
	BankFrame:SetScript("OnShow", nil)
end
HideDefaultBank()
