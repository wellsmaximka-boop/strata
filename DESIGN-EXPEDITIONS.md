# Strata — Expeditions

Design for the run loop, the collapse system, and the construction sink.
Written 2026-09-13. Numbers in here are measured against the live config, not
guessed — the simulations live in the scratchpad and can be re-run when the
config changes.

---

## 1. The problem this solves

Strata's economy is a closed rate ladder. Ore buys a better pick, a better pick
mines more ore. Every reward's only purpose is to increase the rate of the same
activity, so the top of the ladder is *"I can mine anything"* — which is the
same as being finished. There is no terminal sink: nothing you spend on that
isn't about mining more.

Three things fix it, and they fix different halves of the problem:

| | What it fixes |
|---|---|
| **Runs** | A session has no shape. Now it has a start, a stake and an end. |
| **Collapse** | Being good means being safe. Now it means being fast under risk. |
| **Construction** | Ore has nowhere to go. Now it builds the way down. |

Free-roam mining stays exactly as it is. Contracts are a board at the camp, not
a replacement — if runs don't feel good, we've lost a board.

---

## 2. The run

### Dig to discover, lift to return

A layer is not a lift destination until you have stood in it. The first time you
reach the Magma Vents it is because you dug there. After that it unlocks as a
destination forever.

This keeps first contact as a discovery rather than a menu click, and it gives
the `???` rows on the depth chart a job: you cannot take a contract to a place
you have never seen.

### Shape of a run

1. Take a contract at the camp — layer, duration, objective, payout
2. The lift drops you into that layer
3. Dig, find chambers, fill the pack, decide what is worth a slot
4. The chambers you strip get unstable
5. Get back to the lift before the clock
6. Raw ore banks, the contract pays, materials go to the build site

### Raw ore

Everything mined during a run goes into a **run manifest**, not your inventory.
It banks when you extract. Fail — clock out, or buried — and **40%** of the
manifest survives and the contract bonus is lost.

This is deliberately gentler than DRG. Total loss reads as punishment in a
simulator; a partial haul reads as a bad day.

### Contract types

Ship the first two. The others reuse the same machinery.

| Type | Objective | Why it exists |
|---|---|---|
| **Haul** | Bring back N of a named ore | The baseline. Teaches the loop. |
| **Survey** | Reach a named cavern archetype and take something from it | Makes the archetype system matter and sends you looking rather than digging down. |
| **Deep Core** | Reach a set depth, longer clock, bigger payout | Later. Uses depth as the objective. |
| **Salvage** | A chamber that starts already unstable | Later. Pure nerve. |

### Durations

Measured strip times for one chamber, for a miner with power 60 and a 130 pack:

| Layer | Chamber radius | Nodes | Value | Time to strip |
|---|---|---|---|---|
| Topsoil | ~19 | 73 | 4,100 | 1.5 min |
| Stonebed | ~28 | 251 | 26,200 | 5.9 min |
| Magma Vents | ~38 | 643 | 279,000 | 24.5 min |

So contract clocks should be:

- **Topsoil — 5 minutes.** Several chambers per run.
- **Stonebed — 8 minutes.** One chamber and a bit.
- **Magma Vents — 10 minutes.** A fraction of one chamber. You will leave things behind, and that is the point.

---

## 3. Collapse — the replacement for monsters

The mine is the antagonist. Not because enemies are impossible, but because
instability is better design for *this* game:

- It is pure terrain and geometry. No AI, no pathfinding through voxels the
  player is actively destroying, no models, no animation. It stays inside the
  no-modelling constraint the project was built around.
- It is caused by the player. A spawner is something that happens *to* you; a
  collapse is a bill for your own greed.
- **It scales the right way.** A timer gets easier as you get better. Collapse
  gets worse, because being better means taking more.

### The rule: pace, not total

The first model drained stability by total digs taken. That punished big
chambers hardest, which is backwards — the pack already stops you emptying one.

What should bite is *hammering one spot*. So stability drains per dig and knits
back together over time. Greed becomes a question of pace, and the answer is to
keep moving.

```
stability starts at 1.0
each dig in a chamber:   -0.0152 / sqrt(radius)
each ore node broken:    x3 that
recovery:                +0.004 per second
```

