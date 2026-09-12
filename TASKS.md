# TASKS.md — Investigation tasks

This is a scaffolding/task-expansion pass, not an implementation pass. Every task
below is an **investigation** to run before writing addon logic. None of these are
"just do it" tickets — each needs a decision recorded (in `DESIGN.md` or a new
`DECISIONS.md` entry) before the corresponding architecture piece gets built.

Format per task: Goal, Success conditions, Failure conditions, Direction hints.

---

## 1. Controller nav graph model

**Status: resolved 2026-08-16, corrected 2026-09-12 — the 2026-08-16 resolution was
incomplete.** The attribute contract below is real and still correct, but it turned
out to be necessary, not sufficient: without the registration finding added below,
ConsolePort never scans SpeedyBags' frames at all, so `nodeignore`/`nodepriority`
were inert the whole time. Caught by the user in-game ("the console port ui cursor
still doesn't register the menu as a valid target to navigate to/from").

**Addendum 2026-09-12 — the missing gate.** `ConsolePortNode`'s `NODE(...)`
(`references/ConsolePortNode/ConsolePortNode.lua:174`) only ever scans the specific
frames it's handed — it never walks `UIParent`'s full child tree looking for
mouse-enabled frames. The caller, `Cursor:FlatScanStack`
(`references/ConsolePort/ConsolePort_Cursor/View/Cursor.lua:162-164`), hands it
`env.UnlimitedFrameStack` (`UIParent`, `DropDownList1/2` — fixed names, in
`ConsolePort_Cursor/Database.lua:147-172`) plus whatever
`Stack:GetVisibleCursorFrames()` currently reports. `Stack`
(`ConsolePort_Cursor/Controller/Stack.lua`) is a curated registry: a frame only
enters it via one of a fixed set of name lists
(`env.StandaloneFrameStack`/`StaticPopupStack`/`GroupLootStack`, all in
`Database.lua`), periodic scans of Blizzard's own `UIPanelWindows`/
`UISpecialFrames`/`UIMenus` (`env.FrameManagers`), hooks on
`ShowUIPanel`/`StaticPopupSpecial_Show`/`HelpTipTemplateMixin.Init`
(`env.FramePipelines`), or an explicit `Stack:SetFrame(frame, true, owner)` call —
the public entry point for the last one is `ConsolePort:AddInterfaceCursorFrame(frame)`
(`references/ConsolePort/ConsolePort/API.lua:143-151`). **There is no generic
"any nearby mouse-enabled frame" fallback.** `SpeedyBagsFrame`/`SpeedyBagsBankFrame`
match none of the fixed lists and are never shown via `ShowUIPanel`, so `Stack`
never marks them visible, `FlatScanStack` never includes them, and
`ConsolePortNode.Scan` is never invoked on their children at all —
`nodeignore`/`nodepriority` are correct but moot until this gate is passed.

**Fix**: call `ConsolePort:AddInterfaceCursorFrame(frame)` once per view, at frame
creation time in `UI.lua`'s `NewBagView` (after `frame` is created, ~line 324),
guarded the same way every other soft integration in this project is
(`if ConsolePort and ConsolePort.AddInterfaceCursorFrame then ... end` — safe even
before `ConsolePort_Cursor` (a load-on-demand module) has loaded, since the real
API internally defers via `EventUtil.ContinueOnAddOnLoaded`). No change needed to
ConsolePort itself, no compatibility-table edit, no new frame attribute — this is
purely a missing registration call on our side. **Implemented 2026-09-12**:
`UI.lua`'s `NewBagView` now calls it right after creating `frame`, existence-guarded.

**Goal**: determine how to represent and register a nav graph where item slots form
a clean up/down/left/right grid and category headers sit on a deliberately separate
axis, satisfying `DESIGN.md` invariants 1 and 5.

**Resolution**: ConsolePort's actual gamepad-cursor engine is a standalone library,
`ConsolePortNode` (`references/ConsolePortNode/`, `seblindfors/ConsolePortNode`,
pulled via ConsolePort's own `.pkgmeta` external — not vendored in the ConsolePort
clone itself, had to be cloned separately), used as `LibStub('ConsolePortNode')`
inside `ConsolePort_Cursor/Controller/Nudge.lua`. Read the full 855-line source and
its README:

- **There is no registerable adjacency graph.** `NavigateToBestCandidate` (three
  versions: "picky"/"balanced"/"permissive" strictness) and
  `NavigateToClosestCandidate` are all pure geometric candidate search — on every
  directional input, they scan the cached node set, compute each candidate's
  angle+distance vector from the current node's actual on-screen center
  (`GetCenterScaled`), and pick the best-scoring one. Confirms `DESIGN.md` invariant
  5's "positional inference" framing was correct — **but** the fix isn't "give
  ConsolePort a graph instead" (no such input exists); it's "control what geometry
  and eligibility the scanner sees," which is a different, more specific target than
  invariant 5 as originally worded implied. See note below.
- **The real override surface is a small, documented frame-attribute contract**,
  checked in `IsRelevant`/`IsInteractive`/`IsTree`/`GetPriorityCandidate`:
  - `nodeignore` (bool) — `frame:SetAttribute('nodeignore', true)` removes a frame
    from candidate selection entirely. **This is invariant 1's actual mechanism**:
    put it on any category-header frame (even a clickable one) and it can never be
    landed on by up/down/left/right from an item slot, while remaining reachable by
    a direct click and by any deliberate off-grid placement (invariant 1's "hard
    right instead of up/down").
  - `nodepriority` (number) — tiebreak/preference weight, relevant to
    `NavigateToArbitraryCandidate`'s fallback ("what does the cursor land on when
    the frame first opens/reopens" — task 2's cursor-stability question, not just
    task 1's).
  - `nodesingleton` (bool) — skip recursive scan of this node's children.
  - `nodepass` (bool) — include children as candidates but skip the node itself
    (useful for a category-header container that itself shouldn't be a target but
    whose children legitimately should be, if that shape ever comes up).
  - A candidate must also independently satisfy `IsInteractive` (real
    `IsMouseEnabled`/`IsMouseMotionEnabled`, not a `ScrollFrame` itself) and
    `IsRelevant` (visible, not forbidden, not anchoring-restricted) — a plain
    non-mouse-enabled `FontString` label is already excluded by default without
    needing `nodeignore` at all; `nodeignore` is only load-bearing for headers that
    are themselves clickable/mouse-enabled (e.g. collapsible category headers).
- **Decision (2026-08-16, user-directed): hand-authored graph is the default path,
  not a deferred escalation.** ConsolePort has no adjacency graph to hand it, but
  every D-pad press funnels through one confirmed choke point —
  `Cursor:Navigate(key)` in `ConsolePort_Cursor/View/Cursor.lua`, reachable globally
  via `db.Cursor` — so a companion module can monkey-patch that single function:
  save the original as an upvalue, replace `Cursor.Navigate` with a wrapper that
  checks a `graph[node][direction]` lookup first and only calls the original
  (geometric) implementation when no authored edge exists for that exact
  `(node, direction)` pair. Rationale: a hand-authored edge is O(1) and predictable;
  a live geometric rescan is neither, so hand-authored should be the normal path,
  not an optimization bolted onto geometry after the fact.
  **Every failure mode of the patch must still resolve cleanly**, which is why
  `DESIGN.md` invariant 1's `nodeignore`/`nodepriority` tagging discipline stays
  mandatory regardless of the graph: it's what makes the *fallback* — no ConsolePort
  installed, a ConsolePort update changes `Cursor:Navigate`'s shape so the patch
  can't apply (guard with `pcall`/shape-check before patching, degrade to
  doing nothing rather than erroring), or simply an un-authored edge — behave
  correctly on its own, not just the primary path. `DESIGN.md` invariant 5 and its
  Target Architecture section are updated to reflect this as the actual design, not
  a wording tweak.

**Success conditions**:
- Concrete answer for how ConsolePort (and ideally native/default gamepad UI nav)
  actually determines traversal order — positional inference, explicit
  `SetAttribute("nav-...")`-style hints, a registered node graph, or something else.
- A representation for "this frame is a nav node, and its up/down/left/right/etc.
  neighbors are exactly these other nodes" that can be built once from bag layout
  data and handed to ConsolePort without ConsolePort re-inferring anything.
- A concrete plan for where category headers live in that graph such that they are
  reachable only via deliberate lateral movement, never via up/down through the item
  grid.

**Failure conditions**: the only mechanism available is positional inference with no
way to override/register explicit adjacency — in which case the fallback (off-grid
placement, invisible spacer frames, etc.) needs to be found and its cost documented,
not silently adopted.

**Direction hints**:
- `references/ConsolePort/` is the primary source — it has its own `CLAUDE.md`, read
  that first. Look for how it registers frames as nav-capable and whether it exposes
  any override/hint API versus pure positional inference.
- Check whether ConsolePort exposes something like a custom nav-node API (grep for
  "UIHandler", "Node", "SetNode", "Compat" in `references/ConsolePort/`).
- Cross-check against how every reference bag addon (AdiBags, Baganator, Bagnon,
  BagBrother, BetterBags) currently lays out headers vs. slots — confirm the "mixed
  grid" failure mode is real and consistent before designing around it, don't take
  the user's description as unverified.
- Blizzard's default gamepad UI nav (`GamePadUI` covered in `Interface\FrameXML` /
  the wow-ui-source annotations under `references/BetterBags/.libraries/wow-ui-source`
  if present) may have its own separate inference model worth comparing against
  ConsolePort's.
