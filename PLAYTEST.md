# Strata — playtest notes

This is yours. Write in it however you like; I read it.

**How we use it:** you play, you dump what you saw under the right heading, then
you say *"fix the UI"* (or the descent, or the caves) and I read only that
section and work through it. That keeps one topic on the table at a time instead
of everything at once in chat.

**Writing style does not matter.** Half sentences are fine. "this looks empty"
is a useful note. Don't tidy it up — the raw reaction is the useful part.

---

## How to mark things

```
- [ ] not done yet
- [x] done
- [!] this ruins it, do this first
```

When I fix something I add a line under it starting with `→` saying what I did,
and tick the box. If I disagree or can't do it, the `→` line says that instead
and the box stays open.

**Screenshots:** drop them in `notes/` and write the filename on the line, e.g.
`- [ ] the shop cards overlap — notes/shop-overlap.png`. Stills at the moment it
goes wrong beat video, which I can't read.

---

## Output window

Paste the Studio Output here after a fresh playtest — the whole thing, not just
errors. Every system prints when it starts and I've never seen any of it fire.

```
18:42:17  every service online, in order, no errors
18:42:17  [SaveService] no DataStore available -> progress NOT saved (place unpublished)
18:42:19  [MineGenerator] shell written in 2.43s, 1136 chunks (seed 28049)
18:42:19  [Descent] station at the Topsoil, deck -70.6   <- matches the computed value exactly
18:42:19  [DescentService] online, bore to -86           <- adaptive bore working
18:42:22  [MineClient] no arm joints. Rig joints found: absolutely none (R15, 25 parts)
18:43:44  [Expedition] took haul in the Topsoil on STEADY
18:45:11  ore exposed at x=140, y=-93  <- out in a hall, site generated fine
18:45:25  screenshot at 0m SURFACE, clock still running, no extract logged
          ^ the lift teleported out of the run
```

---

## 1. UI

Panels, HUD, fonts, colours, the shop and depot, the player card, buttons.

- [x] **Ghost title under every ribbon** — "Pick Works" / "Contracts" showing in
  dark text behind the plate.
  → My own text-outline change caused it. `TextTransparency = 1` hides a label's
  fill, but the `UIStroke` every label now carries has its *own* transparency, so
  the black outline kept drawing. Hidden outright instead.
- [x] **Pick Works header washed-out lavender** while Contracts was gold.
  → Every accent in `StrataConfig.Zones` was still an old pastel. Pick Works is
  violet now, Depot green, Forge orange, Lift cyan, Contracts gold.
- [x] **Pick Works showed one "???" card and no picks.**
  → A deadlock, and the worst bug in the pass. Picks are tier 2, 3 and 4 — there
  is no tier 1 — and the gate showed `tier <= (owned or 0) + 1`, so tier 1 only.
  Nothing was visible, so nothing was buyable, so nothing could ever become
  visible. The gate counts up from the cheapest tier that exists in each slot
  now. The scanner (also tier 2) was silently hidden by the same bug.
- [x] **The ribbon did not follow the panel accent** — stayed cyan over a gold
  header.
  → `setPanelAccent` puts the colour into a UIGradient, which *multiplies*, so
  the header's own BackgroundColor3 stays pure white and the property-changed
  hook never fired. Wrapping the function works.
- [x] **KIT had no ribbon** — plain text where every other screen has the plate.
  → Given one.
- [ ] **Huge empty space on tile screens**, and the detail pane is a big empty
  box saying PICK SOMETHING.
  → Partly self-solving now the picks actually appear, but the panel is still
  900px wide for a handful of tiles. Wants another look with real content in it.
- [ ] Kit screen: "HEAT 0 / 3" is cramped right under the armour slots.

---

## 2. The descent

- [x] It works — arrived in a Topsoil site at 118 m.
- [x] `[DescentService] online, bore to -86` — the adaptive bore is real: only
  the Topsoil was discovered, so it stopped just past that station.
- [x] `[Descent] station at the Topsoil, deck -70.6` — matches the computed
  figure exactly.
- [ ] Still no note on how the ride *felt*. The one thing I cannot see.

---

## 3. Dig sites

- [x] Generated and reads as a cave — mushrooms, terraces, varied floor.
- [x] **"felt good but almost too bright and lumen."**
  → My fault and recent: I raised the prop cap from 26 to 46 a hall last session
  and every glowing prop carried its own PointLight at full strength, through a
  bloom pass. Props still glow, but only one in three now lights the room, at
  about half brightness and a much shorter reach — counted rather than rolled so
  they spread instead of clumping.
- [ ] Still want a wide shot with your character in it to judge hall size.

---

## 4. Finding your way

- [x] Arrow, map and banner all drew. Map named halls and filled them in as they
  were walked (2/5, then 4/5).
- [x] **"0 / 34 Coalbit" was on screen twice** — banner and run card.
  → The run card drops its goal line and keeps the clock and the haul; the
  banner keeps the objective.
- [x] **The depth chart showed during a run**, behind the dig-site map.
  → It answers "where could I go", which is a camp question. Hidden below the
  surface now.
- [ ] **Roblox's own player list sits on top of the run card.** Not my UI, but
  it is covering mine. Either move the card or hide the list.

---

## 5. Contracts and objectives

- [x] Board reads well: cross-sections, HAUL / LOCKED pills, times, payouts.
- [!] **The lift teleports you out of a live run.** Confirmed in the Output:
  contract taken 18:43:44, at y -85 at 18:45:11, at 0 m by 18:45:25, no extract
  logged. That skips the entire extract decision the run is built around.
  → NEXT: this is the one I am doing now.

---

## 6. Flares

- [x] Slot shows, three pips, READY.
- [ ] Nothing yet on the throw, the arc, or the light it casts.

---

## 7. Mining and money

- [x] Strength 5 → 33 and credits 8,000 → 13,767 in one session.
- [!] **Progress is not being saved.** `[SaveService] no DataStore available —
  you must publish this place to the web`. Every session starts fresh until the
  place is published.

---

## 8. The camp

- [x] Lodge interior reads well — warm, lit, timber.

## 9. Bugs and performance

Anything broken, stuck, invisible, doubled, or slow. Frame drops and where.

- [ ] **No arm joints.** `[MineClient] no arm joints. Rig joints found:
  absolutely none` — R15, 25 parts. The pick swings on its tool weld so mining
  works, but your arms never move. Been there a while; not yet chased down.
- [ ] Nothing else reported. Shell wrote in 2.43 s over 1,136 chunks, no errors
  anywhere in the boot.

## 10. Feel and direction

The big one. Not bugs — whether it's any good.

Some things I'd genuinely like your answer to, whenever you have one:

- After ten minutes, what do you want someone to *say* about this game?
- Is a run fun, or just functional?
- Is this a **simulator** (numbers climb, you collect things, you can half-play
  it) or a **session game** (a clock, tension, a run you can fail)? I have been
  building the second and styling it like the first.

- [ ]

---

## Parked

Things we've decided not to do yet, so they stop coming back up.

- Vertical icon tab rail — the bottom bar already switches screens and the right
  edge is the detail pane; a rail would be a second navigation fighting the first
- Search boxes — 11 shop items, 16 kinds of rock; filtering that is chrome
- Collapse / mine instability — designed in `DESIGN-EXPEDITIONS.md` §3, not built
- The construction sink (build your way down to the Frostline) — §4, not built

---

## Reference

What's actually built and why is in `DESIGN-EXPEDITIONS.md`. Sections 6–11 cover
the descent, dig sites, flares, signposting and the UI restyle.
