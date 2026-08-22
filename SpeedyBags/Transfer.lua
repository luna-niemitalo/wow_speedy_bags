local _, ns = ...

-- Right-click "move this whole category to the other view" (UI.lua wires
-- this to section headers and subcategory labels). PickupContainerItem is
-- NOT itself protected (only UseContainerItem is -- see DESIGN.md's
-- "Protected functions (taint)" note and Pawn.lua's own comment on the
-- same fact), so this pickup-then-place pair is safe to call from our own
-- insecure code -- verified against Baganator's own real, shipped
-- Transfers/FromBagsToBags.lua, which does the exact same pair
-- (PickupContainerItem source, PickupContainerItem target, ClearCursor).

local function FindEmptySlot(bagIDs)
	for _, bagID in ipairs(bagIDs) do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		for slot = 1, numSlots do
			if not C_Container.GetContainerItemInfo(bagID, slot) then
				return bagID, slot
			end
		end
	end
end

-- Flattens the section/subcategory's entries into one queue of individual
-- (bag, slot) moves -- one per real backing slot, not one per merged
-- visual stack.
local function BuildQueue(entries)
	local queue = {}
	for _, entry in ipairs(entries) do
		for _, loc in ipairs(entry.locations) do
			table.insert(queue, { bag = loc.bag, slot = loc.slot })
		end
	end
	return queue
end

-- Every model that reads from any bag/bank -- rescanned once a transfer
-- finishes so the render reflects real state instead of whatever partial
-- picture the click's original Refresh was taken from. Fixes the "ghost
-- items" bug (Data.lua/Bank.lua already make Update() a cheap re-scan, so
-- refreshing all three unconditionally rather than tracking exactly which
-- ones were touched is simpler and correct either way).
local function RescanAllModels()
	ns.Model.Update()
	ns.PersonalBankModel.Update()
	ns.WarbandBankModel.Update()
end

-- Moves one item per step, waiting a full frame (C_Timer.After(0, ...))
-- between each pickup/place pair before starting the next -- rebuilt
-- 2026-08-17 as a step-driven queue (was previously a single synchronous
-- loop over every item; user report: "only the first item actually
-- moves"). PickupContainerItem doesn't complete synchronously enough for
-- the client to have the target slot's new contents visible to the very
-- next PickupContainerItem call in the same frame -- confirmed against
-- Baganator's own real, shipped Transfers/FromBagsToBags.lua, which is
-- built the same way (an explicit step machine driven across frames/ticks,
-- not one synchronous loop) rather than assuming PickupContainerItem is
-- instant.
local function StepQueue(queue, i, targetBagIDs)
	if InCombatLockdown() then
		RescanAllModels()
		return
	end

	local move = queue[i]
	if not move then
		RescanAllModels()
		return
	end

	-- Re-check the source slot at step time, not queue-build time -- an
	-- earlier step in this same transfer may have shifted bag contents
	-- (e.g. a stack behind it compacting forward).
	if not C_Container.GetContainerItemInfo(move.bag, move.slot) then
		StepQueue(queue, i + 1, targetBagIDs)
		return
	end

	local targetBag, targetSlot = FindEmptySlot(targetBagIDs)
	if not targetBag then
		UIErrorsFrame:AddMessage("SpeedyBags: no space to transfer items.", 1, 0.1, 0.1, 1)
		RescanAllModels()
		return
	end

	C_Container.PickupContainerItem(move.bag, move.slot)
	C_Container.PickupContainerItem(targetBag, targetSlot)
	ClearCursor()

	C_Timer.After(0, function()
		StepQueue(queue, i + 1, targetBagIDs)
	end)
end

function ns.TransferEntries(entries, targetBagIDs)
	if InCombatLockdown() then
		-- Bulk item movement breaks under combat lockdown -- a real
		-- Blizzard restriction (see Baganator's own transfer code, same
		-- guard), not something SpeedyBags can work around.
		return
	end

	local queue = BuildQueue(entries)
	if #queue == 0 then
		return
	end

	StepQueue(queue, 1, targetBagIDs)
end