- **Checked 2026-08-16, from the real client via `casc-tool`** (see
  `references/README.md` § `wow-client-source/`): no native nav-graph/adjacency
  registration system found in `ContainerFrame.lua`/`BankFrame.lua`/
  `ItemButtonTemplate.lua`, despite a broad search across the whole client tree for
  `*gamepadui*`/`*navigat*`/`*cursor*`. This is a real negative result, not an
  unexplored gap — ConsolePort remains the primary source for this task; Blizzard's
  own client doesn't appear to expose an alternative worth comparing against.

---

## 2. Cursor stability under action (bags + knowledge points)

**Goal**: figure out the mechanism by which the gamepad/controller cursor's focused
node is determined after a frame's contents change (item consumed, slot emptied,
stack partially consumed, item opened into another item), so cursor focus can be
pinned to "the stack the player just acted on" per invariant 2.

**Success conditions**:
- Identified event(s) that fire on slot content change (`BAG_UPDATE`, `ITEM_LOCK_CHANGED`,
  `BAG_UPDATE_DELAYED`, or similar) and confirmation of what ConsolePort/default UI
  currently does with cursor focus in response.
- A concrete technique for suppressing/overriding the default refocus (if any) so the
  cursor stays put on a slot that may now contain a different item, fewer items, or
  be empty — without breaking ConsolePort's own state tracking.
- Same investigation extended to "opening" Knowledge Point items/parchments
  (profession Knowledge tokens) — confirm whether that UI surface is a bag slot
  interaction at all, or a separate frame/flow with its own cursor behavior, since
  the fix might differ by surface.

**Failure conditions**: cursor-focus-on-refresh turns out to be hardcoded inside
ConsolePort with no addon-facing override — in which case document the workaround
options (e.g. addon posts a synthetic re-focus after ConsolePort's own update pass)
and their tradeoffs, rather than declaring the invariant unachievable.

**Direction hints**:
- Artisan's Mettle bags (Blizzard's own delve-currency container UI) and generic
  "loot chest" multi-open flows are the reference behavior the user wants matched —
  these are Blizzard UI, not in `references/`; may need to check `warcraft.wiki.gg`
  Widget API docs or in-game observation for how they hold cursor position.
- `references/wow-client-source/interface/addons/blizzard_uipanels_game/mainline/ContainerFrame.lua`
  (pulled 2026-08-16 via `casc-tool` from the real client, see `references/README.md`)
  calls `CanAutoSetGamePadCursorControl(true)` / `SetGamePadCursorControl(true)` on
  opening a new bag frame (`ToggleBag_Individual`, ~line 189) — the one concrete
  native gamepad-cursor touchpoint found in this file. Both functions are
  undocumented beyond their names in `references/vscode-wow-api`'s annotations
  (bare wiki stubs, no params/return) — worth an in-game trace of what they actually
  do to focus before relying on them, not just reading the call site.
