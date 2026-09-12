# DESIGN.md — SpeedyBags

## Purpose

A WoW bag/bank addon built around two things every existing addon gets wrong for
controller play: a nav graph that actually matches how a gamepad cursor should move,
and bag updates that never block the rest of the UI or yank the cursor around.

## Problem statement

Every addon in `references/` (AdiBags, Baganator, BagBrother, Bagnon, BetterBags)
lays out category headers and item slots in the same grid, and lets ConsolePort (or
native gamepad nav) infer traversal order from that layout. The result: pressing
up/down from an item slot can land on a category title, which is not a usable nav
target (nothing happens when you confirm on it) and breaks the "just move to the
adjacent slot" expectation. Category titles, when they need to be reachable at all,
belong on a deliberately separate axis — e.g. hard-right instead of up/down/left/right
into the grid — so item-to-item movement is never interrupted by a non-item node.

Separately, every action that opens/loots/sells/unpacks multiple things in sequence
(loot window, mailbox, vendor sell, container-opening, Knowledge Point parchments)
tends to either move the gamepad cursor to whatever slot the result landed in, or to
the first empty slot, or to require a full bag-frame rebuild that blocks input to the
rest of the UI while it happens. Reference points for the pattern we want instead:
Artisan's Mettle bags and loot-chest-style "open all of these without the cursor ever
leaving the stack" behavior already used elsewhere in the game.

## Hard constraints (invariants)

These are non-negotiable design invariants, not implementation details. If a chosen
approach can't satisfy one, the approach is wrong, not the invariant.

1. **Category headers are never primary-grid nav targets.** Up/down/left/right from
   an item slot must only ever land on another item slot (or nothing, at a grid
   edge). Category-level navigation, if it exists, lives on its own explicit axis.
2. **Cursor focus never moves as a side effect of an action.** Opening, looting,
   selling, or using an item/stack must leave the gamepad cursor on the slot/stack
   the player acted on — not on the result, not on the next empty slot, not
   anywhere else — for as long as that stack still exists to act on again.
3. **Junk is one slot, not N slots.** Items flagged vendor-trash are never rendered
   as individual grid slots. They're aggregated into exactly one "Junk" slot that
   shows a count/space-consumed indicator.
4. **Bulk operations never block the rest of the UI.** Looting a stack, opening
   mail, selling to a vendor, or unboxing containers must not freeze or lock out
   interaction with other frames while bag state updates. This implies an
   event/incremental update model rather than a full synchronous rebuild per
   `BAG_UPDATE`-family event — confirm via investigation (see `TASKS.md`), don't
   assume the mechanism yet.