### What that produces

| Radius | Cost per dig | Sustainable rate | Duty cycle | Flat out, collapses in | Digs taken |
|---|---|---|---|---|---|
| 16 | 0.0038 | 0.63/s | 18% | 54 s | 192 |
| 24 | 0.0031 | 0.77/s | 22% | 69 s | 247 |
| 32 | 0.0027 | 0.89/s | 25% | 83 s | 298 |
| 40 | 0.0024 | 1.00/s | 28% | 97 s | 347 |
| 52 | 0.0021 | 1.14/s | 32% | 117 s | 418 |
| 60 | 0.0020 | 1.22/s | 34% | 130 s | 465 |

**The ratio that matters:** a full pack is about 520 digs — 2.4 minutes of solid
work. Every chamber comes down before that. *You cannot fill your pack from one
chamber.* You have to move, and every chamber is a fresh "how much do I dare"
decision.

Pace yourself to roughly a quarter duty cycle and you can stay indefinitely —
but you will be slow, and the clock is running.

### Thresholds

| Stability | What happens |
|---|---|
| 0.65 | Dust falls, the rock creaks. A warning you can ignore. |
| 0.40 | Small debris, screen shake. |
| 0.20 | Rockfall. Real damage if you stay. |
| 0.00 | Collapse. Terrain fills, the chamber closes, heavy damage inside it. |

A collapsed chamber stays collapsed for the session. Its ore is gone.

---

## 4. Construction — what the ore is for

### The finding that shapes this

A single Stonebed chamber is worth ~26,000 credits. A Magma chamber ~279,000. A
Cinder Cathedral ~974,000. The most expensive item in the game costs **1,800**.

The economy has no top end. So construction is denominated in **materials, not
credits**, and it is priced in dozens of runs rather than a few.

### The way down

The depth chart already has three layers marked `???`. Make them *sealed*, and
make opening each one a build the whole claim can see.

| Layer | Build | Roughly |
|---|---|---|
| Frostline (−500) | **Cooling Plant** | 5 stages, Stonebed and Magma ore |
| The Crush (−1000) | **Pressure Lock** | 6 stages, Frostline ore |
| The Null (−1800) | unnamed | later |

Each stage consumes a bundle of materials and the structure visibly grows at the
camp — procedural parts, nothing to model. **Completed stages give permanent
claim-wide buffs** (pack capacity, light, walk speed) so progress is felt long
before the layer opens.

The punchline: the mine goes down forever, and you are the one opening it.

### Side effect worth taking

Gear costs should rise to match. Late pickaxes and armour at 1,800 credits are
free money once you have seen one Magma chamber.

---

## 5. Build order

1. **Run state machine** — contracts, timer, raw manifest, extraction, failure.
   No collapse yet. Mostly state and UI; reuses the lift.
2. **Collapse** — stability field, thresholds, terrain fill, damage.
3. **Construction site** — stages, costs, the structure that grows, buffs.
4. **Frostline** — a real fourth layer, opened by the first build.

Each step is playable on its own. Step 1 is a game with runs in it. Step 2 is
the game this document is about.

---

## 6. The descent — built

Signing for a contract is not a teleport. There is a real bore down the middle
of the claim and a cage that runs in it, and you stand in the cage while the
layers go past.

### The bore

Carved by the same voxel function that writes the rest of the mine — one extra
condition per voxel, 0.08 ms per chunk, and only chunks within 27 studs of the
axis pay it at all. Eleven studs of radius inside a shaft mouth thirteen wide,
so the terrain runs to the lodge floor and stops under the grate.

**It only runs as deep as the crew has been.** The floor of the bore follows the
deepest layer anybody on the server has stood in. Somebody breaking into the
Magma Vents for the first time lengthens the shaft for everyone — chunks written
after that carve themselves, and the ones already written are opened directly
with `FillCylinder`. Look down the shaft from the camp and its bottom is the
bottom of what has been found.

Terrain is shared, so this is per-server rather than per-player. The per-player
version of the same idea is already the contract board: you cannot sign for a
layer you have never stood in.

### Stations