- `references/ConsolePort/` again — search for focus/cursor set calls tied to bag or
  container events specifically, not just general nav code.
- Determine whether "Knowledge Points" here means the profession Knowledge parchment
  items (bag-slot interaction) or the Warband/profession Knowledge tree UI (not a bag
  surface at all) — this changes which frame the investigation targets. Don't assume;
  confirm the UI surface first.
- **Found 2026-08-16, directly on point**:
  `references/ConsolePort/ConsolePort_Cursor/Controller/Stack.lua` tracks which
  frames are cursor-navigable and re-derives cursor placement whenever the visible
  set changes (`Stack:UpdateFrames` → `db.Cursor:OnStackChanged`). Its own `hideHook`
  comment (line ~80) names this exact failure mode: *"Use C_Timer.After to
  circumvent node jumping when closing multiple frames, which leads to the cursor
  ending up in an unexpected place on re-show. E.g. close 5 bags, cursor was in 1st
  bag, ends up in 5th bag on re-show."* — i.e. ConsolePort already has internal
  machinery fighting a version of invariant 2's problem, it just doesn't solve our
  specific case (staying on a slot *within* a still-open frame across content
  changes). The actual re-placement logic is
  `NavigateToArbitraryCandidate(cur, old, x, y)` in `references/ConsolePortNode/`:
  it prefers the previous node if still a valid candidate (`cur`/`old` args), else
  falls back to `GetPriorityCandidate` using `nodepriority` and screen-distance from
  the last known coordinates. **This means invariant 2 is achievable through the
  same attribute contract as task 1**: keep the slot's underlying frame/widget
  identity stable across a content update (don't recreate/reparent the frame the
  cursor is on when its item changes, only mutate its texture/count/tooltip) so
  `cur`/`old` still resolves to it, and use `nodepriority` to bias reselection
  toward it if identity can't be preserved. Not yet verified end-to-end against a
  real bag frame — this is a mechanism finding, not a tested fix.

---

## 3. Non-blocking bulk update model

**Goal**: determine whether/how bag-content UI updates can avoid blocking interaction
with the rest of the interface during high-churn operations (looting, mailbox,
vendor selling, unboxing containers), per invariant 4.

**Success conditions**:
- Clear technical answer on whether "blocking" in existing addons is literal (a long
  synchronous Lua loop holding the frame) or perceived (full-frame redraw per event
  making the bag frame unresponsive/flickery while other frames remain interactive).
  These have different fixes.
- A concrete event-driven or throttled-update design (e.g. coalescing rapid
  `BAG_UPDATE` bursts into one deferred layout pass via `C_Timer` /
  `OnUpdate` throttling, versus patching only the changed slot per event) with a
  reasoned choice between them, not just a list of options.
- Confirmation of whether Blizzard's container APIs impose any inherent sync cost
  (e.g. `GetContainerItemInfo`-family calls being expensive at bulk scale) that
  bounds how "instant" this can actually be.

**Failure conditions**: if bag-frame responsiveness turns out to already be
non-blocking at the WoW UI-thread level (i.e. the perceived slowness in competitor
addons is purely wasteful full rebuilds, not an engine constraint) — that's still a
valid, useful finding; report it as such rather than forcing an events-vs-sync
framing that doesn't apply.

**Direction hints**:
- Profile-by-reading: check how AdiBags/Baganator/Bagnon structure their update
  functions — do they rebuild the whole layout on every `BAG_UPDATE`, or diff?
  `references/BetterBags/.context/data-loader.md`, `layout-rendering.md`, and
  `virtual-stacks.md` look directly relevant — BetterBags already documented its own
  reasoning here, worth reading before designing from scratch.
- `references/Baganator/` also separates "data" from itself in its folder layout
  (`API` dir) — check if that split maps to anything useful for this task.

---

## 4. Junk (vendor-trash) consolidation

**Goal**: design the single-slot junk aggregation described in invariant 3 —
detection, display, and interaction (what happens when the player targets the Junk
slot: sell-all? preview list? nothing but a count?).

**Success conditions**:
- A defined, single-sourced rule for "is this item junk" (sell-vendor-price-only
  heuristic vs. explicit quality/type rules vs. user override list) — one field, one
  check, one destination, per the foreign-data policy in `~/.claude/CLAUDE.md`.
- A defined interaction model for the Junk slot itself: is it a nav target at all
  (tension with invariant 1's "category headers aren't nav targets" — junk is an
  aggregate but might still need to be actionable, e.g. "sell all junk"), and if so
  what confirming on it does.
- Confirmation of what item-quality/binding/type data is actually available
  client-side to classify without a server round-trip or vendor-open dependency
  (since junk-detection ideally works even away from a vendor).

**Failure conditions**: no reliable client-side signal exists for "vendor trash"
without visiting a vendor (some addons approximate via item quality = Poor, which is
a narrower definition than colloquial "junk") — document the gap and the fallback
(Poor-quality-only vs. a broader heuristic vs. requiring an explicit user junk list)
rather than overclaiming detection accuracy.

**Direction hints**:
- AdiBags has an established filter-rule system for exactly this kind of
  classification — read its filter modules for the existing heuristic even though we
  won't copy its UI.
- Check `C_Item`/`GetItemInfo`-family API docs (`warcraft.wiki.gg/wiki/World_of_Warcraft_API`,
  referenced from `references/BetterBags/.context/api.md`) for sell price and quality
  fields available without a vendor open.

---

## 5. WoW API reference / language server tooling

**Status: substantially resolved 2026-08-16.** Sources pulled into `references/`;
remaining open item is a hands-on tooling trial, not sourcing.

**Goal**: determine whether real autocomplete/type-checking against actual WoW API
signatures is achievable in-editor, instead of writing Lua against an API we can't
verify function-by-function.

**Findings**:
- `references/vscode-wow-api/` (`Ketho/vscode-wow-api`, MIT) has a complete
  LuaLS/EmmyLua annotation set under `Annotations/`, generated from Blizzard's own
  `Blizzard_APIDocumentationGenerated` source plus warcraft.wiki.gg. Verified it
  covers `C_Container` in full, including `GetBagSlotFlag`/`Enum.BagSlotFlags` and
  `GetBackpackSellJunkDisabled` — directly relevant to task 4 (junk detection). This
  answers the "does a comprehensive set already exist" question: yes.