5. **Nav order is a hand-authored graph by default; geometric inference is the
   resilience fallback, never the primary path.** Decided 2026-08-16 (`TASKS.md`
   task 1). ConsolePort's own nav engine (`ConsolePortNode`,
   `references/ConsolePortNode/`) has no registerable adjacency graph — it's pure
   geometric candidate search (angle+distance from the cursor's live on-screen
   position) via `Cursor:Navigate` in
   `ConsolePort_Cursor/View/Cursor.lua`. We override that: a companion module
   monkey-patches `Cursor:Navigate` (a single, already-confirmed choke point every
   D-pad press funnels through — see `TASKS.md` task 1) to consult a hand-authored
   `graph[node][direction] = target` lookup first; a hand-authored edge is faster to
   traverse and predictable in a way a live geometric rescan can never be, so it's
   the default, not an optimization layered on top of geometry.
   **Every fallback layer must still resolve cleanly on its own**, because the patch
   can fail for reasons outside our control (ConsolePort not installed, a
   ConsolePort update changes `Cursor:Navigate`'s shape so the patch doesn't apply,
   or a specific node/direction simply has no authored edge yet): no graph edge for
   a given (node, direction) falls through to ConsolePortNode's geometric scan for
   that one lookup; the patch failing to apply at all must leave ConsolePort running
   exactly as it does unpatched. That fallback path only resolves *correctly* if
   invariant 1's `nodeignore`/`nodepriority` tagging discipline is still applied to
   every frame regardless — the graph doesn't replace that discipline, it sits in
   front of it.
   **Correction, 2026-09-12** (user report: "the console port ui cursor still
   doesn't register the menu as a valid target to navigate to/from" — confirmed by
   investigation, see `TASKS.md` task 1's addendum): `nodeignore`/`nodepriority`
   tagging, and the future nav graph, are both moot for a frame ConsolePort never
   scans in the first place. There is a *gate* in front of ConsolePortNode's
   geometric search that invariant 1's original resolution missed entirely — ADDING
   `SpeedyBagsFrame`/`SpeedyBagsBankFrame` to ConsolePort's cursor-navigable frame
   stack (`ConsolePort:AddInterfaceCursorFrame`, see `TASKS.md` task 1) is a
   **prerequisite** for invariant 1 and 5 to have any effect at all, not an
   orthogonal nice-to-have.
6. **Layout position is identity-keyed and frozen between sorts; nothing already
   on screen moves while a view is open.** Added 2026-09-12, user-directed hard constraint
   ("no layout reflows while the bag is open, ever, under any conditions"), refined
   the same day into a precise, two-part mechanism once the user answered the
   masonry-tension question below:
   - **Exactly two triggers ever cause a reflow, both a deliberate "re-sort now"
     action, never a side effect of ordinary play**: the view being closed (the
     sort runs at close time, not on the next open — opening must stay instant,
     and this is also what makes an item that appears while the view is closed
     land in New Items rather than getting sorted: nothing sorts again until the
     *next* close), and a manual "Sort" button clicked while it's still open. No
     event, timer, or count change reflows anything on its own, and opening the
     view never itself triggers a sort.
   - **A category/subcategory position, and an item's grid cell within it, are
     identity-keyed and sticky for the duration of ONE open session** — "if an
     item has a slot, that location is reserved for it" (user's own framing),
     literally: the reservation survives the item's count dropping to zero (an
     empty, still-reserved cell, not backfilled by reflowing a neighbor into the
     gap) and applies again the moment a matching item (same identity) is
     reacquired, even mid-session — "if I use the last item from a specific
     spot, and then ... acquire a new item of matching material, that should
     automatically fall into that slot even if the slot is technically empty."
     **Correction, same day**: this stickiness is bounded by the next sort, not
     permanent — the user asked directly whether a dead reservation (an item no
     longer owned at all) ever gets reclaimed, and the honest answer was no, it
     sat there until `/reload`. Since a sort is already one of the only two
     allowed reflow points, it's also the right point to compact: every sort
     recomputes each touched subcategory's membership from what's actually
     owned right now, dropping reservations for anything no longer present and
     compacting the rest down, rather than only ever appending. A subcategory
     that becomes completely empty stops reserving a column/header at all. The
     mid-session promise above still holds exactly as stated — it just means
     "until the next sort," not "forever."
   - **An item with no existing reservation is not placed into its category grid
     at all** — it lands in the New Items area instead, and stays there until one
     of the two triggers above runs a real sort. This is what keeps the "no
     reflow while open" promise honest: a genuinely new item can't reflow its
     category into a new shape if it never enters that category's grid before the
     next real sort.
   - **The New Items area is the one place still allowed to reflow on its own**,
     because it's explicitly a bounded staging area, not a semantic category —
     when it runs out of room it may repack/wrap/shrink internally to fit more,
     independent of the two triggers above.
   - **A sort should not treat every subcategory as equally movable** — "larger
     objects / larger categories like crafting materials should be more reluctant
     against being moved by reflow": the sort algorithm biases toward keeping a
     large/dense subcategory's previous column, only displacing it when the
     imbalance is large enough to be worth it, while small subcategories flow
     freely to fill whatever's left. A full from-scratch masonry pack (ignoring
     the previous layout entirely, as `UI.lua` does today) doesn't have this
     property — it needs the previous assignment as an input, not just current
     entry counts. Exact weighting is a tuning knob, not decided here.

   This resolves the tension with the masonry-by-live-size packing added
   2026-08-17 (`UI.lua`'s `RenderSection`/`SubcatCols`/`OrderedSubcats`, which
   recomputes on every model change, not just on a deliberate sort): masonry's
   packing algorithm itself is still useful, just relocated — it now runs only at
   the two sort triggers, seeded by the previous layout (for the size-weighted
   stickiness above) rather than from a blank slate every render. See `TASKS.md`
   task 7 for the full mechanism (reservation table, New Items staging, Sort
   button, size-weighted resort).

