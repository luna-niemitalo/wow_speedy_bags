local _, ns = ...

-- Ghost-item reconciliation (DESIGN.md "Transfer verification", TASKS.md
-- task 10). The existing single trailing rescan in Transfer.lua wasn't
-- enough for a multi-item batch where different items settle at different
-- times (user report, 2026-09-12: "often leaves ghost items behind"). Two
-- independent mechanisms here, plus a render-layer self-check that lives in
-- UI.lua's Refresh() (it needs the widget pools, which belong there):
--   1. A fast per-item verification loop for items Transfer.lua just moved --
--      registered via ns.VerifyMove, polls every VERIFY_INTERVAL until that
--      specific item's move is confirmed or the retry cap is hit.
--   2. A slow background ticker that force-rescans every model every
--      BACKGROUND_INTERVAL, independent of BAG_UPDATE-family events, as a
--      safety net against a missed/unexpected event -- the plausible root
--      cause of a ghost that never goes through Transfer.lua at all (plain
--      drag-and-drop, which has zero verification today).
-- Both mechanisms only ever call model.Update() (a cheap re-scan, see
-- Data.lua) plus a direct view Refresh() (itself a no-op while hidden) --
-- never anything synchronous in an event handler, per DESIGN.md invariant 4.

local VERIFY_INTERVAL = 0.3
local MAX_ATTEMPTS = 3
local BACKGROUND_INTERVAL = 5

-- Every model this addon has, alongside the view that needs a forced
-- Refresh() after a forced Update() -- this file doesn't otherwise know
-- about "views". ns.BagView/ns.BankView don't exist yet at this file's own
-- load time (UI.lua loads after Verify.lua, see the .toc) -- wrapped in
-- functions so they're only read at tick time, once they're real.
local MODELS = {
	{ model = ns.Model, view = function() return ns.BagView end },
	{ model = ns.PersonalBankModel, view = function() return ns.BankView end },
	{ model = ns.WarbandBankModel, view = function() return ns.BankView end },
}

-- Rescans every model unconditionally rather than tracking exactly which
-- ones a given record actually touches -- same reasoning Transfer.lua's own
-- RescanAllModels already used: Update() is a cheap re-scan either way, and
-- "which models are affected" is itself derived from bag-ID lists that could
-- overlap in ways not worth computing precisely here.
local function RescanAll()
	local refreshedViews = {}
	for _, entry in ipairs(MODELS) do
		entry.model.Update()
		local view = entry.view()
		if view and not refreshedViews[view] then
			view.Refresh()
			refreshedViews[view] = true
		end
	end
end

-- Locates the first slot in bagIDs holding the given identity -- a GUID for
-- equipment, an itemID for anything stackable. First occurrence is enough: a
-- retry only ever needs one occupied slot to act on. Always re-locates fresh
-- rather than trusting a remembered slot -- a stackable item's own slot
-- position isn't reliable across a multi-step transfer (Transfer.lua's own
-- StepQueue already re-checks the source slot at step time for the same
-- reason: an earlier step can shift bag contents).
local function FindSlot(record, bagIDs)
	for _, bagID in ipairs(bagIDs) do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		for slot = 1, numSlots do
			local info = C_Container.GetContainerItemInfo(bagID, slot)
			if info then
				if record.isEquipment then
					if C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bagID, slot)) == record.guid then
						return bagID, slot
					end
				elseif info.itemID == record.itemID then
					return bagID, slot
				end
			end
		end
	end
end

local function CountByItemID(itemID, bagIDs)
	local total = 0
	for _, bagID in ipairs(bagIDs) do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		for slot = 1, numSlots do
			local info = C_Container.GetContainerItemInfo(bagID, slot)
			if info and info.itemID == itemID then
				total = total + (info.stackCount or 1)
			end
		end
	end
	return total
end

-- Equipment: literal presence (never merges, so "somewhere in target and
-- nowhere in source" is an exact answer). Stackable: the count-delta THIS
-- move is responsible for, not a bare "does itemID X exist in the target
-- bags" check -- see TASKS.md task 10 on why a bare GUID isn't reliable once
-- a stackable item can merge into an existing destination stack; scoping to
-- the expected delta also means unrelated concurrent bag activity (looting
-- more of the same itemID mid-transfer) can't false-negative the check.
local function Settled(record)
	if record.isEquipment then
		local inSource = FindSlot(record, record.sourceBagIDs) ~= nil
		local inTarget = FindSlot(record, record.targetBagIDs) ~= nil
		return inTarget and not inSource, inSource and inTarget
	end

	local sourceDelta = record.beforeSourceCount - CountByItemID(record.itemID, record.sourceBagIDs)
	local targetDelta = CountByItemID(record.itemID, record.targetBagIDs) - record.beforeTargetCount
	return sourceDelta >= record.expectedDelta and targetDelta >= record.expectedDelta, false
end

local pending = {}
local ticking = false

local function Tick()
	if InCombatLockdown() then
		-- Never retry into a lockdown -- just wait it out, next tick
		-- re-checks (Transfer.lua's own queue is under the same guard).
		C_Timer.After(VERIFY_INTERVAL, Tick)
		return
	end

	for key, record in pairs(pending) do
		local done, inBoth = Settled(record)

		if done then
			pending[key] = nil
		elseif inBoth then
			-- Equipment found in both locations -- almost always a stale
			-- model, not a real duplicate (the textbook ghost). Force a real
			-- rescan and re-check once; if it's still in both after that,
			-- this is genuinely ambiguous and retrying a pickup against a
			-- possible real duplicate could make things worse, not better --
			-- log it and stop polling either way.
			RescanAll()
			local recheckDone = Settled(record)
			if not recheckDone then
				print("|cffff8080SpeedyBags|r: item "..tostring(record.itemID)
					.." appears to be in both its source and target location after a transfer -- please check manually.")
			end
			pending[key] = nil
		else
			record.attempts = record.attempts + 1
			if record.attempts > MAX_ATTEMPTS then
				-- Cap hit -- one last rescan (clears the common "just a
				-- stale cache" case even when nothing was left to retry)
				-- and stop polling; surface it rather than silently giving up.
				RescanAll()
				if not Settled(record) then
					print("|cffff8080SpeedyBags|r: item "..tostring(record.itemID)
						.." may not have moved correctly -- please check manually.")
				end
				pending[key] = nil
			else
				local bag, slot = FindSlot(record, record.sourceBagIDs)
				if bag then
					ns.RetryContainerMove(bag, slot, record.targetBagIDs)
				else
					-- Not found anywhere we're looking -- our cached view of
					-- the source might just be stale; force a rescan before
					-- the next tick tries to classify this again.
					RescanAll()
				end
			end
		end
	end

	if next(pending) ~= nil then
		C_Timer.After(VERIFY_INTERVAL, Tick)
	else
		ticking = false
	end
end

-- Called once per moved item by Transfer.lua, before that item's pickup/
-- place pair is issued (the "before" counts below need to be captured
-- pre-move). record: { key, isEquipment, guid?, itemID, expectedDelta,
-- sourceBagIDs, targetBagIDs }.
function ns.VerifyMove(record)
	record.attempts = 0
	if not record.isEquipment then
		record.beforeSourceCount = CountByItemID(record.itemID, record.sourceBagIDs)
		record.beforeTargetCount = CountByItemID(record.itemID, record.targetBagIDs)
	end
	pending[record.key] = record
	if not ticking then
		ticking = true
		C_Timer.After(VERIFY_INTERVAL, Tick)
	end
end

C_Timer.NewTicker(BACKGROUND_INTERVAL, RescanAll)
