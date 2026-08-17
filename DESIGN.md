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
global `_` without `local` taints it and breaks unrelated protected calls elsewhere;
touching `BankFrame`/`BankPanel` at addon-init time (before the bank is actually
open) can permanently taint all future `UseContainerItem` calls, even for the
backpack, because `UseContainerItem` itself reads `BankFrame:GetActiveBankType()`.