## Target architecture (sketch — not yet built)

- **Data layer**: bag/bank/currency/knowledge-point state, updated incrementally from
  Blizzard events, decoupled from the rendering layer. Exact event set and update
  granularity: investigation task, see `TASKS.md`.
- **Junk classification**: a single boundary where "is this vendor trash" is decided
  once per item (sell price + item type heuristics, +/- explicit user overrides),
  feeding the aggregate Junk slot. One field, one check, one destination — no
  scattering the junk decision across render code.
- **Nav graph layer (primary)**: a `SpeedyBags`-owned `graph[node][direction] =
  target` table, built alongside slot layout, consulted by a monkey-patched
  `Cursor:Navigate` (see invariant 5) before ConsolePort's own geometric scan ever
  runs. This is the actual nav mechanism for normal operation — hand-authored, not
  inferred.
- **Nav eligibility layer (fallback safety net)**: a construction-time step every
  non-item-slot frame goes through regardless of whether the graph patch is active —
  `SetAttribute('nodeignore', true)` for category headers and anything else that
  shouldn't be a directional-nav target, `nodepriority` on item slots for
  reselection bias — applied uniformly by the render layer, not left to per-widget
  discretion. This is what makes invariant 1 and invariant 5 enforceable rather than
  aspirational, against `ConsolePortNode`'s actual (geometric, not graph-based)
  mechanism — see invariant 5 and `TASKS.md` task 1.
- **Render layer**: subscribes to data-layer diffs, patches only affected slots.
  Never a full-frame rebuild in the hot path (loot/vendor/mail/unbox).
- **Layout-position layer**: an identity-keyed slot-reservation table
  (section/subcategory → column, item key → grid index within its subcategory),
  written only by an explicit sort pass (at view-**close** time, or a manual
  "Sort" button while open — never on open, which must stay instant) and
  otherwise read-only — an item with no reservation renders in the New Items
  staging area instead of its category, until the next sort. See
  invariant 6 and `TASKS.md` task 7. Sits between the data layer and the render
  layer: the render layer still repaints a slot's texture/count/tooltip on every
  relevant change, but never re-derives *where* a slot sits outside a sort pass.
  Not yet built — masonry-by-live-size (`UI.lua`'s current `RenderSection`, which
  repacks on every model change) is what's actually shipped, and it violates
  invariant 6.
- **ConsolePort frame registration**: every top-level SpeedyBags frame calls
  `ConsolePort:AddInterfaceCursorFrame(frame)` (existence-guarded — soft
  integration, same pattern as `Junk.lua`/`Pawn.lua`) at creation, so ConsolePort's
  cursor stack ever considers its children as nav candidates at all — see
  invariant 5's 2026-09-12 correction and `TASKS.md` task 1. Not yet built.

## Rejected / deferred alternatives

- **Ace3 (AceAddon/AceEvent/AceGUI/...)** — used by BetterBags and vendored in most of
  the references. Deferred, not rejected outright: pulling in Ace3 for event
  dispatch is plausible, but AceGUI-style widget frameworks tend to encourage
  positional/implicit layout, which cuts against invariant 5. Decision needs the
  framework-evaluation task in `TASKS.md` before committing either way — don't adopt
  it by default just because every reference addon does.
- **Copying any reference addon's nav/update code directly** — rejected. The whole
  point of this project is that the reference set's nav and update behavior is the
  problem being solved, not a base to build on. See `references/README.md`.

## External addon integration — scope of "no external dependencies"

Clarified 2026-08-16, because the distinction matters and got conflated once
already: "no external dependencies" (CLAUDE.md § Status, TASKS.md task 6) means no
other **bag addon** and no **Syndicator** — the things this project exists to do
differently, where depending on one would mean inheriting the exact accretion
problem the project is trying to avoid (see CLAUDE.md § Purpose). It is not a
blanket rule against any addon integration.

