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
- [x] There is overlapping in menus of shop etc. also font color and size need readjusting
- [x] Ui overlaps with the roblox top right corner UI which makes it a little tediuos, this is on mac tohugh I dont know about PC
- [x] When in the contracts menu, the side bar UI like shop and inventory overlap. this is unclear, also the black font color etc as mentioned above also the depth chart
  → **These three were one bug.** Nothing in the UI was responsive. The shop,
  contracts and kit screens are 900px wide and sat dead centre; the action bar
  (SHOP / KIT / PICKS / LIFT / RUNS / CAMP) sits at x=16 and is the *only* way to
  switch screens. So on any viewport narrower than about 1310 the panel simply
  covered the navigation, and the depth chart poked out from behind its other
  edge. On a desktop monitor you never see it; in Studio on a laptop, where the
  play viewport is a fraction of the screen, you cannot miss it. Not a Mac thing
  — it would do the same on the PC in a small window.
  → Screens now live in the band to the *right* of the action bar, centred in
  that band and scaled down to fit it rather than spilling over it. Checked at
  nine viewport sizes from 1920×1080 down to 760×520: the bar stays clear at all
  of them. Below 760 the fit gives up and takes the full width, so the bar now
  also draws on top — navigation you cannot click is worse than navigation that
  overlaps.
  → The depth chart hides while any screen is open. If a screen is up, the screen
  is what you are reading.
  → Roblox's player list is switched off. It draws above every ScreenGui, so no
  amount of moving my own UI gets out from under it, and a run is yours alone.
- [x] Font looks imported and isnt special
  → You were right and it was the most Roblox-default choice in the file.
  FredokaOne is the rounded bubbly face a thousand simulators use. Headings are
  **Oswald** now — condensed industrial, reads as lettering stencilled on a
  plate. Prose is Titillium, squared-off and slightly technical. Numbers are
  RobotoMono so the run clock doesn't jitter as it ticks.
  → The black outline on text dropped from 2.5px to 1.6px. It suited Fredoka's
  fat strokes and would have swallowed Oswald's thin ones, filling in the
  letters. That's half the answer to "hard to read".
  → Three lines in `StrataConfig.UI`. One-line revert if it reads worse moving.
- [ ] The Ui is choppy, you added designs like squares, unsmooth
- [ ] The picture for the map in the contracts is extremely lazy, I added an example of how it should look like in notes under the ideal UI idea.
- [ ] overall redisign of color fonts and the overall fonts and UI, it looks like a actual square instead of like a button if oyu know what I mean, I know its not ike that type of game, but I feel like we can polish it up a little bit. its also hard to read and where the coins are and everything in menus is not really clean looks really artificial. 
- [ ] can you get more theme from deep rock galactic UI? just that kind of vibe, not this imported and roblox vibe thing. Photo in notes
  → **Waiting on the pictures.** What came through in `notes/README.md` were
  Google image *search* links, not images — those are JavaScript pages with your
  session encoded in them, so I can't see what you were looking at. Save the
  actual files into `notes/` (right-click → Save Image As) and commit them.
  → I'm holding the palette deliberately rather than guessing. You told me
  earlier that grey "makes people know its AI", and DRG's look is desaturated
  gunmetal carried by hard amber accents — I don't want to swing the panels grey
  on a guess and undo the thing you already asked for. Font and readability I
  changed because those were unambiguous.
  → One thing I checked and it wasn't what I assumed: the coin is already a
  circle with a rim, not a square. So "looks like a square instead of a button"
  is about depth and press affordance somewhere else, and I need to see which
  screen.

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
- [x] **Roblox's own player list sits on top of the run card.** Not my UI, but
  it is covering mine. Either move the card or hide the list.
  → Hidden the list. You reported it again from the Mac, which settled it: the
  list draws above every ScreenGui, so moving my own UI can never win. A run is
  yours alone, so there is nothing for a player list to show.

---

## 5. Contracts and objectives