- `references/wow-ui-source/` (`Gethe/wow-ui-source`, `live` branch) is the ground
  truth those annotations are generated from — Blizzard's actual FrameXML/Lua source.
  Confirmed the installed client at `/media/luna/games/World of Warcraft/_retail_`
  does *not* expose this directly (modern client packs `Blizzard_*` UI source into
  CASC, no loose `.lua`/`.xml` on disk) — this mirror is the only practical way to
  read it without extracting CASC archives.
- `references/wowlua-ls/` (`TradeSkillMaster/wowlua-ls`, GPL-3.0, beta) is a
  purpose-built WoW language server — stronger than generic `lua-language-server` +
  annotations (typed event payloads, XML-frame-as-class inference, `.toc` awareness,
  wrong-flavor-API diagnostics). It's built on the same Ketho/Blizzard-doc lineage
  (its `stubs/overrides/` explicitly overrides "Ketho's vendored" annotations), not
  an independent source. Installable via VS Code Marketplace
  (`TradeSkillMaster.wowlua-ls`, binary bundled — usable directly in this repo's dev
  environment) or as a Neovim LSP binary (`cargo build --release` or a GitHub
  Release download) for `mobile_fox`.

**Decision**: use `wowlua-ls` as the primary in-editor tool (VS Code Marketplace
install; Neovim binary on `mobile_fox`) — it's purpose-built for exactly this
problem and both dev machines can run it without a flake change. Keep
`lua-language-server` + `references/vscode-wow-api/Annotations/` in the flake/repo as
a fallback if `wowlua-ls` (beta, GPL-3.0) proves too unstable to depend on, or if a
GPL-3.0 dependency in the toolchain (not the addon itself) turns out to be
undesirable — that tradeoff wasn't evaluated here and should be a deliberate call,
not a default.

**Remaining work**: actually install `wowlua-ls` in VS Code and confirm
hover/autocomplete against a real `C_Container` call in `SpeedyBags.lua` — nothing
above has been tooling-tested end to end yet, only sourced and read.

**Direction hints (superseded by findings above, kept for provenance)**:
- `references/BetterBags/.context/api.md` names `warcraft.wiki.gg` as the canonical
  API reference for both widget and non-widget (`C_*`) APIs — useful as a fallback
  cross-reference even with annotations/LS in place.

---

## 6. Community addon framework evaluation

**Goal**: decide for/against adopting an existing community framework (Ace3 family,
LibStub, CallbackHandler-1.0, or others) versus building directly on the raw WoW API,
and justify the decision in `DESIGN.md`.

**Success conditions**:
- For each framework piece under consideration (AceAddon, AceEvent, AceDB, AceGUI,
  AceConfig, LibStub, CallbackHandler-1.0, LibDataBroker, LibSharedMedia), a specific
  yes/no with a one-line reason tied to this project's invariants — not a blanket
  "use Ace3" or "avoid Ace3."
- Explicit check of whether any candidate framework's patterns conflict with
  invariant 5 (explicit nav graph, not positional inference) — AceGUI in particular,
  since it's a layout/widget framework and BetterBags' use of it is worth reading
  critically rather than assuming it's compatible.
- A stated position on event dispatch specifically, since invariant 4 (non-blocking
  bulk updates) lives largely in how events get handled — does AceEvent's dispatch
  model help or hurt versus raw `frame:RegisterEvent`/`OnEvent`?

**Failure conditions**: none — this task always produces a usable answer as long as
each framework piece gets an explicit reasoned call instead of a vague default.

**Direction hints**:
- `references/BetterBags/BetterBags.toc` `OptionalDeps` line lists the framework
  stack it uses — good enumeration of what's available, not evidence it's right for
  us.
- `references/AdiBags/install-deps.sh` shows the older `libs/` SVN-checkout pattern
  for the same libraries — useful for understanding what "vendoring Ace3" actually
  costs in repo size/maintenance if we go that route.
- Nix packaging note: if any library needs to be vendored rather than fetched via
  SVN/git at dev time, that's a `nix/flake.nix` fetcher question (`pkgs.fetchFromGitHub`
  or similar) — flag back to the flake once the framework decision is made, per the
  "adding a package" rule in `~/.claude/CLAUDE.md`.

---

## 7. Layout position stability (no in-session reflow, reserved identity-keyed slots)

**Status: implemented 2026-09-12, corrected same day.** `UI.lua`'s `GroupEntries`/
`Sort`/`RenderSection`/`RenderSubcategory`/`RenderNewItemsArea` rewritten per the
design below; `Data.lua`'s `NewRecentTracker` (the old timer-driven "Recent"
heuristic) removed outright. **Correction**: the first implementation made `Sort`
purely append-only (never revisiting an already-reserved subcategory/item) —
the user then asked directly whether a dead reservation (an item no longer
owned) ever gets reclaimed, exposing that it didn't, forever, until `/reload`.
`Sort` now recompacts every touched subcategory's membership against what's
actually owned at sort time (dropping a fully-empty subcategory's reservation
entirely), while keeping the size-weighted column stickiness described below.
This required adding `state.keySubcat` (a reverse key -> subcategory lookup) so
compaction can find and clear stale reservations for departed items — without
it, an item that left before a compaction, then reappeared later in the same
open session, could collide with or render outside a freshly shrunk block.
Untested in-game — same caveat as every other round.

**Goal**: satisfy `DESIGN.md` invariant 6 (added this session, user-directed hard
constraint) — once a subcategory or an item is rendered at a screen position while
a view is open, nothing about that position may change until the view closes,
except the Recent/new-items row overflowing.

**Root cause, confirmed by reading `UI.lua`**: `RenderSection` (the masonry packer
added 2026-08-17) and its helpers recompute layout from scratch on every `Refresh()`,
which fires on every model change via `ScheduleRefresh`'s 0.1s debounce (i.e. on
essentially every loot/vendor/craft/use event while the window is open):
- `OrderedSubcats` sorts subcategories by *live* entry count (densest-first) —
  a subcategory gaining or losing one item can change its sort position relative to
  others.
- `SubcatCols` sizes a block's width from the *live* entry count — a block's own
  width, and therefore everything's wrap point, changes as items come and go.
