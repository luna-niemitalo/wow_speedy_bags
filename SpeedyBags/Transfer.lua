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

-- Shared by StepQueue and Verify.lua's retry path (ns.RetryContainerMove
-- below) -- one pickup/place pair, same mechanism either way. Returns false
-- (and posts the no-space message) rather than issuing a half-formed move
-- when there's nowhere to put the item.
local function MoveOneItem(bag, slot, targetBagIDs)
	local targetBag, targetSlot = FindEmptySlot(targetBagIDs)
	if not targetBag then
		UIErrorsFrame:AddMessage("SpeedyBags: no space to transfer items.", 1, 0.1, 0.1, 1)
		return false
	end

	C_Container.PickupContainerItem(bag, slot)
	C_Container.PickupContainerItem(targetBag, targetSlot)
	ClearCursor()
	return true
end

-- Exposed for Verify.lua's fast per-item retry loop (TASKS.md task 10) --
-- retries against whatever slot the item currently occupies, never a
-- remembered one (a step earlier in the same batch, or unrelated bag
-- activity, can have shifted it since).
function ns.RetryContainerMove(bag, slot, targetBagIDs)
	if InCombatLockdown() then return false end
	if not C_Container.GetContainerItemInfo(bag, slot) then return false end
	return MoveOneItem(bag, slot, targetBagIDs)
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

-- Every model that reads from any bag/bank -- rescanned when a transfer
-- aborts outright (combat lockdown, no space) so the render doesn't keep
-- showing the click's stale starting picture. For the queue draining
-- normally, Verify.lua's per-item polling (registered once per entry before
-- the queue starts, below) is the actual mechanism that catches an
-- individual item still settling -- this blanket rescan is a floor for the
-- abort paths, not the fix for ghosting anymore (see TASKS.md task 10).
local function RescanAllModels()
	ns.Model.Update()
	ns.PersonalBankModel.Update()
	ns.WarbandBankModel.Update()
end

-- Moves one item per step, waiting a full frame (C_Timer.After(0, ...))
-- between each pickup/place pair before starting the next -- see this
-- function's own history in TASKS.md/TODO.md for why (PickupContainerItem
-- doesn't complete synchronously enough to chain multiple pairs in one Lua
-- call). Whether each pickup/place pair actually landed is Verify.lua's job
-- now, not this loop's -- the records for the whole batch are already
-- registered (see ns.TransferEntries) before this starts stepping.
local function StepQueue(queue, i, targetBagIDs)
	if InCombatLockdown() then
		RescanAllModels()
		return
	end

	local move = queue[i]
	if not move then
		return
	end

	-- Re-check the source slot at step time, not queue-build time -- an
	-- earlier step in this same transfer may have shifted bag contents
	-- (e.g. a stack behind it compacting forward).
	if not C_Container.GetContainerItemInfo(move.bag, move.slot) then
		StepQueue(queue, i + 1, targetBagIDs)
		return
	end

	if not MoveOneItem(move.bag, move.slot, targetBagIDs) then
		RescanAllModels()
		return
	end

	C_Timer.After(0, function()
		StepQueue(queue, i + 1, targetBagIDs)
	end)
end

-- sourceBagIDs is the bag-ID list the entries actually came from (the
-- transferring group's own model -- see UI.lua's group.model.getBagIDs),
-- needed by Verify.lua to know where to look for "did it actually leave."
function ns.TransferEntries(entries, targetBagIDs, sourceBagIDs)
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

	-- Registered up front, once per entry (not once per physical slot --
	-- Data.lua already merged same-itemID slots into one entry with the
	-- correct total count), before anything actually moves -- Verify.lua
	-- needs its "before" snapshot pre-move.
	for _, entry in ipairs(entries) do
		ns.VerifyMove({
			key = entry.key,
			isEquipment = entry.isEquipment,
			guid = entry.guid,
			itemID = entry.itemID,
			expectedDelta = entry.count,
			sourceBagIDs = sourceBagIDs,
			targetBagIDs = targetBagIDs,
		})
	end

	StepQueue(queue, 1, targetBagIDs)
end