- [x] Board reads well: cross-sections, HAUL / LOCKED pills, times, payouts.
- [x] **You could end up on the surface with a live run and no way back down.**
  Contract taken 18:43:44, at y -85 at 18:45:11, at 0 m by 18:45:25, no extract
  logged.
  → I blamed the lift; wrong. The lift already requires you to be standing at
  the camp pad, so it could not have been used from -85. You died or reset —
  and **nothing in the server handled that at all**. You respawn at the camp,
  the contract is still live, the clock still runs, the haul is still in the
  manifest, and there is no way back down because the cage only descends when
  you sign for a job and you are already on one. The only exit was to stand
  there and watch the timer expire.
  → Dying now ends the run the way the clock does: a failure, keeping the same
  share of what you carried. And the lift refuses while a contract is live,
  because the cage is the way in and out for the length of a job.

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

---

## 11. Cave layout — the DRG pass

Worked from the reference brief you pasted. Most of it was right and is in;
three numbers in it were impossible here and I adapted rather than followed.

- [x] **Choke points.** Galleries were 18 studs wide for their whole run, which
  is generous plumbing, and generous plumbing is still plumbing. 54% of them now
  pinch to a 9-stud throat partway along, eased in and out rather than stepping.
  The path is unchanged — only the radius moves.
  → Verified open: 70,088 segments across 720 sites, **0 sealed pockets**, with
  10.75 studs of spare overlap at the tightest pair. This is the bug class that
  has bitten twice, so it is measured, not assumed.
- [x] **Hall size.** Was 36–112 studs across the three layers, under the 80–150
  the brief asks for. Now 34–150, median 76. The Topsoil spends it on width
  rather than height because it is only 160 studs thick.
- [x] **The void.** 31% of sites now end in a room 150–286 studs tall and taller
  than it is wide, where the layer has the height to hold one. Never in the
  Topsoil, which cannot.
- [x] **Darkness.** Caves were lit to about camp level, so every lamp in them was
  competing with free skylight. Lighting is now depth-driven on the client:
  the camp keeps exactly the look it had, and the caves crossfade to near-black
  with heavy distance haze tinted off the layer's own rock.
- [x] **A helmet lamp.** This is the piece the brief was missing and without which
  the rest is a trap — there was no player light anywhere in the game, so going
  dark would have left you blind between flares. Permanent spotlight on the
  head, plus a weak bulb at the chest so your own feet exist.
- [x] Hard shadow edges (`ShadowSoftness = 0`). A soft shadow reads as daylight
  through cloud.
- [x] `Lighting.Technology = Future` — the brief asks for this and it was
  already set, so point-light shadows were working.

**Where I did not follow it, and why:**

- [!] **Ambient is not pure black.** At zero, every surface no lamp touches
  renders flat #000 and Future lighting has no bounce to recover it — the cave
  stops having a silhouette or an up. It is set to 5 units of blue-grey, which
  is still black on screen. One number in `Look.Cave` if you want the absence.
- A 300-tall, 250-across void does not fit. The mine is 359 studs in radius, so
  250 cannot keep its clearance off the boundary wall, and a room whose floor
  you can walk onto needs twice its half-height under the layer ceiling. 165
  and ~286 is what the world takes. It matters less than it sounds: a lamp
  reaches about 30 studs, so a 286 roof is already ten times past being lit.
- Glowing veins embedded in the walls — not done. The props and mushrooms
  already glow and will pop much harder now the caves are dark; I'd rather see
  that first than add more light to a room we just finished dimming.

- [ ] **Needs your eyes.** Does the throat read as a squeeze or as an
  obstruction? Is the void awe or annoyance? Is the dark atmospheric or just
  dark — and is the helmet lamp too weak, too strong, or about right?

---

## 12. The grapple

New, from the external brief. The brief listed grappling as an existing system —
there was none anywhere in the project, and sections 2, 9 and 10 of it all hang
off one, so this had to come first.

