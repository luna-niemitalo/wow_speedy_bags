# TODO — implementation plan

Ordered checklist. Items tagged `(task N)` still need their `TASKS.md` investigation
resolved first — don't build past them until that task has a recorded decision.

## Live testing findings, 2026-08-17 (partially fixed)

Reported directly by the user while testing in-game, same session as the masonry/tabs
work above.

- [x] ~~Right-click category transfer only moves the first item~~ — resolved
      2026-08-17: `Transfer.lua`'s `ns.TransferEntries` rebuilt from one synchronous
      loop into a step-driven queue (`BuildQueue`/`StepQueue`), matching Baganator's
      own real `Transfers/FromBagsToBags.lua` shape — one pickup/place pair per step,
      each step waiting a full frame (`C_Timer.After(0, ...)`) before starting the
      next, instead of assuming `PickupContainerItem` is instant and chaining every
      pair in one Lua call. Each step also re-checks the source slot
      (`C_Container.GetContainerItemInfo`) before acting, since an earlier step in the
      same transfer can shift bag contents. Untested against a live client — the
      diagnosis (confirmed against Baganator's real code) is solid, but this specific
      fix hasn't had an in-game pass yet.
- [x] ~~Category transfer leaves "ghost" items in the render~~ — resolved 2026-08-17,
      same fix as above: `Transfer.lua`'s `RescanAllModels()` calls all three models'
      `Update()` (`ns.Model`, `ns.PersonalBankModel`, `ns.WarbandBankModel`) once the
      step queue drains (or hits combat lockdown / no-space), so the view reflects
      real state instead of the stale picture the original click's `Refresh()` was
      taken from. Refreshing all three unconditionally rather than tracking exactly
      which two were involved is simpler and still correct — `Update()` is a cheap
      re-scan on an unaffected model. Untested against a live client.
- **Right-click category transfer while Personal Bank is selected tries to move items
  to Warband Bank instead.** Re-examined 2026-08-17 while fixing the two bugs above:
  by inspection, `UI.lua`'s `ns.BankView` instantiation sets BOTH bank groups'
  `transferTargetBagIDs` to `function() return ns.BAG_IDS end` (character bags, not
  the other bank) for either tab, and the tab-switch `OnClick` handler
  (`UI.lua:395-398`) calls `Refresh()` synchronously, which reassigns every pooled
  header/subcategory-label button's `.transferTargetBagIDs` field on every render —
  no stale-closure path found. Most likely this actually was a symptom of the
  now-fixed synchronous-loop bug above (state readable mid-corruption during a
  same-frame multi-`PickupContainerItem` burst), but that's inference, not a
  confirmed root cause — genuinely re-check this specifically on the next in-game
  pass before assuming the transfer-queue fix cleared it too.
- **Bank → bag single-item moves also leave a ghost in the bank view.** Still
  unfixed, still a separate question from the category-transfer ghosting above (that
  one's root cause — `Transfer.lua` never re-scanning after a move — is now fixed;
  this one is about plain drag-and-drop, which never goes through `Transfer.lua` at
  all). `SpeedyBags.lua` already routes `PLAYERBANKSLOTS_CHANGED`/
  `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED` to the matching bank model's scheduler
  unconditionally (not gated on the bank view's visibility, same as every other
  scheduler), so by inspection this *should* already self-correct — but that's
  exactly what was true of the transfer-ghosting bug too before it was traced to a
  real gap. Needs its own live-client look, not assumed fixed by inspection.
- **Masonry recomputes on every item change and it's "*massively*" slow.** Partially
  addressed 2026-08-17: `UI.lua`'s `NewBagView` now debounces `Refresh()` itself
  (`ScheduleRefresh`, a `C_Timer.NewTimer(0.1, ...)` that cancels and reschedules on
  every subsequent model change) instead of calling it directly from every model's
  `OnChanged`, so a rapid burst of model updates spread across several frames (mass
  loot/vendor/mail/unbox) collapses into one trailing render instead of one full
  masonry pack per update. This does NOT fix the deeper issue — `RenderSection`'s
  column-height loop still walks every subcategory in every section on that one
  render, not just the part that changed — that's still DESIGN.md's own stated target
  architecture ("patch only affected slots"), gated on the still-open task 3
  investigation, not something this pass rebuilt. Whether 0.1s trailing-debounce
  actually reads as responsive rather than laggy is itself untested against a live
  client — first thing to tune if the window feels sluggish to update while open.

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
      slots rendered. That row later grew Recent and Quest too (see Layout and
      Known-gaps entries below) -- same function, same shape.
- [x] ~~"Recent items" tracking~~ — resolved 2026-08-17: since `ClearNewItemGlow`
      already erases `C_NewItems`' own flag on every render, `Data.lua`'s
      `NewRecentTracker` keeps its own session-only notion of "recent" instead —
      diffs each model's own scan history (a key that's new, or whose count went
      up) rather than reading Blizzard's flag back. Timestamped with `GetTime()`,
      pruned after `RECENT_WINDOW_SECONDS` (300s), capped at `RECENT_ICON_CAP` (6),
      newest-first. A guarded "first scan establishes the baseline, doesn't flag
      anything" case was needed -- caught before shipping, not after: without it,
      the very first `Update()` (addon load) would have had no `previousCounts` to
      diff against and flagged the entire bag as Recent at once. Renders as real,
      individually-clickable item slots (`UI.lua`'s `RenderAggregateRow`,
      `ConfigureItemSlot` shared with `RenderSubcategory`) in the same row as Empty
      and Junk, keyed `"recent:"..entry.key` since the same item can legitimately
      be showing in its normal category grid at the same time (two separate
      widgets, one underlying bag slot). One self-scheduled re-`Update()` after the
      window elapses, so an item ages out of Recent even with no further bag
      activity to trigger it naturally. Untested against a live client.
