local _, ns = ...

-- Soft-integrates with Pawn's own documented third-party-bag contract --
-- verified against Pawn's real installed source
-- (Interface/AddOns/Pawn/PawnBags.lua on the live client), whose own file
-- header explicitly documents this exact integration for bag addon
-- authors, not reverse-engineered:
--   1. PawnShouldItemLinkHaveUpgradeArrow(link, true) -> true/false/nil
--   2. nil means Pawn can't answer yet (its own per-frame throttle) --
--      check back soon.
--   3. PawnRegisterThirdPartyBag("name", { RefreshAll = ... }) disables
--      Pawn's own built-in ContainerFrame hooking entirely
--      (PawnIsAThirdPartyBagRegistered) -- this matters here specifically
--      because our slot buttons inherit the same
--      ContainerFrameItemButtonTemplate Pawn's default hooks target;
--      without registering, Pawn could try to update UpgradeIcon on our
--      buttons on its own schedule, racing our own render.
-- Optional throughout, same shape as Junk.lua's Leatrix_Plus integration:
-- does nothing if Pawn isn't installed/loaded.
if PawnRegisterThirdPartyBag then
	PawnRegisterThirdPartyBag("SpeedyBags", {
		RefreshAll = function()
			ns.Model.Update()
		end,
	})
end

-- @return isUpgrade: true, false, or nil (Pawn hasn't resolved this item
-- yet -- caller should treat nil as "not resolved," not "not an
-- upgrade," and re-check soon; see Data.lua's Scan/Model.Update)
function ns.IsUpgrade(itemLink)
	if not PawnShouldItemLinkHaveUpgradeArrow then
		return false
	end
	return PawnShouldItemLinkHaveUpgradeArrow(itemLink, true)
end