A chamber cut into the rock at `stratum.top − 24`, eased at roof and floor so it
reads as a room rather than a tin, with a steel floor ring, hazard edging, a lamp
and the layer's name on a plate. Eleven studs of opening at the roof, twenty-seven
at the middle.

| Layer | Station | Cage deck | Down | Up |
|---|---|---|---|---|
| Topsoil | −56 | −70.6 | 6.7 s | 4.2 s |
| Stonebed | −265 | −279.6 | 11.3 s | 7.0 s |
| Magma Vents | −610 | −624.6 | 18.0 s | 11.2 s |

Ride length is a fixed cost plus a rate, clamped at both ends: two seconds to
the Topsoil would read as a teleport with a wipe over it, and nobody wants to
stand still for more than about a quarter of a minute. Coming up is 62% of going
down — the tension is already spent.

### The grate

Two halves over the shaft mouth in the lodge floor. They are the reason the bore
can be a real hole: with them shut the lodge floor is a floor, and they only come
apart when there is a cage to step into. They shut again once the cage is
twenty-six studs down.

### The cage

Built per rider and thrown away after, so two people can be in the shaft at once
without sharing a lift. Three walls of bars, one open face, a gate that rises
into a housing on the roof, and — the piece the whole ride is built around — a
**gauge across the top of the open face, tipped down at the rider**, counting
metres and naming the layer you are in. The same numbers are on screen; the
board is the one you actually watch.

### The clock

Starts when the gate opens at the bottom, not when you sign. Charging you for
the ride would make the deepest contract the one you are least able to finish.
Extraction stops it the moment the cage takes you, for the same reason in
reverse.

### Smoothness

The server owns where the cage is; the client runs the same easing curve on the
same numbers and writes the CFrame every frame. An anchored part driven from the
server replicates as a property change every few frames, which over two hundred
studs is a stutter. Both agree at both ends, which is the only place agreement
matters — the payload carries `hold`, `seconds`, `fromY` and `toY` so it can.

### Camera

Scriptable for the whole ride rather than handed back after an opening swoop.
Half a cutscene is worse than none: the moment control comes back people look at
the floor and miss the Stonebed going past. Three-quarters behind the rider at
the start, drifting square on to the gate by the time it opens, every offset kept
inside ten studs of the axis because the bore wall is at eleven.

### What it falls back to

`ExpeditionService` asks for a ride through `_G.StrataDescent` and drops back to
the old teleport if that file failed to start. A descent that fails is still a
contract that starts.

---

## 7. The dig site — built

A contract does not drop you into generic rock any more. It cuts a map.

### Shape

A hub, drifts, and halls. The hub is the landing station already cut by the
bore; three drifts leave it on their own bearings, and two to four more halls
hang off *those*, so the site is a tree rather than a star. That is the
difference between a map you read and a corridor you walk: there is a near ring
you clear quickly and a far one you have to decide whether the clock allows.

Halls are named, not numbered — the Low Crosscut, the Quiet Bench — because "go
back to the Quiet Bench" is an instruction and "go back to chamber 4" is a
chore. The last one placed is always the **vault**: bigger, further, and given
the rarest archetype the layer can hold.

Everything derives from one number. The server that carves the rock, the
decorator that furnishes it and the client that draws the map all run the same
layout off the same seed, so nothing crosses the wire but the plan itself, once.

### What the layers can hold

The constraint that shapes everything is vertical. A hall is kept inside its own
layer — not for tidiness, but because the ore table, the depth banner and the
hazard gates all read the layer off your Y, so a Topsoil hall with its floor in
the Stonebed is a Topsoil contract handing out Stonebed ore in a room the HUD
calls by the wrong name.

So halls flatten to fit. The same floor plan, pressed down into whatever the
layer will take:

| Layer | Usable depth | Halls | Biggest |
|---|---|---|---|
| Topsoil | 132 studs | 5–7 | 161 across × 122 tall |
| Stonebed | 288 studs | 5–7 | 224 across × 170 tall |
| Magma Vents | 488 studs | 5–7 | 224 across × 170 tall |

Reach is 250–320 studs from the station and 650–1000 studs of drift to walk.
Across 1,200 generated sites: never fewer than five halls, never one outside its
layer, and one overlapping pair.

