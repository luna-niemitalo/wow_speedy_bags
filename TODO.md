# TODO — implementation plan

Ordered checklist. Items tagged `(task N)` still need their `TASKS.md` investigation
resolved first — don't build past them until that task has a recorded decision.

## Known gaps
- [x] ~~In-combat item use/pickup~~ — resolved: slot buttons inherit Blizzard's real
      `ContainerFrameItemButtonTemplate`, so clicks are untainted in and out of
      combat. See `DESIGN.md` § Protected functions (taint) for the full story
      (including a wrong first diagnosis, corrected against a real repro).
- [x] ~~Blue "new item" glow on every slot after reload/relog/character-switch~~ —
      resolved 2026-08-16: `UI.lua`'s `ClearNewItemGlow` replicates Blizzard's own
      `ContainerFrameItemButtonMixin:OnUpdate` clear (`C_NewItems.RemoveNewItem` +
      hide `NewItemTexture` + stop `flashAnim`/`newitemglowAnim`), since we never
      call `UpdateNewItem` ourselves and "Recent items" tracking isn't real yet —
      suppressed outright rather than left in its broken always-on state. Real bug,
      found by the user in-game, not anticipated.
- [x] ~~Double border on item slots~~ — resolved 2026-08-17 (corrected twice: the
      first fix, `SetNormalTexture(nil)`, crashed the addon outright — the setter
      genuinely doesn't accept nil, confirmed live via `LUNA_NOTES.md`). Real fix:
      `btn:GetNormalTexture():SetTexture(nil)` then `:Hide()` on the region itself,
      matching BetterBags' own documented workaround for this exact
      `ContainerFrameItemButtonTemplate` quirk. Keeps only the quality-colored
      `IconBorder`. Lesson: I'd already read BetterBags' workaround for this same
      issue earlier in the session and didn't apply it correctly the first time —
      worth being more careful cross-referencing prior findings before writing
      similar fixes.
- [x] ~~Addon frame rendering behind static UI elements~~ — resolved 2026-08-17:
      `frame:SetToplevel(true)`, matching Blizzard's own `ContainerFrameCombinedBags`
      (`ContainerFrame.xml:290`) — same `MEDIUM` strata as Blizzard's bag frame
      already (not the actual issue), but missing `toplevel` meant no auto-raise
      within that strata. Found by the user in-game.
- [x] ~~Icons too small, covered by their own overlay text~~ — resolved 2026-08-17:
      reverted `SLOT_SIZE` from 30 back to Blizzard's real default 37 — the actual
      problem was fighting the proportions `Count`/`UpgradeIcon`/`IconBorder` are
      natively sized for, not a font-size issue. Found by the user in-game.
- [x] ~~"Use:" items should get their own category ("unboxable items")~~ — resolved
      2026-08-17: `Categories.lua`'s `HasUseEffect`, scoped to only the final
      Miscellaneous fallback (not every usable item — consumables/quest items
      already have a real subcategory). Detected via a `C_TooltipInfo.GetBagItem`
      line text match for the literal "Use:" prefix (no structured
      `TooltipDataLineType` for it, unlike `ItemUpgradeLevel`) — same untested-
      against-a-live-tooltip caveat as the reward-track parsing.
- [x] ~~Subcategory groups need a visual background to distinguish them~~ — resolved
      2026-08-17: a subtle (`alpha 0.05` white) background panel per subcategory
      block, pooled and sized to the block's own computed height.
- [x] ~~"Artisan bags" (Crafting Order reward containers) not merging despite
      sharing an itemID~~ — resolved 2026-08-16: `Data.lua`'s `IsEquipment` checked
      "has any itemEquipLoc," which also matches non-equipment inventory types like
      `INVTYPE_BAG` (bags), `INVTYPE_TABARD`, `INVTYPE_BODY` — none of which have
      the per-instance state (upgrade rank/enchants/sockets) that's the actual
      reason Weapon/Armor stay unmerged. Narrowed to classID 2/4, matching what
      `Categories.lua` already independently checked for Equipment-section
      assignment — the two were inconsistent before, now the same check. Also
      moved item level onto Count's own corner (BOTTOMRIGHT, quality-colored to
      stay visually distinct from Count's plain white) instead of its own corner,
      per the user's actual Baganator icon-corner convention (item level/keystone
      level/quantity share one corner safely since they never co-occur).

