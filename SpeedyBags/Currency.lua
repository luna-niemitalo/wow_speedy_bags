local _, ns = ...

-- Mirrors Blizzard's own currency-backpack pinning (right-click a currency
-- in the Currency tab of the Character panel -> "Show in Backpack")
-- instead of a hardcoded currency list for most of the user's wishlist
-- here (Shard of Dundun's, Restored Coffer Keys, Coffer Key Shards,
-- Remnants of Anguish, Field Accolades) -- their IDs aren't verifiable
-- from the offline reference mirrors this addon is built against, and
-- guessing risks silently pulling in the wrong currency, so the user pins
-- those themselves via Blizzard's real UI. User-directed decision,
-- 2026-08-17.
--
-- Artisan's Moxie is the one exception: the user supplied real currency
-- IDs directly (Scribe's 3261, Alchemist's 3256) and asked for the rest to
-- be looked up and auto-pinned per trained profession -- see
-- AutoPinProfessionMoxie below.
local SAFETY_CAP = 32 -- Blizzard's own backpack-currency slot count isn't
                       -- a documented constant we could find in the
                       -- reference mirrors; loop until GetBackpackCurrencyInfo
                       -- returns nil instead of hardcoding a guessed cap,
                       -- same as Baganator's own CurrencyBlizzardTracking.lua.

local function ScanBackpackCurrencies()
	local list = {}
	for i = 1, SAFETY_CAP do
		local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
		if not info then break end
		table.insert(list, info)
	end
	return list
end

-- ns.Currency.list is an array of BackpackCurrencyInfo:
-- { name, quantity, iconFileID, currencyTypesID }
ns.Currency = {
	gold = 0,
	list = {},
}

local listeners = {}

function ns.Currency.OnChanged(fn)
	table.insert(listeners, fn)
end

function ns.Currency.Update()
	ns.Currency.gold = GetMoney()
	ns.Currency.list = ScanBackpackCurrencies()
	for _, fn in ipairs(listeners) do
		fn()
	end
end

-- Fires the instant the player toggles "Show in Backpack" on a currency in
-- Blizzard's own Character/Currency panel, so the row updates immediately
-- rather than waiting for the next unrelated CURRENCY_DISPLAY_UPDATE.
-- EventRegistry callbacks can be registered before the owning UI
-- (Blizzard_TokenUI) has ever loaded -- unlike a global function reference,
-- this doesn't depend on load order.
EventRegistry:RegisterCallback("TokenFrame.OnTokenWatchChanged", ns.Currency.Update)

---------------------------------------------------------------
-- Artisan's Moxie: one currency per crafting/gathering profession
-- (Midnight expansion's Knowledge catch-up system -- see the tooltip the
-- user showed: "Used for purchasing Midnight Inscription recipes,
-- acquiring single-use tomes of Knowledge from Midnight Renowns...").
-- Which one applies depends entirely on which professions the character
-- has trained, so this pins automatically rather than needing the player
-- to hand-pin the right one per alt.
---------------------------------------------------------------
-- One table is the single source for both the skillLine->currencyID
-- auto-pin lookup (below) and the currencyID->color the currency row uses
-- to tint each Moxie's border (UI.lua's RenderCurrencyRow) -- user
-- feedback, 2026-08-17: two Moxie currencies rendered as "the same gray
-- icon twice", indistinguishable without hovering. Colors are thematic per
-- profession (potion green for Alchemy, forge red-orange for
-- Blacksmithing, etc.), spread across the color wheel so all eleven stay
-- distinguishable from each other, not just individually plausible.
--
-- skillLine is the locale-independent numeric ID
-- C_TradeSkillUI.GetAllProfessionTradeSkillLines() returns, stable since
-- Classic (the same IDs many other addons already hardcode for this exact
-- reason) -- not to be confused with currencyID, a completely different
-- numbering space. Currency IDs: user supplied Alchemist's (3256) and
-- Scribe's/Inscription's (3261) directly; the rest were looked up
-- (Wowhead currency pages, 2026-08-17) to complete the set once the
-- 3256-3266 alphabetical-by-profession pattern was confirmed against those
-- two known points -- not guessed.
local PROFESSION_MOXIE = {
	{ skillLine = 171, currencyID = 3256, color = { 0.20, 0.75, 0.30 } }, -- Alchemy: potion green
	{ skillLine = 164, currencyID = 3257, color = { 0.85, 0.30, 0.10 } }, -- Blacksmithing: forge red-orange
	{ skillLine = 333, currencyID = 3258, color = { 0.65, 0.35, 0.90 } }, -- Enchanting: arcane purple
	{ skillLine = 202, currencyID = 3259, color = { 0.90, 0.75, 0.15 } }, -- Engineering: brass gold
	{ skillLine = 182, currencyID = 3260, color = { 0.55, 0.85, 0.25 } }, -- Herbalism: leaf lime
	{ skillLine = 773, currencyID = 3261, color = { 0.25, 0.55, 0.95 } }, -- Inscription: ink blue
	{ skillLine = 755, currencyID = 3262, color = { 0.20, 0.85, 0.85 } }, -- Jewelcrafting: gem teal
	{ skillLine = 165, currencyID = 3263, color = { 0.55, 0.35, 0.15 } }, -- Leatherworking: hide brown
	{ skillLine = 186, currencyID = 3264, color = { 0.65, 0.65, 0.70 } }, -- Mining: ore gray
	{ skillLine = 393, currencyID = 3265, color = { 0.60, 0.15, 0.15 } }, -- Skinning: blood maroon
	{ skillLine = 197, currencyID = 3266, color = { 0.90, 0.40, 0.70 } }, -- Tailoring: thread pink
}

local skillLineToCurrency = {}
ns.Currency.professionColor = {} -- currencyID -> {r, g, b}, read by UI.lua
for _, p in ipairs(PROFESSION_MOXIE) do
	skillLineToCurrency[p.skillLine] = p.currencyID
	ns.Currency.professionColor[p.currencyID] = p.color
end

-- Additive and idempotent only -- never un-pins a currency the player
-- manages themselves, and pinning an already-pinned currency is a no-op,
-- so this is safe to call as often as professions might change (learning
-- a new one, or on every login as a correctness sweep).
local function AutoPinProfessionMoxie()
	if not (C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines) then return end

	local pinnedAny = false
	for _, skillLineID in ipairs(C_TradeSkillUI.GetAllProfessionTradeSkillLines()) do
		local currencyID = skillLineToCurrency[skillLineID]
		if currencyID then
			C_CurrencyInfo.SetCurrencyBackpackByID(currencyID, true)
			pinnedAny = true
		end
	end

	if pinnedAny then
		-- SetCurrencyBackpackByID called directly (not via Blizzard's own
		-- TokenFrameMixin:SetTokenWatched) doesn't reliably fire the
		-- TokenFrame.OnTokenWatchChanged callback above -- refresh
		-- explicitly rather than hoping CURRENCY_DISPLAY_UPDATE follows.
		ns.Currency.Update()
	end
end

local professionEvents = CreateFrame("Frame")
professionEvents:RegisterEvent("PLAYER_LOGIN")
professionEvents:RegisterEvent("SKILL_LINES_CHANGED")
professionEvents:SetScript("OnEvent", AutoPinProfessionMoxie)