### Carving

Three passes, in this order and no other:

1. **ensure** — deep rock is written on demand, so anything carved into a chunk
   that has not been written yet gets filled straight back in the moment a
   player walks near it. Every chunk the site touches is written first, nearest
   hall outwards.
2. **lining** — every hall and tunnel filled *solid*, a few studs oversize, with
   its archetype's own material.
3. **air** — and then hollowed out. What is left between the two is a shell of
   the room's own rock, which is what gives a Crystal Vault walls that look like
   a Crystal Vault.

The passes are global rather than per-hall. One hall at a time would mean the
second hall's lining plugging the first hall's air wherever they come close —
which, given halls are now held closer than their radii together, is most of
the time.

Then terraces are dropped back in as solid slabs, and the last few studs of
every tunnel are cut *again*, because a terrace across the mouth of a drift is a
hall you cannot enter.

**Blobs are true spheres.** The only tool for carving terrain in bulk is a ball,
so a flat hall is many small spheres laid across a disc rather than one squashed
one — ring spacing derived from the sphere size, so coverage and connectivity
are guaranteed instead of hoped for. The Topsoil gets two dozen small spheres,
the Magma Vents four big ones, from the same four lines of code. Measured over
360 halls: no sealed pockets. Tunnels the same: point spacing comes from the
tunnel's own width, never more than 0.87 of a diameter, zero breaks in 58,672
segments.

Cost per site: ~380 `FillBall` calls, 0.7–1.2M voxels, ~50 `ensure` calls.
All of it runs while you are in the cage.

### The timing

This is the second reason the descent exists. A sixteen-second ride down to the
Magma Vents is the loading screen for the map waiting at the bottom of it, and
the halls are carved nearest-first so the ones you can reach in the first twenty
seconds are the ones that exist first.

### Finding your way

Every drift is strung with lamps in the colour of the hall it leads to, and
every drift off the station carries a board with that hall's name. Picking a
tunnel is a decision you can actually make, and getting back is following the
lights the other way.

The **site map** is bottom of the right-hand column, `M` to open it full-screen.
It reveals rather than shows: halls you have not walked into are outlines, and
walking into one fills it in and names it. North stays up — a map that rotates
with you is easier to walk by and impossible to remember, and remembering where
the vault was is the thing you are actually doing. Nothing about it is sent per
frame; the server hands over the plan once and everything after that is worked
out locally from your own position.

### What is in them

Site walls carry **1.5× the ore** of ordinary rock, on top of the archetype's
own bonus, and the archetype exclusives turn up there — which is the argument
for taking a contract instead of digging a hole of your own.

Halls are furnished by the existing cavern decorator with nothing added to it.
A chamber is deliberately shaped like a cavern room — key, centre, radius,
archetype — so spikes, crystals, fungus, boulders and lava and water pools turn
up in a contract's map for free.

### The third contract type

`EXTRACT` joins haul and survey, and it is the one the map exists for: three to
five **deposits**, one per hall, far ones first, each a glowing cluster you
break with the ordinary pick. You cannot have them all without walking the site.
Markers are visible through rock out to 260 studs, which is how you decide which
hall to clear next; the alternative is wandering.

Difficulty scales deposits far more gently than an ore quota — one more deposit
is another hall to walk to, not another minute of mining — so the hard tiers
bite through the clock rather than through the count.

### What stays behind

The lamps, the signs and the deposits go with the contract. **The rock stays.**
A worked-out dig site is somewhere you can come back to and mine on your own
time, and a layer slowly filling with them is the mine having a history.

---

## 8. Making it a cave — built

The first dig sites read as rooms on corridors. Four changes, in order of how
much they mattered.

### The layers are three times thicker

Everything downstream of this was constrained by it. The Topsoil was fifty studs
deep, which is not enough to stand a cave up in — so halls flattened to 28 studs
tall and the whole site read as a crawl.

| Layer | Was | Now | Thickness |
|---|---|---|---|
| Topsoil | 0 → −50 | 0 → −160 | 160 |
| Stonebed | −50 → −200 | −160 → −460 | 300 |
| Magma Vents | −200 → −496 | −460 → −960 | 500 |