Complementary QoL addons doing something genuinely different — Leatrix_Plus's junk
vendoring, Pawn's upgrade advisor, Scrappy's scrapping, and similarly-scoped tools —
are explicitly fine to work *with*, not just read for reference. The pattern,
established by `Junk.lua` and repeated by `Pawn.lua`: integrate with the other
addon's own real, documented mechanism — `Junk.lua` reads Leatrix_Plus's
SavedVariables global directly (`_G.LeaPlusDB`, verified against its real source on
the live client, not a `references/` clone, since this is a runtime dependency, not
something to study once and reimplement); `Pawn.lua` uses Pawn's own first-party
third-party-bag API (`PawnRegisterThirdPartyBag`/`PawnShouldItemLinkHaveUpgradeArrow`
— Pawn's own source literally documents this contract for bag-addon authors, so
there was nothing to reverse-engineer). Both are **soft, optional** integrations —
always nil/existence-checked, always degrade gracefully (no junk-quality-only
fallback in `Junk.lua`'s case; simply no upgrade arrows in `Pawn.lua`'s) when the
other addon isn't installed or loaded. Never a hard `## Dependencies:` requirement;
`## OptionalDeps:` in the `.toc` only, so the addon loader gets load order right when
both happen to be present, without making either mandatory.

## Status

- **Current**: see `CLAUDE.md` § Status for the up-to-date picture — a working
  categorized bag UI with a real junk slot and Pawn upgrade-advisor integration
  exists. Nav graph and cursor stability from the invariants above are not built yet.
- **Target**: see architecture sketch above. Nav graph (invariant 5) is blocked on
  `TASKS.md` tasks 1/2.

## Default-UI suppression must be structural, not a global-function hook

