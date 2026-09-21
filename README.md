# Strata — Phases 1 & 2

Underground mining game. Phase 1 proved the feel; Phase 2 closes the economic
loop: **dig → carry → sell → forge → survive deeper.**

Design doc: https://claude.ai/code/artifact/f0121dc2-e76b-4774-9844-b7be5f8296ad

## What's in

**Phase 1 — the mine**
- Three generated strata (Topsoil / Stonebed / Magma Vents) down to −512
- Server-authoritative digging with distance and rate validation
- The scanner: direction + distance band + signature class, never coordinates
- Ore nodes derived deterministically from the world seed, exposed when uncovered
- Procedural crystal models — no meshes anywhere in the project
- Feel package: debris, pickaxe swing on the shoulder Motor6D, camera kick,
  ore pop-in and collect flight, scanner pulse

**Phase 2 — the loop**
- Per-ore inventory with capacity, replacing the flat counter
- Sell pad that empties the pack automatically when you stand on it
- Forge with four gear pieces: lamp, pack, tuned scanner, thermal plating
- Resistances as keys — the Magma Vents below −200 damage you without heat gear
- Lift that bores a pocket at the destination so it can never strand you in rock
- Gear grants stack, so scanner range and cooldown improve with what you own

**Strength — the mining spine**
- Every stratum has a `hardness`; rock you lack the power for does not break
- Strength is earned *by mining* (+1 topsoil, +3 stonebed, +9 magma)
- **Mining power = strength + best pickaxe + armour set bonus**
- The dig cursor turns amber on rock that's too hard, before you click
- Pick Works: a fourth station selling Iron / Tempered / Thermal picks
- Ore now skews richer with depth (`tierBias`), so descending pays in material
  as well as strength

## Two gates, on purpose

**Strength** asks whether you can break the rock. **Armour** asks whether you
survive standing there. They're earned from different places, and whichever one
is blocking tells you exactly what to go do.

## What's deliberately out

Anomaly biomes, server events and announcements, the collection log, trading,
persistence, rebirth. All Phase 3+.

**Credits and gear do not save yet** — every session starts from zero. That's
by design for now (persistence is Phase 4 in the doc), but it makes testing
progression tedious. Say the word and it's a small DataStore layer behind
`PlayerState.Load/Save` with no caller changes.

## Running it

1. Open Roblox Studio, create a new **baseplate** place and delete the baseplate part
2. From this folder: `rojo.exe serve`
3. In Studio, install the Rojo plugin if you haven't, then **Connect**
4. Press Play

The mine writes at server start — expect a few seconds and a
`[MineGenerator] mine written in …` line in the output before digging works.

## Controls

| Input | Action |
|---|---|
| Hold **LMB** | Dig at the cursor |
| **E** | Scanner sweep |
| Button, top right | Return to surface |

Step off the spawn pad before digging — the pad is a normal part, so the
cursor lands on it rather than on terrain.

## Tuning

Every number lives in `src/shared/StrataConfig.lua`. Nothing else holds a
magic constant. The three worth playing with first:

- **`Dig.Radius`** (5.0) — terrain resolves at 4 studs, so anything under ~4
  barely removes material. This is the chunkiness dial.
- **`Dig.Cooldown`** (0.28) — how fast the tunnel advances.
- **`Scanner.Cooldown`** (2.4) — **the single most important number in the
  game.** Every sweep is a roll. If this feels slow, the whole design feels
  slow. Try 1.5 and 4.0 to find the edges before settling.

Then `Nodes.CellSize` and the per-stratum `nodeDensity` for how often you hit
something, and the `Ores` weights for the rarity curve.

## Sound

`SOUND_IDS` at the top of `src/client/MineClient.client.lua` is empty and the
code no-ops without it. The scanner ping matters most — it's the core feedback
loop, and the pitch already rises with signal strength once an id is in place.
Creator Store ids drop straight in.

## Known costs

- **Generation** is a Lua loop over ~540k voxels. It yields between chunks so
  the server stays responsive, but the mine doesn't exist instantly.
- **Node exposure** does one `ReadVoxels` per player every 0.45s over a 44-stud
  cube. Fine for a playtest; needs revisiting before a full server.
- **Terrain replication** is the scaling risk. Every carve goes server → all
  clients. Untested above a handful of players.
- `StreamingEnabled` is **off**. Streaming fights terrain digging, and turning
  it on is a Phase 3 problem.