Frostline, The Crush and The Null moved to −960, −1600 and −2600 to follow. The
hazard gate and the lift stops are **derived from the strata now** rather than
carrying their own copies of the old numbers, which is how they would otherwise
have ended up pointing at rock that had moved.

### The station sits *inside* its layer

`LandingDrop` was a flat 24 studs below a layer's roof. In a five-hundred-stud
layer that puts the station in the ceiling and every hall a hundred and fifty
studs below the place you arrive at. It is a share of the layer now — 35%,
clamped to 30–150 — so the cage puts you down in the middle of the workings.

Ride times were retuned to keep the same shape against the much longer drop:
**6.7 s / 11.3 s / 18 s**.

### Halls are three times the size, and full of things

| | Was | Now |
|---|---|---|
| Biggest hall | 160 × 110 | 224 × 170 |
| Gallery width | 20 across | 36 across |
| Separation | 92% of radii | 72% — halls **overlap** |

Separation is the one that changes the feel. Under 1 the halls run into each
other, so a site reads as one cave system with lobes rather than rooms joined by
corridors, and you can see from one hall into the next.

And four kinds of relief, all the same trick — put rock back after the air is
carved, or take more away:

- **Pillars**, 3–7 a hall, floor to ceiling. The single biggest thing for scale:
  you cannot judge how big a space is until something in it blocks your view of
  the far side.
- **Terraces**, 3–6, stepped floors rather than a flat pan.
- **Alcoves**, 5–10, pockets bitten out past the wall. This is the perimeter
  detail — without it a hall is a clean sphere and reads as a room.
- **Pits**, 1–3, holes in the floor deep enough that you cannot see the bottom
  from the rim, half of them two spheres deep.

Alcoves and pits **hang off a sphere that is already part of the hall**, pushed
out by less than the two radii together. Placing them at an absolute distance
left some floating in the rock as sealed pockets — visible on the map and
impossible to reach.

Decor scales with the hall now (8–46 props, was 6–26) and its ground-finding
casts start from half the hall's *height* rather than half its width, which in a
flattened hall was above the roof.

### The seam

> *"how do you make it so people only stay within that actual layer"*

A contract is for one layer, and while you are on one the seams above and below
it **will not break**. It is a rule about the contract, not about the rock — off
a contract the whole mine is yours to dig through exactly as before. Two
translucent sheets are built at the layer's boundaries so the wall is visible,
because a wall you cannot see is a wall players report as a bug.

The site generator already kept halls inside their layer. This closes the other
half: you cannot tunnel out of one.

---

## 9. Flares — built

Three, thrown by hand, one back every thirty seconds.

They exist because the halls got big. A pack light follows you around and lights
whatever you are already looking at, which is exactly the wrong tool for a
two-hundred-stud room with pits in the floor and alcoves round the walls. A
flare is light you **place**, and placing it is a decision: into the pit, across
the hall, or back down the gallery you came in by so you can find it again with
a full pack and forty seconds left.

### The arc is the feature

Hold `F` and a dotted line appears. It is **simulated forward under the same
gravity the flare will fall under**, and raycast segment by segment so it stops
at the first thing it would hit — which means the ring at the end of it is where
the flare lands, not where it would land in a vacuum. The dots fade along their
length so the near end reads as *now* and the far end as *maybe*.

Hold longer to throw further: 70 to 205 studs per second over 1.05 seconds, with
a power bar above the slot and the bar turning red at full. The lift is added on
both ends, so the arc the client drew and the throw the server makes are the
same throw.

### The pack

One charge back at a time rather than the whole set at once — getting all three
together would make it a thing you empty and then wait on; one at a time makes
it a thing you spend. The slot sits directly above the hotbar in the same
chrome, three pips, with the one refilling drawn over its own pip and the
countdown ticking locally between pushes.

Charges are spent client-side the moment you throw. Waiting for the server to
confirm makes a thrown flare feel like a request rather than an action, and the
next push corrects it either way.

Flares only exist underground: above ground there is nothing to light and a
thrown one is litter on the camp deck.

---

## 10. Station gates, signposting and the restyle — built