- `RenderSection`'s masonry loop assigns each block to "whichever column is
  currently shortest," recomputed fresh every render — a block placed in column 2
  last render can land in column 4 next render because some other block earlier in
  `OrderedSubcats`'s (also-changing) order grew or shrank first.

Widget *identity* is already stable (pooled by `entry.key`, per task 2's finding) —
this is a different bug: the same widget object gets reassigned to a new `(x, y)`
every render, which is exactly as disorienting as reassigning identity, both for a
mouse player watching items visibly jump and for ConsolePort's own geometric
reselection (`NavigateToArbitraryCandidate`, task 2's finding), which scores
candidates by on-screen distance from the cursor's last known position — a moving
target actively fights the very mechanism task 2 found for keeping the cursor put.

**Design, resolved 2026-09-12 (user-directed — see `DESIGN.md` invariant 6 for the
full framing)**: layout position becomes a reservation, written only by an
explicit sort pass, never by `Refresh()` itself.

- **Reservation table** (`sortState`, held in `NewBagView`'s closure per view,
  session-only — reset makes sense on `/reload` since a fresh sort runs anyway):
  `subcatColumn[groupKey..sectionName..subcatName]`, `itemSlotIndex[entry.key]`
  (grid index within its subcategory's block), plus enough of each subcategory's
  previous width/row-count to support the size-weighted resort below. `Refresh()`
  becomes read-only against this table: it looks up where each currently-present
  entry belongs and paints it there, and never writes a new position itself.
- **Two sort triggers, and only two — both at close time, not open**: (1)
  `view.Hide()` runs the sort pass (corrected 2026-09-12, user correction: sorting
  on the *next* `Show()` instead would delay opening the window, which is exactly
  the "recompute it every time you open the container" cost this addon exists to
  not have — see `SpeedyBags.lua`'s own scan/render split note); (2) a new "Sort"
  button (chrome alongside the existing Deposit Reagents / tab-button row) runs
  the same sort on demand while the view is already open. Sorting at close time
  rather than at the next open also means an item that first appears while the
  view is closed sits unsorted in New Items until the *next* close, not the
  following open — a deliberate, correct consequence of tying the sort to close,
  not a gap to fix. No `OnChanged` listener, timer, or event handler ever calls
  the sort function — only these two. `view.Show()` stays exactly as fast as it
  is today: it never sorts, only renders whatever the reservation table already
  says.
- **Sort pass** (`Sort(model)` or similar): for every entry currently in
  `model.entries`, if it already has an `itemSlotIndex` reservation from before,
  keep it (this is what makes "reacquire a matching item mid-session and it falls
  back into its old slot" work — the reservation was never cleared just because
  the entry briefly vanished from `model.entries` at zero count). For every entry
  with no reservation, assign one now: subcategory column via masonry's existing
  "shortest column" heuristic, but **weighted by the previous layout, biased to
  keep large/dense subcategories where they were** — e.g. process subcategories
  largest-first and only move a subcategory off its previous column if the height
  imbalance clears some threshold, while subcategories with no previous
  assignment (or small ones) flow freely into whatever's shortest. Exact
  weighting/threshold is a tuning knob, not specified here — build it adjustable
  (a local constant) rather than hardcoding a specific bias amount.
- **New Items staging**: an entry with no reservation is not written into the
  category grid at sort time either if the sort itself decides to defer it — in
  the common case (mid-session, item picked up between sorts) it simply has no
  reservation yet at all and renders in the New Items area (`RenderAggregateRow`'s
  existing Recent row, repurposed as a true holding area rather than an
  auto-expiring convenience list — see below) until the next sort assigns it a
  real cell. This is what keeps a plain item pickup from reflowing anything: the
  new item never touches the category grid until a deliberate sort runs.
- **New Items area itself changes shape**: `Data.lua`'s `NewRecentTracker`
  (`RECENT_WINDOW_SECONDS` auto-expiry, `RECENT_ICON_CAP` hard cap) currently
  moves items out of Recent on a timer — that's a third, silent reflow trigger
  under the new invariant, so the timer-driven removal needs to go (an item stops
  being "new" and gets a real reservation only via a sort, not a clock). What
  can stay: a bounded on-screen area for it, and *that* area is the one place
  still allowed to reflow freely (wrap, shrink icons, grow rows) when it's full —
  the literal "no space left in the new items section" exception from the
  original ask. Whether Recent's cosmetic "just arrived" highlight survives
  independent of this (e.g. a fading glow on an item that already has a
  reservation and rendered straight into its slot) is a nice-to-have, not
  required by the invariant.

**Success conditions**: watching a loot/vendor/craft burst in-game, nothing
already-placed moves; a genuinely new item appears only in the New Items area;
reacquiring an item whose last copy was just consumed puts it straight back in
its old slot; closing the view (or clicking Sort while it's open) produces a full
layout where large/dense subcategories (Crafting materials, say) land in the same
column they were in before more often than small ones do; opening the view is
still instant (no sort runs on open) even right after an item appeared while it
was closed — that item shows up in New Items, not pre-sorted.

**Failure conditions**: none expected for the mechanism itself — this is a
rewrite of already-understood code against a fully specified design, not an
open investigation. The size-weighted resort's exact bias is the one piece that
may need in-game tuning after the fact.

**Direction hints**:
- `UI.lua`'s `RenderSection`/`RenderSubcategory`/`OrderedSubcats`/`SubcatCols`
  need to split into a read-only render pass and a separate sort pass; `Data.lua`'s
  `NewRecentTracker` needs its expiry-driven removal replaced by "stays until a
  sort gives it a real slot"; `Categorize`/merge logic in `Categories.lua`/
  `Data.lua` are unaffected.
- The new Sort button is UI chrome only (a button + a function call) — no new
  taint concern, it doesn't touch container APIs, just re-runs layout math.
- Whether the reservation table should persist across `/reload` (a `SpeedyBagsDB`
  entry, another SavedVariables boundary to validate) is still a nice-to-have,
  not required — a view always sorts fresh on first show after being hidden
  regardless.

---

## 8. Default bag UI leaking through alternate open paths (Item Upgrade UI, etc.)

**Status: resolved and implemented 2026-09-12** — root cause confirmed against real
client source; `SpeedyBags.lua` now has `HideDefaultBags()` (mirrors `Bank.lua`'s
`HideDefaultBank()`) plus `SpeedyBagsFrame`/`SpeedyBagsBankFrame` registered in
`UISpecialFrames`.

**Goal**: explain why the user still sees Blizzard's own default bag UI in some
situations (named example: the Item Upgrade view) despite `SpeedyBags.lua`'s
global-function overrides, and why, once shown that way, it can't be closed
without `/reload`.

**Findings**: see `DESIGN.md`'s new "Default-UI suppression must be structural,
not a global-function hook" section for the full writeup — summary:
`Blizzard_ItemUpgradeUI` opens bags via `OpenAllBagsMatchingContext` → raw
`OpenBag(i)`, bypassing all five globals `SpeedyBags.lua` redefines; closing
(both the UI's own close and Escape) routes back through the global
`CloseAllBags`, which we redefined to only hide our own frame, so Blizzard's
real frame is left with nothing able to hide it (it's also absent from
`UISpecialFrames`, so there's no independent Escape fallback). Baganator and
BetterBags both avoid this entire class of bug by suppressing the bag frame
*structurally* (reparent + clear scripts), the same technique `Bank.lua`
already uses for `BankFrame` — they don't special-case Item Upgrade at all,
because it doesn't matter which path tried to show the frame once the frame
itself can't render.

**Fix**: `HideDefaultBags()` in `SpeedyBags.lua`, structurally identical to
`Bank.lua`'s `HideDefaultBank()` — reparent `ContainerFrame1..6` and
`ContainerFrameCombinedBags` onto a hidden frame, clear their
`OnShow`/`OnHide`/`OnEvent` scripts, called once at load. Register
`SpeedyBagsFrame`/`SpeedyBagsBankFrame` into `UISpecialFrames` so Escape closes
our own frames directly (a related but separate gap — currently neither is
registered anywhere for Escape-to-close).

**Direction hints**:
- `references/Baganator/ViewManagement/Initialize.lua`'s `HideDefaultBackpack`
  and `references/BetterBags/core/init.lua`'s `HideBlizzardBags` are the two
  confirmed real, shipped precedents — read either before implementing, same as
  `Bank.lua`'s own header comment already does for the bank case.
- BetterBags keeps Blizzard's own internal open/closed bookkeeping in sync via
  `ForceShowBlizzardBags`/`ForceHideBlizzardBags`, still calling the real
  `OpenBag`/`CloseBag` on the now-harmless reparented frames rather than never
  calling them at all — worth checking whether SpeedyBags needs the same (some
  other system may read "is a bag frame open" state) before assuming a bare
  reparent is sufficient.
- A live in-game repro of the Item Upgrade UI trigger specifically is still
  worth doing before/after the fix — this was confirmed by reading source, not
  by reproducing live.

---

## 9. Bag-adjacent Blizzard UI surfaces beyond bags/bank

**Status: surveyed 2026-09-12 (competitor research only), no decisions made —
this is a scoping list, not a commitment to build any of it.**

**Goal**: the user asked what other Blizzard UI surfaces involve picking items
out of bags (beyond the plain bag view and the bank, both already covered),
whether any reference addon already covers them, and which are trivial enough
to pick up versus genuine gaps worth just documenting.

**Findings** (reference addons surveyed: Baganator, BetterBags, AdiBags,
Bagnon, BagBrother):

| Surface | Native frame | Reference coverage | Rough difficulty |
|---|---|---|---|
| Guild Bank | `GuildBankFrame` (`Blizzard_GuildBankUI`) | **BagBrother** only — a substantial module (`frames/guild/*`, ~620 lines: tabs, slots, money, deposit/withdraw log). Baganator/BetterBags/AdiBags/Bagnon have nothing for it. | Large — comparable to or bigger than the existing Bank.lua work (tabs, permissions, a log). |
| Void Storage / account-wide transmog | No `Blizzard_VoidStorageUI` addon exists in current wow-ui-source; only a vestigial `PlayerInteractionType` enum value remains. Modern transmog collection lives in the Collections UI, not a bag-picker flow. | BagBrother has a `frames/vault/*` module calling `ClickVoidStorageSlot` — looks like dead code for a removed system. | Uncertain whether this surface still exists in-game at all — confirm live before considering it further; current evidence says it's defunct. |
| Mailbox attachment slots | `MailFrame` (`Blizzard_MailFrame`) | **Baganator**: `Transfers/AddToMail.lua` (~30 lines) — not a UI replacement, just drives existing Blizzard attachment slots via `SetSendMailShowing`/`UseContainerItem`. | Trivial-to-small — an action hooked from our own view, not a frame to build. |
| Trade window | `TradeFrame` | **Baganator**: `Transfers/AddToTrade.lua` (~35 lines), same action-not-UI pattern (`PickupContainerItem` + `ClickTradeButton`). | Trivial-to-small, same shape as mail. |
| Merchant sell (beyond junk-selling, which we already have) | `MerchantFrame` | **Baganator**: `Transfers/VendorItems.lua` (~50 lines) — batch-sell a selected list, with throttle/shift-lock handling for gold-cap edge cases. | Small-to-moderate — the core logic is small, the edge-case handling is the real cost. |
| Auction House "post item" | `AuctionHouseFrame` (`Blizzard_AuctionHouseUI`) | None of the five touch the posting flow (Baganator's `Compatibility/AuctionValue.lua` only reads pricing data). | Large, and apparently nobody's bothered — low priority. |
| Item Upgrade / Catalyst item-selection | `Blizzard_ItemUpgradeUI` / `Blizzard_ItemInteractionUI` (two distinct frames, both confirmed to still exist) | None of the five replace either — this is the surface the user hit as raw default Blizzard UI (see task 8), and no addon gives us a reference implementation to check assumptions against. | Moderate-to-large, and greenfield (no precedent to compare against, unlike task 8's suppress-the-frame fix which at least has one). |
| Quest reward / "use container item" bag display | Own item buttons, not a bag grid | Not touched by any reference addon. | Not worth pursuing — no precedent, low value. |

**Decision**: none required yet — recorded as a scoping list per the user's ask
("cover the ones that can be trivially covered, or at least document them").
Mail/trade/vendor-sell integration (all "trivial-to-small," all following the
exact same "action on selected items via existing Blizzard slots" shape
Baganator already validates) are the closest thing to a trivial win here if
ever picked up; guild bank and item-upgrade/catalyst are real gaps but sized
like their own multi-session features, not something to fold into this round.
Void Storage and Auction House posting are flagged, not recommended.

**Direction hints**: if mail/trade/vendor integration is ever picked up, model
it directly on Baganator's three `Transfers/*` files cited above (read for the
mechanism, per this project's normal reference-reading rule — not copied) —
they're all the same small shape: find the right Blizzard-provided slot/action,
drive it with `PickupContainerItem` on a selected entry list, same primitive
`Transfer.lua` already uses for bag↔bank moves.

---

## 10. Transfer verification / ghost-item reconciliation

**Status: implemented 2026-09-12** (design was user-directed, with one correction
mid-design — see mechanism 3 below). New `SpeedyBags/Verify.lua`; `Transfer.lua`
registers a verification record per entry before its queue starts stepping;
`UI.lua`'s `Refresh()` gained the render-layer self-check. Untested in-game.

**Goal**: eliminate "ghost item" bugs — an item that visually stays behind in
its old location, or fails to appear in its new one, after a move — for real
this time. `TODO.md`'s existing entries (category-transfer ghosting, "bank → bag
single-item moves also leave a ghost") were each patched with a single blanket
`RescanAllModels()` call after the fact; the user reports multi-item bag→bank
transfers still leave ghosts often, meaning a single post-hoc rescan isn't
enough — some items in a batch settle later than others, and a blanket rescan
run once at the end doesn't know *which* item is still wrong or retry just that
one.

**Design — two independent mechanisms, matching the user's own explicit spec**:

### 1. Fast, per-item verification loop for items just acted on

Every individual pickup/place pair `Transfer.lua`'s `StepQueue` executes
registers a **pending verification record**, keyed by item identity — a GUID
for equipment (`C_Item.GetItemGUID`, same identity `Data.lua`'s `EntryKey`
already uses and already documented there as "stable across slot moves"), or
itemID + a captured before/after count for anything stackable (see the open
question below for why stackables can't always use a literal GUID). Each
record carries enough to re-locate and, if needed, re-attempt the specific
move: `itemID`, `isEquipment`, `guid?`, `sourceBagIDs`, `targetBagIDs`, an
`attempts` counter, and (stackable only) the pre-move count in both locations
plus the expected delta.

A ticker runs only while at least one record is pending (`C_Timer.NewTicker`
or a self-rescheduling `C_Timer.After`, started on the first registration,
stopped when the pending set empties — no idle ticker running when nothing's
in flight) at the user-specified **~300ms** cadence. Each tick, for every
pending record, locate the item in the source/target bag lists and classify
into exactly the four cases the user specified:

- **Found in target only → success.** Remove from pending, done.
- **Found in source only (the move didn't take)** → retry: re-locate its
  *current* bag/slot (it may have shifted since the original attempt — same
  reason `StepQueue` already re-checks the source slot at step time, not
  queue-build time) and re-issue the pickup/place pair. Capped at the
  user-specified **2–3 attempts**; past the cap, mark the record failed, stop
  polling it, and surface it (a `UIErrorsFrame` line naming the item is the
  obvious place, exact UX not decided here).
- **Found in neither** → force a real rescan (`model.Update()` on both models
  involved, not just a render `Refresh()` — the staleness lives in
  `model.entries`, not the widget layer) and re-classify against the fresh
  scan. If it's still in neither after that, this is a genuinely ambiguous
  state (can't retry a pickup on an item we can't locate at all) — mark
  failed, log it with the identity and both bag-ID lists searched, stop
  polling.
- **Found in both** → same forced rescan, then re-classify. This is expected
  to resolve to "target only" almost every time (the "both" reading was just
  one model's cache not having caught up yet — the textbook ghost). If a
  rescan still shows it in both, treat as ambiguous the same way as above
  (never re-issue a pickup against what might be a real duplicate — that risks
  making things worse, not better) and log it rather than silently dropping it.

This is what answers the user's "tell us where we got stuck and what do we
need to retry": the pending record's own case classification *is* that
answer, at the moment it's known, per item — not inferred after the fact from
a final state diff.

### 2. Slow background reconciliation for everything else

The user asked for a periodic full pass over items *not* currently being
verified, "so the inventory is always up to date to the canonical list,"
explicitly non-realtime and non-blocking. This turns out to need almost no new
logic: `Data.lua`'s `Scan` already computes ground truth from
`C_Container.GetContainerItemInfo` every time it runs — "is the model current"
only fails today because `model.Update()` is purely event-triggered
(`BAG_UPDATE`/bank-slot-changed events, see `SpeedyBags.lua`'s schedulers), so
a missed or unexpectedly-absent event (the actual plausible root cause behind
the still-open "bank → bag drag-and-drop ghosting" `TODO.md` entry, which
doesn't go through `Transfer.lua` at all and so has zero verification
today) leaves a model stale with nothing to ever correct it. The fix is just a
periodic forced `model.Update()` independent of events — a
**`C_Timer.NewTicker(5, ...)`** (the user's own suggested ~5s cadence) calling
`ns.Model.Update()` / `ns.PersonalBankModel.Update()` /
`ns.WarbandBankModel.Update()` unconditionally, for the life of the addon.
`Data.lua`'s own comments already establish this scan is cheap (a
`GetContainerItemInfo` loop, no widget creation) and that `Refresh()`'s own
`IsShown()` guard already keeps the expensive render pass from running while a
view is hidden — so this ticker costs one cheap scan per model every 5s,
never a render, satisfying "in no way realtime, or blocking the render path."

### 3. Render-layer assertion (the piece missing from the first draft of this task)

**Correction 2026-09-12**, user pushback on the first version of this design:
mechanisms 1 and 2 above only verify **truth → data** (does `model.entries`
match real game state after a forced rescan). Neither one checks **data →
render** (does the actually-visible widget set on screen match
`model.entries`) — that step was silently assumed to always hold, via
`UI.lua`'s existing `Refresh()` hide-unused-widgets loop and the
`model.OnChanged(ScheduleRefresh)` wiring, never actually verified. A ghost is
a *rendered* phenomenon; a design that only re-proves the data layer correct
doesn't, by itself, prove the screen agrees with it — if the render layer ever
fails to hide/show a widget correctly (a pooling bug, a debounce timer that
gets cancelled and never fires, anything independent of data staleness), this
task's first two mechanisms would never catch it, no matter how often they
re-scan. Two additions close this gap:

- **The verification loop forces render, it doesn't hope for it.** Every time
  mechanism 1's fast loop or mechanism 2's background ticker calls
  `model.Update()`, it should also directly call that model's view(s)'
  `Refresh()` (not just rely on the existing debounced
  `ScheduleRefresh` eventually firing) — `Refresh()` is already a safe
  no-op when its frame isn't shown, so calling it unconditionally after any
  forced data update costs nothing and removes "did the debounce actually
  fire in time" as a variable in whether verification concludes correctly.
- **`Refresh()` gets a standing self-check, not just a one-time audit.** At
  the end of every `Refresh()` (in normal operation, not just during active
  verification), assert that the set of currently-`:IsShown()` widgets in
  `slotPool` exactly equals `usedKeys` (the set `Refresh()` itself just
  computed as "should be visible right now") — any widget shown but absent
  from `usedKeys`, or a key in `usedKeys` with no shown widget, is a real
  render-layer bug, independent of whatever the data layer says, and should
  be surfaced (print a diagnostic naming the mismatched key, per
  `~/.claude/CLAUDE.md`'s "on failure, always print expected and actual") and
  corrected on the spot (hide the stray widget / show the missing one) rather
  than trusted to have already been handled correctly by the loop above it.
  This turns "the hide-loop is correct" from an assumption into something
  actually checked on every single render, which is the only way to catch a
  render-layer ghost that has nothing to do with data staleness at all.
  **Cost, checked rather than assumed**: this is not a new pass — it folds
  into the hide-unused-widgets loop `Refresh()` already runs (`for key, btn in
  pairs(slotPool) do if not usedKeys[key] then btn:Hide() end end`), which
  already visits every pooled widget once per render. Reading `btn:IsShown()`
  at that same visit and comparing it to `usedKeys` membership is one extra
  cheap C-side call per widget already being touched, not a second iteration.
  `N` is bounded by real bag/bank slot counts (a few hundred at most across
  every bag and both bank types), and `Refresh()` itself is already debounced
  to at most once per 100ms and gated on the view actually being visible — so
  this adds a few hundred boolean comparisons to a pass that only runs on a
  coalesced burst of real changes, not a per-frame cost. The actual expensive
  part of `Refresh()` is the masonry/layout computation (task 7's concern, not
  this one) — this check is noise next to that.

With this third piece, the full chain (real game state → `model.entries` →
visible widgets) is actually verified end to end, not just the first half of
it.

**Open question, flagged rather than assumed**: does an item's
`C_Item.GetItemGUID` survive being moved into a destination slot that already
holds an existing stack of the same itemID (a merge), or does the moved
portion's GUID cease to exist once absorbed into the destination stack's own
instance? This determines whether pure-GUID tracking (as specified) is
reliable for the *common* case this bug report is actually about — batch
bag→bank moves of stackable materials, not equipment. This is server-side
inventory behavior, not something client-side FrameXML source can answer, so
it needs a live check, not more reading. **Until verified, the count-delta
fallback for stackables above (itemID + before/after count in both locations,
scoped to the delta this specific move caused) is the practical
operationalization of "item specific, not itemID specific" for anything that
can merge** — it can't misattribute a *different* stack of the same itemID
the way a bare "does itemID X exist in the target bags" check would, since
it's scoped to the exact quantity this move is responsible for. Equipment
(which never merges — see `Data.lua`'s own `EntryKey` note) can and should use
the literal GUID assertion the user specified with no caveat.

**Success conditions**: a multi-item bag→bank transfer, watched live, ends
with every item in its correct final location and zero visual ghosts within a
few polling cycles; an item that genuinely fails to move (e.g. destination
fills up mid-batch) is retried up to the cap and then reported, not silently
left wrong forever; the background 5s pass catches a plain drag-and-drop ghost
(no `Transfer.lua` involvement at all) within one cycle instead of it
persisting until an unrelated `BAG_UPDATE` happens to fire; and — the piece the
first two alone don't cover — a render-layer mismatch (data already correct,
screen not yet caught up, or a pooling bug) is caught and corrected by
`Refresh()`'s own standing self-check, not just assumed away.

**Failure conditions**: none expected for the background pass or the render
self-check (both mechanical, low risk). The fast loop's correctness for
stackables depends entirely on the open question above — if live testing shows
the count-delta fallback itself produces false positives/negatives (e.g.
because of unrelated concurrent bag activity during a transfer), that needs
its own follow-up, not a silent downgrade to "good enough."

**Direction hints**:
- New file recommended: `SpeedyBags/Verify.lua` — this is a big enough, single
  enough responsibility ("did this specific action's effect actually land, and
  if not what do we do about it") to earn its own file rather than growing
  inside `Transfer.lua`, matching this project's one-file-one-job convention.
  `Transfer.lua`'s `StepQueue` calls into it after each pickup/place pair
  instead of (or in addition to, during a transition period) its current
  single trailing `RescanAllModels()`.
- `Transfer.lua`'s `BuildQueue` only captures `{bag, slot}` today — it needs to
  also capture `itemID`/`isEquipment`/`guid?`/`stackCount` at build time (before
  anything moves), same as `Data.lua`'s `Scan` already does per entry, since
  that's the identity a verification record needs and it's cheapest to grab
  before the queue starts executing.
- `InCombatLockdown()` already short-circuits `StepQueue` — the verification
  ticker needs the same guard (don't retry a pickup/place while in combat).

---

## Suggested order

1 and 2 are the core UX differentiator and should be resolved before any frame code
is written at all — they determine the addon's fundamental frame/slot structure.
3 and 4 shape the data layer and can proceed in parallel with 1/2. 5 and 6 are
tooling/dependency decisions that unblock *writing* code correctly but don't change
the architecture — do them early enough to not write throwaway code, but they're not
gating on 1/2's outcome.