**Q to fire. Crosshair lit green = reachable. Q again mid-flight releases early.**

- [ ] Does the pull feel fast or slow? It is 140 studs/sec, a straight reel.
- [ ] The kick on arrival: do you top out onto ledges, or slam into the rock
  under them? That is `Launch` (32) and `Carry` (0.45) in `StrataConfig.Grapple`.
- [ ] Is 5.5 seconds of cooldown too long in a 150-stud hall?
- [ ] Is 190 studs of range enough to cross a big chamber?
- [ ] Does the reticle tell you what you need? Lit means reachable.
- [ ] Does it ever drag you into a wall and hold you there? There is a 4-second
  hard stop, so the worst case is a wait, but I want to know if it happens.
- [ ] **Frames.** The headlamp casts shadows, which in Future lighting is the
  expensive kind of light and it moves every frame. If a big hall drops frames,
  this is the first suspect — `Headlamp.Shadows` in the config.

## 13. From the screenshot

Things I could only see from the picture:

- [ ] **Huge red and green washes with hard diagonal edges.** Those are single
  PointLights with very large Range painting flat colour across the terrain.
  This is the real shape of "too bright and lumen" — not brightness so much as
  a few enormous lights doing the work of many small ones.
- [ ] **The terrain is smooth rounded blobs.** No stalagmites, no shelves, no
  small rock. §7 of the brief is right and this is the next environment job.
- [x] Character was a pure black silhouette — confirms the headlamp.
- [x] Player list sitting on the run card — fixed.
- [ ] The cyan objective arrow is very large and sits mid-screen.

---

## 14. Reading the cave — the palette pass

From the three in-game shots against the Deep Rock reference. The complaint was
"too blind, no vision" and "hard to unpack what's going on", and the cause was
the opposite of what it sounds like: not too bright, **too black, with a few
things screaming in it**.

- [x] **The water was a sphere.** `FillBall` with Water, sunk at 0.45 of its own
  radius, so well over half the ball stood proud of the floor — in the master
  cavern that was a dome of green water up to 90 studs across sitting in the
  room. Terrain water does not settle; it is voxels. It is a cylinder with its
  top at floor level now, capped at 34 studs across.
- [x] **Your own lamp was dyeing the cave red.** PackLight level one, "Ember",
  was `(255, 78, 62)` — saturated red. Every surface the beam touched came back
  red, the archetype lights came back green, and the two together are the muddy
  wash in all three shots. The ladder still runs warm to cool, but every step is
  now close enough to white to show the rock its own colour.
- [x] **Ambient was too black to read.** At 5 units, anything not emissive simply
  stopped existing — which is why glowing mushroom caps appear to hang in space
  with no stems. Raised to a cool 18/22/32. Dark, but the rock has shape again.
- [x] **Bloom was making halos.** The surface value over a cave full of neon
  props turns every prop into a smear. Underground it drops to 0.2 with the
  threshold nearly doubled, so only genuinely bright things bloom.
- [x] **Four colour families at once.** Each layer tinted the air with its own
  rock colour, on top of the archetype lights and the lamp. Layer air is now
  pulled 62% toward one cool base, so a layer is a variation rather than a
  separate palette. Fewer props carry lights (34% → 22%) and dimmer.
- [x] **Map labels piled up.** "DEEP STOPE" over "BLACK CHAMBER" over "STILL
  STOPE". Names now sit radially outward from the map centre, and anything still
  overlapping is nudged down until it is not. The master cavern draws as an
  outline instead of a filled circle, because a filled circle containing every
  other circle is not information.

- [ ] **Does it read now?** The target is the reference: dark, cool, legible
  everywhere, with colour coming from a few small accents rather than from
  floodlights. If it is now too dark to play rather than too muddy, the number
  is `Look.Cave.Ambient`.
- [ ] Still outstanding from these shots: props sitting half-inside terrain.
  Raising the ambient should show whether they were ever floating or just
  unlit — I could not tell which from the picture.
