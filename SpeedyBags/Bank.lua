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
-- Warband (account) bank listed first, character bank second: the user
-- asked for the bank view to default to the warband bank, and since this
-- is one combined view rather than tabs (matching the bag view's own
-- combined-bags philosophy), "default to" means scan/render order here --
-- warband items land first in the merged view.
--
-- Bank content itself is driven entirely off C_Bank/C_Container, never by
-- reading state back off the BankFrame/BankPanel objects -- see
-- HideDefaultBank below for the one place this module does touch them.
function ns.GetBankBagIDs()
	local bagIDs = {}
	if not C_Bank then return bagIDs end

	for _, bagID in ipairs(C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account)) do
		table.insert(bagIDs, bagID)
	end
	for _, bagID in ipairs(C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character)) do
		table.insert(bagIDs, bagID)
	end
	return bagIDs
end

ns.BankModel = ns.NewModel(ns.GetBankBagIDs)

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
-- a tainted call chain -- SpeedyBags never does, since GetBankBagIDs above
-- is driven entirely off C_Bank/C_Container instead. Not independently
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
