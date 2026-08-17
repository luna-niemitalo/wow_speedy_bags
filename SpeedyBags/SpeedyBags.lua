local ADDON_NAME, ns = ...

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:RegisterEvent("BAG_UPDATE")

-- Coalesces a burst of BAG_UPDATE events (mass loot, mailbox, vendor sell,
-- unboxing) into a single deferred model update, so the event handler
-- itself never blocks on a bag scan -- see DESIGN.md invariant 4. Only
-- runs at all while the frame is visible; ns.Show() forces a fresh update
-- on open regardless.
local updatePending = false
local function ScheduleModelUpdate()
	if updatePending then return end
	updatePending = true
	C_Timer.After(0, function()
		updatePending = false
		ns.Model.Update()
	end)
end

bootstrap:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		SpeedyBagsDB = SpeedyBagsDB or {}
	elseif event == "BAG_UPDATE" then
		if ns.Frame:IsShown() then
			ScheduleModelUpdate()
		end
	end
end)

-- Replace the default bag toggle -- same technique every combined-bag
-- addon uses (Bagnon, Baganator, etc.): these are plain global functions,
-- not secure handlers, so redefining them is safe and standard.
function ToggleBackpack() ns.Toggle() end
function ToggleAllBags() ns.Toggle() end
function ToggleBag() ns.Toggle() end
function OpenAllBags() if not ns.Frame:IsShown() then ns.Show() end end
function CloseAllBags() if ns.Frame:IsShown() then ns.Hide() end end

SLASH_SPEEDYBAGS1 = "/sbags"
SlashCmdList["SPEEDYBAGS"] = ns.Toggle