- [x] ~~Quest item badge/hide~~ — resolved 2026-08-17, user request: an *inactive*
      quest item (`C_Container.GetContainerItemQuestInfo`'s `isQuestItem` true,
      `isActive` false -- nothing to Use yet) is pulled out of the normal grid into
      a collapsed aggregate badge (`Data.lua`'s `Scan`, same shape as Junk --
      `questCount`/`questItems`, capped stacked-icon display via the renamed
      `ICON_STACK_CAP`), sharing the Empty/Junk row. An *active* one (has a real
      Use action) stays a normal, fully visible entry and gets Blizzard's own
      quest-bang/border overlay for free via `btn:UpdateQuestItem(...)` -- a native
      `ContainerFrameItemButtonTemplate` method, the same call Blizzard's own
      `ContainerFrame.lua` makes, not a new texture. No addon dependency: entirely
      native API, unlike Junk/Pawn's soft integrations. Untested against a live
      client.
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
- [x] ~~Tag every non-item-slot frame with `nodeignore`~~ — resolved 2026-08-17:
      the main content frame (both bag and bank views) is `nodeignore`d, since its
      own drag-enabled backdrop would otherwise be a valid geometric nav candidate
      alongside the item slots it contains. Category headers/subcategory labels are
      plain `FontString`s (not mouse-enabled `Frame`s), so `ConsolePortNode` already
      excludes them by construction — confirmed against `TASKS.md` task 1's finding,
      no tagging needed there. The Empty aggregate slot is likewise never
      mouse-enabled, so it's excluded too; Junk stays a valid nav target on purpose
      (it's actionable — hover shows sell value).
- [x] ~~Tag item slots with `nodepriority`~~ — resolved 2026-08-17: every pooled
      item-slot button gets `nodepriority = 1` at creation (`UI.lua`'s
      `AcquireSlot`), biasing arbitrary/reopen reselection toward real items over
      other node types — not a full nav graph, just the fallback-net tagging
      invariant 5 already requires regardless of whether the graph module exists.
- [ ] Verify fallback path with ConsolePort's Navigate unpatched/absent: nav still
      resolves cleanly via geometry + the above tags alone — untested in-game yet.

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

## Currency row
- [x] ~~Currency/gold row~~ — resolved 2026-08-17, then fixed twice more same
      session: `Currency.lua` reads gold (`GetMoney()`) plus whatever the player has
      pinned via Blizzard's own "Show in Backpack" toggle
      (`C_CurrencyInfo.GetBackpackCurrencyInfo`) — no hardcoded currency list for
      most of the wishlist (Shard of Dundun's, Restored Coffer Keys, Coffer Key
      Shards, Remnants of Anguish, Field Accolades — no IDs verifiable from the
      offline reference mirrors this addon is built against, so guessing them was
      rejected in favor of Blizzard's real pinning mechanism, same approach
      Baganator's `CurrencyBlizzardTracking.lua` uses). Renders as a right-to-left
      row (`UI.lua`'s `RenderCurrencyRow`) at the **bottom** of the frame (moved
      there from an initial under-the-title placement per the user's in-game
      feedback) on both the bag view and the bank view. Real bug found by the user
      in-game: currency icons rendered as empty spots — `CreateTextureMarkup` was
      called with width/height `0, 0` instead of a real render size, fixed to
      `12, 12` with a `0.08–0.96` crop inset (Baganator's own working values for
      this same call). Superseded by a further redesign same session (below):
      per-currency icons are now real `Texture` widgets, not inline text markup, so
      they can carry a colored border.
- [x] ~~Bigger currency icons/font + per-profession color coding~~ — resolved
      2026-08-17, user feedback after the first real look ("icons are tiny AF" /
      two Moxie currencies were "the same gray icon twice" with no way to tell them
      apart without hovering): `UI.lua`'s `RenderCurrencyRow` now builds each
      non-gold currency widget from a real `Texture` (20px, up from the inline
      markup's 12px) behind a colored border square (`BORDER_THICKNESS = 3`), font
      bumped from `GameFontHighlightSmall` to `GameFontHighlight`. Border color
      comes from `Currency.lua`'s `ns.Currency.professionColor[currencyID]` — one
      thematic color per Artisan's Moxie profession (potion green for Alchemy,
      forge red-orange for Blacksmithing, etc.), defined in the same
      `PROFESSION_MOXIE` table that drives the profession auto-pin, so the
      skillLine/currencyID/color mapping has one source, not two tables that could
      drift. Currencies with no mapped color get a neutral gray border rather than
      no border. Gold keeps Blizzard's own multi-denomination coin markup — not a
      per-profession currency, nothing to disambiguate.
- [x] ~~Artisan's Moxie profession auto-pin~~ — resolved 2026-08-17: the user
      supplied real currency IDs (Alchemist's 3256, Scribe's/Inscription's 3261)
      and the rest were looked up (Wowhead currency pages) once the
      3256–3266-alphabetical-by-profession pattern was confirmed against those two
      known points. `Currency.lua`'s `AutoPinProfessionMoxie` maps
      `C_TradeSkillUI.GetAllProfessionTradeSkillLines()`'s locale-independent
      skillLine IDs to the matching Moxie currency and pins it via
      `C_CurrencyInfo.SetCurrencyBackpackByID` — additive/idempotent, runs on
      `PLAYER_LOGIN`/`SKILL_LINES_CHANGED`. The other five named currencies still
      have no verified IDs and are not auto-pinned. Untested against a live client.

## Bank UI
- [x] ~~Bank view mirroring the bag view~~ — resolved 2026-08-17: `UI.lua`'s
      `NewBagView` factory now builds both the bag view and a bank view from the
      same rendering machinery (categorization, junk aggregate, currency row) —
      one factory, not a copy-pasted second file. `Bank.lua`'s
      `ns.GetBankBagIDs()` drives it off `C_Bank.FetchPurchasedBankTabIDs` for
      both `Enum.BankType.Account` (warband bank, listed first per the user's
      "default to warband bank" direction) and `Enum.BankType.Character`.
      `GetBankBagIDs` itself never reads state back off the `BankFrame`/
      `BankPanel` globals, sidestepping the taint hazard `DESIGN.md` documented.
      Opens/closes on `BANKFRAME_OPENED`/`BANKFRAME_CLOSED`. Reagent Bank needs no
      separate handling — the modern client folded it into regular character-bank
      tabs, no
      distinct `BagIndex` for it anymore. Untested against a live client.
- [x] ~~Suppress Blizzard's default bank window~~ — resolved 2026-08-17, per the
      user's explicit direction to check how Baganator does it: `Bank.lua`'s
      `HideDefaultBank` reparents `BankFrame` onto a hidden frame and clears its
      `OnHide`/`OnEvent`/`OnShow` scripts at load, matching Baganator's own real,
      shipped `ViewManagement/Initialize.lua` exactly (`SetParent(hidden)` +
      clearing those three scripts, called unconditionally at addon init). This
      corrects this file's earlier, more cautious stance (based on
      `references/BetterBags/.context/patterns-taint.md`, read as broader than what
      actually causes trouble) — a widely-used addon doing this in production with
      no reported taint fallout is stronger evidence than the earlier unverified
      caution. `GetBankBagIDs` still never *reads* state back off `BankFrame`/
      `BankPanel` (the part of the taint note that's still true —
      `BankFrame:GetActiveBankType()`-style reads from a tainted chain), so this
      addition is additive, not a reversal of that part. Not independently verified
      in-game by us yet.

## Layout: scrolling, dynamic columns, subcategory ordering
- [x] ~~Bank view overflowing the screen~~ — resolved 2026-08-17, user report (with
      screenshot -- five full-width subcategory blocks spilling past the frame
      edge, no way to see the rest): `UI.lua`'s `NewBagView` now wraps everything
      below the title in a real `ScrollFrame` (`UIPanelScrollFrameTemplate` --
      Blizzard's soft-deprecated-in-favor-of-ScrollBox but still-shipped scroll
      widget; kept anyway since ScrollBox's element-virtualization is built for a
      uniform list of rows, not this frame's mixed-height flow layout) over a
      `content` child frame everything actually renders into. The outer frame
      still sizes snugly to its natural content height when everything fits (same
      "no wasted space" as before), now clamped at `MAX_VIEW_HEIGHT` (640) instead
      of growing without bound -- content beyond that scrolls.
      `scrollFrame.scrollBarHideable = true` hides the slider entirely when
      there's nothing to scroll, so the bag view (which usually fits) doesn't grow
      a permanently-disabled scrollbar.
- [x] ~~Currency row swallowed by the scroll/dynamic layout~~ — resolved 2026-08-17,
      user correction mid-implementation: the currency row is deliberately NOT
      part of the scrolled `content` ("it's more of a part of the frame than an
      actual element") -- it stays parented directly to the outer `frame`,
      anchored fixed to `frame`'s `BOTTOMLEFT`, with the scrollFrame's own bottom
      anchor pulled up to leave room for it. Gold/currency stays visible
      regardless of scroll position.
- [x] ~~Fixed subcategory columns wasting horizontal space~~ — resolved 2026-08-17,
      user report (screenshot: "Parts"/"Optional Reagents" with only a handful of
      items still reserving a full 4-wide block's worth of space, crowding out how
      many blocks fit per row): `UI.lua`'s `SubcatCols(entries)` caps a block's
      column count at `min(SUBCAT_COLS, #entries)` instead of always using the
      max -- a block only takes as much width as it actually needs.
      `RenderSubcategory`/`RenderSection` were reworked to compute and use each
      block's own width for wrapping instead of a single constant `SUBCAT_WIDTH`.
- [x] ~~Alphabetical subcategory ordering~~ — resolved 2026-08-17, user request
      ("reasonable ordering / category compressing instead of alphabetical"):
      `UI.lua`'s `OrderedSubcats` sorts by entry count descending (ties broken
      alphabetically for a stable order), rather than pure alphabetical. Also
      happens to pack better now that blocks are dynamically sized -- placing the
      widest blocks first means the smaller ones that follow are the ones filling
      whatever space is left in a row.

## Bank split, transfer, deposit button
- [x] ~~Warband/Personal empty-slot counts wrongly combined~~ — resolved
      2026-08-17, user report: `Bank.lua`'s single merged `ns.BankModel` (one
      `Scan` over both banks' bag IDs) meant "N empty slots" silently added
      warband space (shared across every character on the account) to
      personal space (not accessible to any of them) into one misleading
      number. Fixed by splitting into two real, independent models
      (`ns.PersonalBankModel`/`ns.WarbandBankModel`, both still
      `ns.NewModel(getBagIDs)` instances -- no change needed to Data.lua's
      generic `Scan`/`NewModel` at all) rather than teaching `Scan` a second
      grouping axis it never needed before.
- [x] ~~Bank view merging Personal/Warband into one set of sections~~ —
      resolved 2026-08-17, same user report, same fix: `UI.lua`'s
      `NewBagView` now renders one or more `opts.groups`, each with its own
      complete section/subcategory breakdown and its own super-header
      ("Warband Bank" / "Personal Bank") -- the bag view has exactly one,
      unlabeled group (no behavior change there). Every pooled widget key
      is namespaced by `groupKey` so two groups' same-named sections (both
      banks have an "Equipment" section) get separate widgets.
- [x] ~~Right-click category/subcategory to transfer items~~ — resolved
      2026-08-17, user request ("categories *and* subcategories should be
      right clickable to transfer all of the items from that category"):
      new `Transfer.lua`'s `ns.TransferEntries(entries, targetBagIDs)` does
      the actual move -- `C_Container.PickupContainerItem` pickup-then-place
      pairs, verified safe against Baganator's own real, shipped
      `Transfers/FromBagsToBags.lua` (same pair, `PickupContainerItem` is
      NOT itself protected, only `UseContainerItem` is -- see DESIGN.md).
      Section headers (`AcquireHeaderButton`) now register both
      `LeftButtonUp`/`RightButtonUp`: left toggles collapse (unchanged),
      right transfers every entry in that section. Subcategory labels
      switched from a bare `FontString` (`AcquireLabel`) to a real `Button`
      (`AcquireSubcatLabelButton`), since a FontString can't receive
      clicks at all -- right-click transfers just that block's entries.
      Direction is always "the other view": bag view's groups target
      `ns.GetWarbandBankBagIDs` (default bank, matching the existing
      "warband bank listed first" precedent -- only actually succeeds
      while at a banker, a real Blizzard restriction, not enforced by this
      addon itself), both bank groups target `ns.BAG_IDS`. Guarded on
      `InCombatLockdown()`, matching Baganator's own transfer code.
      Untested against a live client -- the riskiest untested piece of this
      whole pass, given it's the one that actually moves items.
- [x] ~~"Deposit Reagents" button lost when the default bank frame was
      suppressed~~ — resolved 2026-08-17, user request: `Bank.lua`'s
      `ns.DepositReagents()` calls the modern equivalent,
      `C_Bank.AutoDepositItemsIntoBank(bankType)`, against both bank types
      (whichever one actually has a reagent-flagged tab configured; each
      call is a no-op on the other) -- the old standalone Reagent Bank
      button doesn't exist anymore now that it's folded into regular tabs.
      Rendered as a real `UIPanelButtonTemplate` button, bottom-left of the
      bank frame (mirroring the currency row's bottom-right), bank-view-only
      (`opts.depositButton`).
- [x] ~~Bank currency row showing currencies a bank can't hold~~ — resolved
      2026-08-17, user's own reasoning ("the bank should not have
      currencies other than what the warband or personal bank has
      independently, the banks can not store other types of currencies"):
      the bank view's currency row (`opts.currencyMode = "warbandGoldOnly"`)
      now shows only Warband Bank's own deposited-gold balance
      (`Bank.lua`'s `ns.GetWarbandBankGold`, `C_Bank.FetchDepositedMoney`) --
      a real, separate pool from the player's own `GetMoney()`. Personal
      bank gets nothing shown (it has no currency store of its own -- it's
      just character gold, already on the bag view's row), and none of
      `Currency.lua`'s pinned currencies (Artisan's Mettle, Delve
      currencies) render here at all, since they're not bank content.
      Refreshed on a new `ACCOUNT_MONEY` event (`SpeedyBags.lua`) -- separate
      from `PLAYER_MONEY`, which only covers the character's own gold.

## Masonry layout
- [x] ~~Row-then-wrap left small categories stranded on a mostly-empty new
      row~~ — resolved 2026-08-17, user report with a diagram (a full row of
      small Crafting subcategories -- Enchanting, Finishing Reagents, Parts,
      Cooking, Optional Reagents -- would have fit in the leftover space
      below a shorter column from the row above, instead of forcing an
      entire new row): `UI.lua`'s `RenderSection` replaced left-to-right
      row-wrapping with real masonry -- `SECTION_COLUMNS` (5) fixed-position
      column slots, each with its own running height; every subcategory
      block (still densest-first via `OrderedSubcats`) goes into whichever
      column currently has the least content, not the next slot in reading
      order. Column x-positions are fixed-width (`SUBCAT_WIDTH`); a
      narrower block (`SubcatCols`) still only takes its own width within
      that slot, left-aligned -- the "5 columns" stayed, only the packing
      itself changed. Deliberately NOT also implemented: the user's
      follow-on idea of precomputing Warband's layout once globally and
      each character's once per-character, only reflowing on window close
      instead of live on every model update -- that's a real, separate
      architectural question (this project's own still-open task 3: what
      triggers a re-render, at what granularity) rather than something the
      packing algorithm itself needs, and masonry recompute at these bag
      sizes (a few hundred items at most) hasn't been shown to actually
      cost anything yet. Untested against a live client.
- [x] ~~"Deposit Reagents" target unclear~~ — resolved 2026-08-17, user
      question ("which bank does the 'deposit reagents' button deposit them
      to?"): the honest answer is genuinely both (whichever bank type
      actually has a reagent-flagged tab picks the items up, the other call
      is a no-op) -- added a tooltip to the button saying so outright
      instead of leaving it ambiguous, rather than trying to guess/restrict
      to one bank type.

## Real bank tabs, snappy-open, deposit-target fix
- [x] ~~Stacked Personal/Warband groups weren't real tabs~~ — resolved
      2026-08-17, user correction ("this is why i wanted personal bank and
      warband bank as separate tabs" / "I want them to go to the bank that
      is selected"): `UI.lua`'s `NewBagView` now shows exactly one group at
      a time behind real switchable tab buttons (bottom of the frame, above
      the currency/deposit row -- user's own placement preference,
      "traditionally below the frame ... below even the currency frame"),
      not both banks' content stacked simultaneously. Selection persists per
      view via `SpeedyBagsDB.selectedGroup`. This also resolved the
      Deposit Reagents ambiguity for free: the button now targets
      `SelectedGroup().bankType` specifically (`Bank.lua`'s
      `ns.DepositReagents(bankType)`, no longer tries both banks
      unconditionally) since the user has a reagent-flagged tab on both
      banks, making "whichever one has it" a genuinely ambiguous answer,
      not just an apparently ambiguous one.
- [x] ~~Opening the window forced a full re-scan every time~~ — resolved
      2026-08-17, user correction: this addon's own founding complaint
      (`DESIGN.md`'s Purpose section) is that every other bag addon is slow
      to open; forcing `model.Update()` (a full container/quest/item
      re-scan) on every single `view.Show()` reproduced exactly that. Fixed
      by decoupling the *scan* from window visibility entirely
      (`SpeedyBags.lua`'s `MakeScheduler` no longer gates on
      `frame:IsShown()`) so it runs continuously in the background,
      spread across the many individual `BAG_UPDATE`-family events that
      already fire during normal play/login, the same way `Currency.lua`
      already always has -- by the time the player opens the window,
      `model.entries` is already current, so `Show()` only pays for one
      render pass (`Refresh()`), not a scan AND a render. The deeper
      version of this -- `Refresh()`'s own masonry/layout pass still runs
      as one synchronous call, not diffed or spread across frames, which
      matters because WoW's client is single-threaded and synchronous Lua
      work sits directly in the render-thread path -- is DESIGN.md's own
      already-stated target architecture ("Render layer: subscribes to
      data-layer diffs, patches only affected slots") and remains
      genuinely gated on the task-3 investigation this project has never
      done. Not "no evidence it's slow" (a framing this file briefly used
      and the user corrected) -- the real reason is architectural
      (never block the render thread by default), not a measured cost.

## Live in-game testing fixes
- [x] ~~Both bank tabs showed empty on first open~~ — resolved 2026-08-17,
      user report while testing live: the scan/render decoupling above
      wrongly assumed background events pre-warm every model the way
      `BAG_UPDATE` always does for bags -- but bank contents genuinely
      aren't available before `BANKFRAME_OPENED` fires (no equivalent
      event exists to pre-warm bank data from elsewhere in the world).
      `SpeedyBags.lua`'s `BANKFRAME_OPENED` handler now explicitly calls
      both bank models' `Update()` before `ns.BankView.Show()` -- once per
      actual bank visit, not once per SpeedyBags-window toggle, so this
      isn't a regression back to the "recompute on every open" cost that
      fix was for.
- [x] ~~Tabs/Deposit Reagents/currency on separate rows~~ — resolved
      2026-08-17, user request ("put the buttons on the same row as the
      currency"): all three now share the bottom row -- tabs left-anchored,
      Deposit Reagents right after them, currency display right-anchored
      as before. Confirmed there's real room (tabs+button ~430px, currency
      ~170px, against an ~880px-wide frame).

## Category headers
- [x] ~~Collapsible section headers~~ — resolved 2026-08-17: section headers
      (`UI.lua`'s `AcquireHeaderButton`) are now real `Button`s with a click
      handler toggling `SpeedyBagsDB.collapsedSections[sectionName]` and
      re-`Refresh()`ing; a collapsed section still shows its header (so it can be
      re-expanded) but renders none of its subcategory blocks. Shared between the
      bag view and the bank view (same SavedVariables key). Being clickable/
      mouse-enabled makes these exactly the case `TASKS.md` task 1 flagged
      `nodeignore` as load-bearing for — plain `FontString` labels are excluded
      from ConsolePort's candidate scan automatically, but a real `Button` is not,
      so `AcquireHeaderButton` sets `nodeignore` explicitly. Untested against a
      live client.

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