## Tooling
- [ ] Install `wowlua-ls` in VS Code, confirm real hover/autocomplete on a
      `C_Container` call (task 5's last unverified step)
- [ ] Verify `nix/flake.nix` actually builds (`direnv exec .`) on the real system —
      untested in the sandbox that scaffolded it

## Framework decision
- [ ] Resolve task 6 (Ace3/LibStub/CallbackHandler — yes/no per piece) before writing
      any addon code beyond the current stub

## Data layer
- [ ] Resolve task 3 (event coalescing model — what triggers a re-render, at what
      granularity)
- [x] ~~Resolve task 4 (junk classification rule; Junk-slot interaction model)~~ —
      resolved 2026-08-16: reads Leatrix_Plus's own `_G.LeaPlusDB` (quality ==
      Poor + sellable, minus its exclude list/Keeper Ta'hult/grey-gear settings),
      falling back to Blizzard's bare Poor-quality rule if Leatrix_Plus isn't
      loaded. See `Junk.lua` and `DESIGN.md`'s external-integration note. No
      interaction model yet — the Junk slot displays count + hover-tooltip sell
      value, doesn't sell anything itself (Leatrix_Plus already does that).
- [ ] Bag/bank/currency state model, decoupled from rendering
- [ ] Subscribe to `BAG_UPDATE`-family events; diff, don't rebuild
- [x] ~~Junk classification as a single boundary~~ — resolved: `ns.IsJunk` in
      `Junk.lua` is the one field → one check → one destination point; `Data.lua`'s
      `Scan()` calls it once per slot and never creates a normal entry for junk.

## Render layer
- [x] ~~Item slot widget, built on the real `ItemButtonTemplate`~~ — resolved via
      `ContainerFrameItemButtonTemplate` (see Known gaps above; same fix, same file).
- [x] ~~Category-header widget~~ — resolved 2026-08-16: `Categories.lua` classifies
      each entry into a section (Crafting/Equipment/Misc/Old Stuff) + subcategory
      (source-based for crafting reagents, quality-or-slot for equipment depending on
      bind status, expansion name for outdated items); `UI.lua` renders sectioned,
      flow-wrapped subcategory blocks. This reverses the original MVP's "no
      categories" scoping decision — the user's own Baganator layout turned out to be
      a real usability requirement, not optional polish. Section headers still need
      `nodeignore` tagging once ConsolePort nav integration lands (see below) — not
      done yet, this pass was display-only.
- [x] ~~Junk aggregate slot widget (count/space-consumed, not per-item)~~ —
      resolved 2026-08-16: shares a row with the Empty widget (`UI.lua`'s
      `RenderAggregateRow`), count + total sell-value tooltip, no individual junk
      slots rendered.
- [ ] "Recent items" tracking (`C_NewItems.IsNewItem`) — the reference layout's
      Empty row is actually a Recent+Empty row; only Empty is implemented so far.
      Note: `C_NewItems.RemoveNewItem` is now called on every render
      (`ClearNewItemGlow`), so this would need its own "seen it in SpeedyBags"
      tracking rather than relying on Blizzard's own new-item flag, which we
      already clear for the unrelated glow-suppression fix above.
- [x] ~~Pawn integration (upgrade arrows + item level on equipment)~~ — resolved
      2026-08-16: `Pawn.lua` uses Pawn's own first-party third-party-bag API
      (`PawnRegisterThirdPartyBag`/`PawnShouldItemLinkHaveUpgradeArrow` — Pawn's own
      source documents this contract explicitly). `UpgradeIcon` is a native
      `ContainerFrameItemButtonTemplate` region, no new texture needed. Item level
      via `C_Item.GetDetailedItemLevelInfo` (accounts for upgrades, unlike
      `GetItemInfo`'s static base ilvl). Nil ("Pawn hasn't answered yet") triggers
      one deferred re-scan rather than leaving arrows unresolved.
- [ ] Wire render layer to data-layer diffs — patch only changed slots, never a
      full-frame rebuild in the loot/vendor/mail/unbox hot path (invariant 4)
- [x] ~~Keep slot frame identity stable across content changes~~ — resolved: slot
      widgets are pooled by `entry.key` (stable item identity — itemID for merged
      stacks, item GUID for equipment), not list position, so a new item appearing
      earlier in bag/slot scan order can no longer silently reassign an existing
      widget to a different item. Real bug hit and fixed 2026-08-16 (combining
      reagents into a new item type shifted scan order). Prerequisite for invariant
      2, not the whole thing — ConsolePort's own reselection is still task 2.

## ConsolePort nav integration
- [ ] Nav graph module: `graph[node][direction] = target`, built alongside slot
      layout
- [ ] Monkey-patch `Cursor:Navigate` (`ConsolePort_Cursor/View/Cursor.lua`, via
      `db.Cursor`) — `pcall`/shape-check guarded — to consult the graph first, fall
      through to the original geometric scan per-direction when no edge exists
- [ ] Tag every non-item-slot frame (category headers, Junk slot if applicable) with
      `SetAttribute('nodeignore', true)` — mandatory regardless of graph, it's the
      fallback's correctness net
- [ ] Tag item slots with `nodepriority` for cursor-stability reselection bias
- [ ] Verify fallback path with ConsolePort's Navigate unpatched/absent: nav still
      resolves cleanly via geometry + the above tags alone

## Cursor stability
- [ ] Verify cursor stays on the acted-on slot/stack across loot, sell, mail, and
      container-opening flows (invariant 2)
- [ ] Confirm the Knowledge Point UI surface (bag slot vs. separate frame) before
      building its fix (task 2)

## Validation (in-game, manual)
- [ ] Up/down/left/right from any item slot never lands on a category header
      (invariant 1)
- [ ] Bulk loot/mail/vendor operations never block interaction with other frames
      (invariant 4)
- [ ] Junk slot count matches actual aggregated junk, no per-item junk slots leak
      through
- [ ] `luacheck` clean

## Future ideas (not scoped, from LUNA_NOTES.md)
Explicitly speculative — the user's own framing on the second one was "don't pull
colors and shit from this, it's literally I made it in paint, so it's shit." Neither
is a decision, just a direction worth remembering.
- Per-item label row, same idea as the character-panel equipment list (a
  subcategory becomes a labeled list instead of an icon grid) — bigger layout
  change than anything else in this file, would need real design thought, not a
  quick add.
- Deduplicate visually-identical items that only differ by a quality-corner tag
  (e.g. two ore types with the same icon) — concept only, no concrete mechanism
  worked out yet.
