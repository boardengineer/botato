# WaveLab Steering Benchmark — loud-w11

The lasting test bed for bot steering corrections: every steering change gets
measured here before it counts as an improvement.

## Protocol

```powershell
tools\wavelab.ps1 bench -Note "what changed"
```

Runs the standard snapshot 6 times (fresh seed each iteration, real-time
speed), appends one row to `C:\brotato\wavelab\bench-history.csv` (survival,
avg damage, damage/sec, hit-source split, git commit), and prints the recent
history. Don't touch the game windows mid-batch; survivals auto-record via the
wave-timer-reset detection in the WaveLab watcher.

## The snapshot

`20260802-w11-loud-d5-hp59.json` — library copy in
`C:\brotato\wavelab\snapshots\`, canonical backup in `tools/bench/`.
Loud, Danger 5, entering wave 11 with 59 max HP, 6 ghost weapons. Captured
from a real run that died on this wave (the player, not just the bot).

Why this wave earns benchmark status — it superimposes every steering failure
mode at once:

- **Croc elite**: chain-dashes every ~1.2 s (cooldown 15 frames, range 500,
  ~600 px/s, 22 dmg contact) — a dash corridor is live 45–70 % of ticks, so
  whatever owns the dodge owns the bot's macro-trajectory.
- **Pursuers (2–3 alive)**: 150 px/s base +45/s per boost to 600 px/s; the
  boost stack resets only on landing a hit (23 dmg) — un-outrunnable
  intercepts every few seconds.
- **Loud swarm density**: 30+ enemies mid-wave; encirclement pressure and
  spitter volleys (15–19 dmg) punish any steering dither.
- **Tight margin**: 59 max HP = three contacts stack lethally, but regen
  nearly matches intake — cutting intake ~30 % vs. the careless baseline is
  enough to stabilize. The wave is winnable but only just: the bot has won it
  twice (once with 48 HP left), at a measured rate of ~2/45.

## How to read a result

- **Survived** is the headline but noisy at n=6; treat < 3/6 shifts as
  suggestive, not proof. `DmgPerSec` is the sensitive metric (baseline ~4.2,
  best sustained ~3.4, stabilization needs ~2.9).
- **CrocHits / PursuerHits / ProjHits** expose trades: tonight's history
  shows three different arbitration schemes moving damage *between* columns
  with the same total. A real improvement drops the total.
- Full per-tick telemetry for any batch: `results\<Batch>-i*.log` (BOTLOG
  lines; `esc=` bitmask: +1 gap +2 counter +4 crossfire +8 AoE +16 dodge
  +32 bullet +64/+80 composites).

## Current state (post-A/B revert)

The steering experiments were REVERTED after a 10-vs-10 A/B on this benchmark
showed them to be marginal (4.08 vs 3.89 dmg/s, 0/10 both arms) with a hidden
6x projectile-hit regression. The working tree carries the pre-experiment AI
WIP (July 30–Aug 1 machinery) as the test bed's official start line. The full
experimental code — lap kiting, lap-aligned dodges, body slide, fast-chaser
corridors, arbitration variants — is preserved in commit 6dda860 for reuse;
the lap-alignment insight (dodges must advance one held rotational direction;
it produced both wins) is the strongest candidate to carry into the planned
single-arbiter rework.

## History highlights (Aug 2–3, 2026 — the founding night)

Chronology of steering iterations, all vs. this snapshot (details in
`bench-history.csv`, code archaeology in the wavelab branch log):

1. AI-WIP baseline: 0/6, 4.0–4.3 dmg/s, deaths = pursuer-burst inside dodge
   commits.
2. Five reactive fixes (speed-scaled panic, absolute-strength repulsion,
   synthetic pursuer corridors, body slide, base-layer lap drive): no
   movement — any base-field fix is masked while corridors own the vector.
3. **Lap-aligned dodge scoring** (dodges must advance one held rotational
   direction): first win ever (witnessed), intake trend down to ~3.4.
4. Path-aware dodge probes + squeeze: second win (48 HP left) but squeeze
   rotated dodges into the croc (croc hits 1→3/run, user-observed).
5. Corridor-priority guard and lateral-floor arbitration: each fixed one hit
   column and inflated another. Conclusion: the layered vector-sum
   architecture is saturated — next step is the single-arbiter rework (one
   motion intent per frame, scored against all threats at once).