### The shaft was a ladder out of your layer

The bore runs past every station down to the deepest one anybody has found. The
cage set you down at the Topsoil and then dropped away, leaving you on the lip
of an open five-hundred-stud hole to the Magma Vents — a contract for one layer
with a way out of it.

Every station has the plug the camp deck has now: **shut by default, open only
for the width of a cage going past, shut again the moment it has.** The cage is
the only thing that ever moves through the shaft.

It shuts as soon as the cage *parks*, not once the cage has faded. The cage
floor is square and the station ring is round, so there is a three-stud gap
between them on each axis — open, that is a hole you can step through on your
way off the lift.

### Fewer holes, bigger ones

| | Was | Now |
|---|---|---|
| Alcoves a hall | 5–10 | **2–4** |
| Alcove size | 16–34% of radius | **30–50%** |
| Pits a hall | 1–3 | **0–2** |
| Pit size | 18–34% | **30–48%** |

Ten small bites out of a wall is noise you walk past; three wide ones are bays
you walk *into*. Spheres per hall dropped from 14.5 to 8.6 and the halls read as
more open, not less — which is the point.

### Signposting

Three things, all off the one plan the server already sends:

- **An arrow.** A chevron lying flat on the floor a few studs ahead of you,
  pointing at whatever you should be doing right now. Straight out of BioShock,
  and for the same reason: a map says where things *are*, an arrow says where to
  *go*, and in a cave with six mouths off it those are not the same question. It
  hides once you are within eighteen studs, because an arrow still pointing when
  you have arrived is an arrow people stop believing.
- **A waypoint** on the target, readable through rock, with the distance on it.
  "The vault" means nothing; "the vault, 210 m" is a decision.
- **A banner** across the top naming the job, because a quota in small type
  inside a card in a corner is a quota nobody reads.

All three answer to one function:

| Situation | Points at |
|---|---|
| Objective met, or under 45 s left | the cage |
| `EXTRACT`, deposits left | the nearest deposit |
| `SURVEY` | the vault |
| `HAUL` | the nearest hall you have not been in |

The clock is counted down locally between pushes, so "time is short" flips the
arrow on the second it becomes true rather than on the next ore you pick up.

### Colour is the map's language

A hall is painted for what it *is* — its archetype's own colour, the vault
always violet with a diamond on it — filled in when you have walked into it and
a dim outline when you have not. Three glances tell you the vault from the
ordinary workings without a legend.

### The restyle

> *"the grey makes people know its AI which is fine, but the UI is bland"*

Fair. The old palette was cut stone: warm greys, a granite speckle, one amber
accent. Read back, it was simply grey — and grey with a thin outline and a thin
font is the look of a placeholder, whoever made it.

Three rules now, taken off the games this is trying to sit next to:

1. **The dark is not grey.** It is a near-black with blue and violet in it, so
   every accent laid on it reads as *lit* rather than as painted.
2. **Accents are saturated to the point of being loud.** A muted accent on a
   dark panel is a smudge; the whole job of an accent is to be the thing your
   eye goes to first. Gold went `(232,176,96)` → `(255,186,56)`, and Violet,
   Rose and Sky joined it.
3. **Everything has a heavy black outline** — panels at 4px, and *the text
   itself* through a `UIStroke` in every label helper. That single change does
   more than any colour: it is what makes a flat rectangle read as an object.

Type is three faces and no more: **Fredoka One** for anything short — headings,
labels, buttons, quantities — Gotham for prose, because a paragraph set in a
poster face is a paragraph nobody reads, and Code for anything that counts,
because a monospaced digit is the only way a running timer does not jitter.

Panels gained a lit top gradient, a drop shadow and a coloured header bar. Every
panel in the references has a header bar and it is most of why they read as
objects rather than as rectangles with text on them.

None of this is typed twice. The palette, the three fonts and the chrome numbers
(outline, corner, text edge, shadow) all live in `StrataConfig.UI`, and every
client file reads them — so the next change of mind about the colour of a panel
is one line.

---

## 11. The inventory screens — built

Look at any of the references — the unit grids, the pet inventories, the card
collections — and it is the same five pieces every time:

- a **ribbon**: the screen's name on a plate that overhangs the panel's corner
- a **tile**: a square card whose *whole body* is the rarity colour
- a **detail pane**: the selected thing, big, down the right
- **chunky bars**: fat saturated buttons with black edges
- a **red X**, overhanging the opposite corner

The thing that makes them read as one family is that **the rarity colour is not
an accent on the card, it *is* the card.** A grey card with a coloured edge is a
list row. A card that is entirely gold is a legendary.

### The rarity ladder

The six-step ladder the genre uses, because using it means a player knows what a
card is worth before reading a word of it. Nothing *stores* a rarity — it is
derived from what an ore sells for and what tier a piece of gear is, so adding
either puts it on the ladder automatically and there is no second table to keep
in step.

| | Ores | Gear |
|---|---|---|
| Common | 2 | — |
| Uncommon | 1 | 5 |
| Rare | 5 | 5 |
| Epic | 4 | 1 |
| Legendary | 2 | 1 |
| Mythic | 1 | — |

Gear starts one rung up: Common is kept for loose rock, because a starter helmet
painted the same grey as the gravel in your pack is a starter helmet nobody
feels good about buying.

### The tile

118 × 136, the rarity colour washing up the body strongest at the top, a level
badge in one corner, a mark in the other, the art floating on the colour rather
than sunk in a well, and a dark name plate across the bottom carrying the name
and one line underneath — a price in a shop, a count in a pack, the rarity in a
collection.

**Two rings, not one**: the rarity colour inside and black outside. That is what
stops a bright card bleeding into the dark panel behind it. Tiles lift and
thicken their edge on hover.

Dimmed rather than hidden when you cannot have it: a greyed card still says the
thing exists, which is most of why a shop is worth looking at.

### Clicking selects; the pane acts

Clicking a card no longer buys it. It fills the pane on the right — the thing
big, its rarity named in its own colour, its stats in rows — and *that* grows
the button. It is what the references do and it is the end of misclicking a
purchase you meant to read first.

### One call site, five screens

Every screen still calls `card(order, spec)` with the table it always passed.
The keys are mapped onto a tile in one place rather than at five call sites,
which is why the shop, the pick works, the depot and the forge all changed shape
at once — and why the contract board, which has its own wide-row builder, did
not. The grid makes room for the detail pane with padding rather than by
resizing, so the board and the depth chart go on working without knowing the
pane exists.

### `UIKit`

All of it lives in `src/shared/UIKit.lua` — ribbon, tile, detail pane, chunky
button, close, search — building instances and nothing else: no state, no
knowledge of the game, every function returning what it made.

Being a module is also what made it fit. `SurfaceUI` runs a handful of locals
under Luau's limit of two hundred per chunk, so the three new blocks are wrapped
in IIFEs and each requires the kit for itself. A `do` block would not have done:
a block's locals still coexist with the outer ones and the peak is unchanged.

### The chip row

The vertical icon rail from the references did **not** get built, and neither
did search. The rail switches slices of one screen — but the bottom button bar
already switches screens and the right edge is now the detail pane, so a rail
there would be a second navigation arguing with the first. Search over eleven
shop items and sixteen kinds of rock is chrome.

What both are *for* is worth having, so it is a row of chips under the ribbon
instead:

- **Shop** — ALL / HEAD / BODY / LEGS / TOOLS. Six tiles on ALL, two on HEAD.
- **Depot** — WORTH / EACH / COUNT / NAME. Sorting is the one place this earns
  its keep: with sixteen kinds of rock and a capacity you are always up against,
  "what do I dump first" is a real question and value-per-unit answers it.

The row owns which chip is live, so no screen needs a variable to remember. It
does **not** forget on hide — a screen rebuilding itself to apply the chip you
just clicked goes through the hide path first, and clearing there meant the
filter never took. Switching screens resets it anyway, because `Set` falls back
to the first option whenever the id it is holding is not one the new screen
offers.

Everything the panel wears around its grid — chips, detail pane, and the padding
that makes room for both — is one handle rather than five locals. That is not
tidiness: this file runs a handful of locals under Luau's limit of two hundred,
and the first attempt at the chip row overflowed it twice.