**Found 2026-09-12** (user report: Blizzard's own bag UI still opens in some
situations — the Item Upgrade view specifically — "and is impossible to close
without reloading the UI"), confirmed by reading real client source
(`references/wow-ui-source/`): `SpeedyBags.lua`'s redefinition of
`ToggleBackpack`/`ToggleAllBags`/`ToggleBag`/`OpenAllBags`/`CloseAllBags` only
intercepts code that calls exactly those five globals. It is not the only way
Blizzard's own UI opens the real bag frame:

- `Blizzard_ItemUpgradeUI/Mainline/Blizzard_ItemUpgradeUI.lua` calls
  `ItemButtonUtil.OpenAndFilterBags`/`CloseFilteredBags`
  (`Blizzard_FrameXMLUtil/ItemUtil.lua`), which calls
  `OpenAllBagsMatchingContext` (`Blizzard_UIPanels_Game/.../ContainerFrame.lua`),
  which calls the raw internal `OpenBag(i)` directly — none of our five
  redefined globals are in that call chain, so the real
  `ContainerFrameCombinedBags`/`ContainerFrame1..6` opens unsuppressed.
- Once open that way, it can't be closed through our UI either:
  `CloseFilteredBags` (and Escape, via `UIParentPanelManager`'s
  `CloseAllWindows` → the global `CloseAllBags()`) both route through the same
  global `CloseAllBags` we redefined to only hide `ns.Frame` — Blizzard's real
  frame is left showing with nothing left in the chain able to hide it.
  `ContainerFrameCombinedBags`/`ContainerFrame1..6` are also not in
  `UISpecialFrames`, so there's no independent Escape-to-close fallback either.
  (Separately, `Blizzard_ItemInteractionUI` — the Catalyst-style flow — calls
  the global `OpenAllBags`/`CloseAllBags` directly and IS correctly intercepted
  today; the Item Upgrade UI's `OpenBag`-based path is the one that isn't.)

**The lesson generalizes past this one call site**: global-function redefinition
is a compatibility shim for the *common* entry points, not a suppression
mechanism — anything with its own more direct path to the real frame walks
straight past it. `Bank.lua`'s `HideDefaultBank` (below) already uses the
correct, general technique for the bank frame — structural suppression
(`SetParent` onto a hidden frame, scripts cleared) — precisely because it
doesn't care which code path tried to show the frame. The regular bag frame
never got the same treatment; that's the actual gap, not a missing hook for
this one specific Item Upgrade call site. Confirmed against Baganator/BetterBags'
own real, shipped code: both suppress `ContainerFrameCombinedBags`/
`ContainerFrame1..6` structurally, the identical way they (and we) already
suppress `BankFrame` — BetterBags additionally special-cases
`Enum.PlayerInteractionType.ItemUpgrade` in its own interaction-event table,
confirming this is a known, real-world trigger other addons had to handle too,
not an edge case unique to us.

**Fix** (not yet implemented — see `TASKS.md` task 8): a `HideDefaultBags()` in
`SpeedyBags.lua` mirroring `Bank.lua`'s `HideDefaultBank()` exactly — reparent
`ContainerFrame1..6` and `ContainerFrameCombinedBags` onto a hidden frame and
clear their `OnShow`/`OnHide`/`OnEvent` scripts at load. This closes the gap for
every current and future code path, not just the one that was actually caught.
Separately (a real but related gap, not the same bug): `SpeedyBagsFrame` and
`SpeedyBagsBankFrame` are not registered in `UISpecialFrames` either, so Escape
does not close *our own* frames independently of the `CloseAllBags`-global
compatibility shim — should be added alongside the structural suppression fix.

## Transfer verification (ghost-item reconciliation)

**Added 2026-09-12** (user report: multi-item bag→bank transfers "often" leave
ghost items behind — a persistence beyond what the earlier single trailing
`RescanAllModels()` fix in `Transfer.lua` catches). Full design in `TASKS.md`
task 10; the shape of it as an invariant:

- **Every move `Transfer.lua` initiates is verified against a per-item
  assertion** ("item X is gone from the source, present in the destination"),
  not just re-rendered from whatever the model happens to show afterward. The
  assertion is identity-scoped — a GUID for equipment, an itemID + expected
  count-delta for stackables (see task 10's open question on why stackables
  can't always use a bare GUID) — never a loose "does this itemID exist
  somewhere in the target bags now" check, which can't distinguish the item
  actually moved from an unrelated existing stack.
- **Verification retries the specific stuck item, not the whole batch.** A
  fast (~300ms) poll loop runs only while at least one item's move is
  unconfirmed, re-attempts a failed pickup/place up to a small capped number
  of times, and forces a real model rescan (not just a render) before
  concluding an item is missing or duplicated — most "ghost" sightings are
  exactly that: a stale cached model, not a real duplicate or a real loss.
- **A slow (~5s) background pass keeps the rest of inventory state honest
  independent of events**, on the working assumption that a missed/unexpected
  event (not a flaw in `Data.lua`'s `Scan` itself, which is already correct
  when it runs) is the actual root cause of ghosts that don't go through
  `Transfer.lua` at all (plain drag-and-drop). This is deliberately not
  real-time and never touches the render path — see invariant 4, which this
  strengthens rather than replaces: bulk operations already must not block the
  UI; this adds "and must eventually be provably correct," on a background
  cadence, not a synchronous one.
- **Correction, same day**: the two mechanisms above only verify real game
  state against `model.entries` (the data layer) — a ghost is a *rendered*
  phenomenon, and neither one checks that the actually-visible widget set
  agrees with `model.entries` (the render layer). A third piece closes that:
  every forced data update also forces its view's `Refresh()` rather than
  trusting the existing debounce to fire, and `Refresh()` itself gains a
  standing self-check (its own hide-unused-widgets pass gets audited against
  what it just computed as "should be visible," every render, not just during
  active verification) — printing and correcting any mismatch, per
  `~/.claude/CLAUDE.md`'s foreign-data discipline of always stating expected
  vs. actual on failure, rather than trusting a render-layer invariant that's
  already been proven wrong once. Without this piece, a render-layer bug
  entirely unrelated to data staleness would never be caught no matter how
  often the data layer is re-verified.

Not yet implemented — recorded here as the target invariant, with the
mechanism itself in `TASKS.md` task 10.

## Boundaries

- WoW client Lua API (all of it — game state, item data, container contents) is the
  external boundary. Foreign-data handling policy from `~/.claude/CLAUDE.md` applies:
  validate at the boundary, interior trusts its inputs.
- SavedVariables (junk overrides, user config) is the other boundary — anything read
  back from a SavedVariables table crossed a session boundary and should be validated
  before use, same as any other foreign data.

## Protected functions (taint)

A real, permanent platform constraint, not a bug class we'll eventually eliminate —
record findings here as they accumulate, since every feature that acts on an item
(use, sell, mail, socket, equip) will hit some version of this.

**The rule, corrected 2026-08-16 after a real in-game repro** (initial diagnosis was
wrong — see below): `C_Container.UseContainerItem` is **unconditionally protected**
— per warcraft.wiki.gg, "can only be called from secure code," full stop, combat or
not. `PickupContainerItem` is *not* protected at all (freely callable from anywhere,
confirmed by absence from Warcraft Wiki's restricted-function notes and by it working
fine in our own addon before this fix). The first diagnosis here guessed
`UseContainerItem` was combat-gated like `C_Container.SortBags` actually is, and
shipped an `InCombatLockdown()` guard — that guard was real but insufficient: the
user hit `ADDON_ACTION_FORBIDDEN` on `UseContainerItem` *out of combat, in town*,
which the guard doesn't touch at all. Lesson: "protected" isn't one rule with one
shape — check the specific function, don't pattern-match from a different one.

Blizzard's own `ContainerFrame` calls `UseContainerItem` from a plain `OnClick`
(`ContainerFrameItemButtonMixin:OnClick`,
`references/wow-client-source/.../ContainerFrame.lua:1489`) with no special wrapper
— that works because the function *body* handling the click is Blizzard's own code
(untainted), not because of combat state. Identical code in `SpeedyBags/UI.lua` is
addon code and can never call it, regardless of combat.

**Fix**: `UI.lua`'s slot buttons now inherit Blizzard's real
`ContainerFrameItemButtonTemplate` (`CreateFrame("ItemButton", name, parent,
"ContainerFrameItemButtonTemplate")`) instead of a plain `Button` with our own
`OnClick`. The click then executes as Blizzard's own `ContainerFrameItemButtonMixin:OnClick`
— untainted, so both `UseContainerItem` and `PickupContainerItem` work normally, in
and out of combat. **This was rejected earlier in this same investigation** on the
assumption that the template requires implementing a chunk of
`BaseContainerFrameMixin` on the parent frame (`self:GetParent():IsCombinedBagContainer()`
etc., per `ContainerFrame.lua:502,651,746,784,804,920,971`). Re-checked line by line:
that call only happens inside the template's *optional* `:Initialize(bag, slot)`
convenience method — its actual `OnLoad` (line 1473) and `OnClick` (line 1489) path
touch nothing on the parent at all. Skipping `Initialize()` and instead driving
`SetBagID`/`SetID` directly (both self-contained, no parent dependency) gets the
untainted click with zero parent-frame coupling. Confirmed every reference addon
(AdiBags, Baganator, BetterBags) does exactly this — it's not a workaround unique to
us, it's how every real bag addon solves this.

**Escalation path not taken**: `SecureActionButtonTemplate` with `type="item"` (the
standard pattern for trinket-click/quick-use addons) was considered and set aside —
it only fits "use by item link," not bag-slot pickup/move, and the template inheritance
above solves both cleanly with less code than reimplementing either path ourselves.

**Known related traps** (from `references/BetterBags/.context/patterns-taint.md`,
not yet hit by us but worth knowing before touching bank support): assigning to the
global `_` without `local` taints it and breaks unrelated protected calls elsewhere.

**Corrected 2026-08-17** (`Bank.lua`'s `HideDefaultBank`, user-directed — "explore
how Baganator does it"): this note previously warned that touching `BankFrame`/
`BankPanel` at addon-init time, at all, could permanently taint every future
`UseContainerItem` call, backpack included, because `UseContainerItem` itself reads
`BankFrame:GetActiveBankType()`. That framing was too broad. Baganator's own real,
shipped code (`references/Baganator/ViewManagement/Initialize.lua`'s
`HideDefaultBank`) calls `BankFrame:SetParent(hidden)` and clears its `OnHide`/
`OnEvent`/`OnShow` scripts unconditionally at addon load — in production, for a
widely-used addon, with no reported taint fallout. `SpeedyBags/Bank.lua` now does
the same. The part of the original warning that's still true: what actually taints
`UseContainerItem` is *reading state back* off `BankFrame`/`BankPanel` (a
`GetActiveBankType()`-style call) from within a tainted call chain — not structural
`SetParent`/`SetScript(nil)` calls on the frame object itself. `Bank.lua`'s
`GetBankBagIDs` avoids the former entirely (driven off `C_Bank`/`C_Container`), so
this distinction is what makes `HideDefaultBank` safe to add without touching the
part of the hazard that's real. Not independently verified in-game by us yet —
adopted on the strength of Baganator's production use, not first-hand confirmation.
