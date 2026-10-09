# Movement

The grapple and the momentum system. Every number named here lives in
`StrataConfig.Grapple` and nothing is hardcoded at a call site.

## Controls

| Input | Does |
| --- | --- |
| `Q` | Fire the hook at whatever the crosshair is lit on |
| `Q` again, or `G` | Let go, keeping all your speed |
| `W` | Climb the cable toward the anchor |
| `S` | Feed the cable back out |
| `A` / `D` | Steer the swing |
| `Space` | Jump, as it always did |
| `Shift` | Sprint, as it always did |

Fire is **not** the left mouse button, which is where the brief put it. The left
button is the pickaxe and mining is hold-to-swing, so every swing at a wall
would have thrown a hook at it. Right click is the camera. `Q` was already the
grapple key and `G` was free.

The hook only works underground, more than `MinDepth` below the surface. That is
also what stops it being a way off the camp deck.

## The pieces

| File | Owns |
| --- | --- |
| `client/GrappleClient.client.lua` | Input, aiming, the slot UI, the camera, other players' cables |
| `client/movement/GrappleRig.lua` | One hook: the anchor part, the `RopeConstraint`, the length |
| `client/movement/Momentum.lua` | Every force on the character — reel, steering, landing |
| `client/movement/RopeView.lua` | The cable you can see |
| `server/GrappleService.server.lua` | Cooldown, validation, and telling everyone else |

Two rules hold it together. **`Momentum` is the only thing that writes a force
to the character**, because two scripts pushing one body is a fight you cannot
tune your way out of. And **nothing writes `WalkSpeed`** — `PlayerState` owns it
and the sprint code reads it, so a third writer would be a bug with three
authors. Forces add on top of all of it and need nobody's permission.

### Why a RopeConstraint

It is a hard distance limit that pulls and cannot push, which is what a rope is.
Below the limit you are in free fall and the rope is not there; at the limit you
are on a pendulum, solved by Roblox against your real mass and real velocity. So
swinging, accelerating out of the bottom of an arc, and keeping every bit of
that speed when you let go are not features anybody wrote. They are what the
constraint already does. Releasing is `rig:Destroy()` and nothing else: there is
no velocity to hand back because it was never taken away.

A `SpringConstraint` oscillates, which is the bounce to avoid. `AlignPosition`
chases a target, which is the magnetic pull to avoid. Writing velocity every
frame — which is what this replaced — throws away the momentum it is supposed to
be preserving, every frame, by definition.

### The ratchet

The one idea that makes it stable. **Reeling is a force, never a shortening.**
Winching a hard constraint shorter than the player actually is hauls them along
it inside one frame, and that haul is the snapping every grapple system gets
accused of. So the force closes the gap and `Length` follows along behind it,
never set shorter than the real distance. There is no frame on which the rope
has to move anyone; it only ever stops them.

And it only follows *while reeling*. Doing it always is a mistake that looks
subtle and feels terrible: on the slack side of a swing you are closer to the
anchor than the rope is long, so the limit would quietly shrink to meet you and
you could never swing back out.

## Testing it, in order

Do these in sequence. Each one depends on the last working.

**1 — Fire, attach, cable.** Drop into a run, get below the surface, look at
rock. The crosshair turns green when it is in range and grey when it is not.
Press `Q`: a cable appears and the slot reads a length in metres instead of
READY. Aim past 190 studs, or at a deposit, and the crosshair stays grey and `Q`
does nothing. Press `Q` again and the cable goes away.

**2 — Swing.** Hook a ceiling well ahead of you and do not touch anything. You
should fall, the rope should go taut, and you should swing through the bottom of
the arc and up the far side. Hold `W` and you climb; hold `S` and you drop away.
Nothing should jitter, snap, or vibrate at full extension. If it does, that is
the ratchet and the note above says where to look.

**3 — Momentum.** Swing forward, release at the front of the arc, and you should
fly. Steer the flight with `WASD`. Land fast and you should slide out of it
rather than stopping dead. Then jump, hook, release, and hook again without
touching the ground — the 0.6s cooldown is set so that chain is possible.

**4 — Multiplayer.** Two clients in Studio (Test → Players → 2). One player
hooks; the other must see the cable, anchored where it actually is, moving with
them. Then: release, die mid-swing, and leave the game mid-swing. In all three
the cable must disappear on the *other* screen. Finally have one player hook and
hang, then have the second player join — the newcomer must see the cable that
was already in the air.

That last set is the whole point of the server half. The cable is drawn locally
by every client from two facts the server broadcasts once per hook, so it costs
no per-frame network traffic at all — but it also means every way a rope can end
has to tell everyone, and that is what you are checking.

## Tuning

Change one. Play. Change the next.

**It feels weak.** `BiteForce` is the kick when the hook lands, in multiples of
gravity, and `BiteTime` is how long it lasts. This is the first number to touch;
it is most of the hook's whole personality.

**It feels like being yanked.** Lower `BiteForce` first, then `ReelForce`.

**I cannot build speed.** Raise `MaxSwingSpeed`. It caps the reel as well as the
steering, so a low value quietly limits everything.

**I cannot steer in the air.** `AirControl`, in studs per second squared. On the
rope it is `SwingControl`, which is higher because it matters more there.

**Turning feels floaty / too instant.** Same two numbers. They are
accelerations, so they *add* rather than setting direction — that is deliberate,
and it is why you cannot reverse instantly.

**Landing kills my speed.** Raise `LandKeep` (share of speed kept on touchdown)
or lower `LandDecay` (how fast the slide bleeds off).

**Landing slides too far.** The opposite, and `LandFloor` sets how much excess
speed is worth a slide at all.

**I run out of rope.** `MaxLength`, and `Range` for how far the hook reaches.

**Chaining is awkward.** `Cooldown`. It is 0.6 because anything near a second
stops a route being a route.

**The lens is distracting.** `Camera.FovGain`, or zero to switch it off.

`ReleaseBoost` is zero on purpose. A free upward kick on every release is the
unearned feel the whole system is built to avoid; it is there to experiment
with.

Ground acceleration, ground deceleration and jump strength are deliberately not
knobs here — they already have owners. See the note in the config.

## When it goes wrong

**The hook does nothing and the crosshair is grey.** You are above `MinDepth`,
out of range, or looking at a deposit. All three are intended.

**It fires and immediately drops.** The server refused it. Check range against
`Range * 1.25` and whether `solidAt` found anything — an anchor on a thin shard
of terrain can fail the probe.

**Other players see no cable.** The broadcast, not the physics. The rig is
local by design; `GrappleRope` is what the others listen to.

**A cable is stuck on screen pointing at nothing.** A rope that ended without
anyone being told. The server clears these `HangLimit + 2` seconds after firing,
so if one lingers longer than that the `drop()` path missed a case.

**You scrape to a halt along the floor mid-swing.** That is correct. Friction is
real now. The version this replaced forced `Freefall` sixty times a second to
beat it, which is exactly the controller fight the brief warns about.

**It feels like it is fighting you.** Look for a second writer. Something else
setting `WalkSpeed`, a force that is not `MomentumForce`, or `ChangeState` in a
loop.

## Still to do

- Audio. Every hook is in place and every `Sfx` id is empty.
- The grapple cannot be practised on the surface, because `MinDepth` keeps it
  underground. A movement system nobody can rehearse is one nobody gets good at.
- `HangLimit` is a safety net at 15 seconds, not a mechanic.
