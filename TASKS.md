# TASKS.md — Investigation tasks

This is a scaffolding/task-expansion pass, not an implementation pass. Every task
below is an **investigation** to run before writing addon logic. None of these are
"just do it" tickets — each needs a decision recorded (in `DESIGN.md` or a new
`DECISIONS.md` entry) before the corresponding architecture piece gets built.

Format per task: Goal, Success conditions, Failure conditions, Direction hints.

---

## 1. Controller nav graph model

**Status: resolved 2026-08-16.** The mechanism is confirmed; what's left is applying
it to a real bag layout, which is implementation, not investigation.

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

## Suggested order

1 and 2 are the core UX differentiator and should be resolved before any frame code
is written at all — they determine the addon's fundamental frame/slot structure.
3 and 4 shape the data layer and can proceed in parallel with 1/2. 5 and 6 are
tooling/dependency decisions that unblock *writing* code correctly but don't change
the architecture — do them early enough to not write throwaway code, but they're not
gating on 1/2's outcome.
