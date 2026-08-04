# Steering Features — derived from the bed baseline (Aug 3, 2026)

Source data: 10-member test bed (`tools/bench/testbed.txt`), 100 baseline
runs at commit `aeba9ab` → **19/100 survived**, 81 deaths parsed per-death
(archive: `C:\brotato\wavelab\bed-baseline-deaths.csv`). Bed-wide facts the
features must answer to:

- **85% of deaths are bursts** (≥half max HP lost in the final 5 s) — on
  every member. Deaths are cluster events, not attrition.
- **77% of deaths occur with a committed escape active**; the single-corridor
  dodge (`esc=16/17`) alone accounts for 41% of all deaths.
- Killing blows: **contact 48 / projectile 21 / pursuer 12**. Cornering (9)
  and pre-10s deaths (7, all fisherman) are minor.
- Contact deaths show avg nearE=125 on the final tick — threats sat at the
  120 px panic boundary one second before killing. The panic radius is
  speed-blind.
- The fisherman member dies under 15-46 simultaneous projectiles; the
  1-corridor bullet-dodge model cannot represent volume fire.

Implementation vehicle note: the founding-night A/B (see `tools/BENCH.md`)
showed that adding these as competing vector-sum layers moves damage between
hit columns without lowering the total, and that any post-processor on the
final vector must protect ALL committed dodge laterals (charge AND
projectile). F1/F2/F5 should therefore be implemented inside a **single
arbiter** (one motion intent per frame, one path-aware scorer), reusing the
candidate generators archived in commit `6dda860`.

---

## F1 — Lap-aligned dodge scoring (priority 1)

- **Failure mode**: committed dodges reverse heading every 1-2 s and cut
  back through the swarm front; the dodge commit is the death context in
  41% of bed deaths (all 10 members).
- **Mechanism**: hold one rotational direction around the arena; corridor
  dodge side scoring and crossfire exit scoring pay a penalty for
  lap-breaking choices (archived working code: `LAP_ALIGN_BONUS` /
  `LAP_ALIGN_BONUS_CF` in `6dda860`). The only mechanism that has ever won
  the loud-w11 member (2 witnessed wins).
- **Expected movement**: burst-death fraction ↓; Surv ↑ on w11-loud,
  w12-wildling; CrocHits/PursuerHits columns ↓ on those members.
- **Blast radius**: touches dodge/crossfire scoring only if implemented as
  scoring bonus; arena-scale behavior change (visible orbiting).

## F2 — Speed-aware contact avoidance (priority 2)

- **Failure mode**: 48/81 killing blows are body contact, with threats at
  the panic boundary (nearE≈125) one second before death — the 120 px
  panic radius gives ~0.2-0.4 s of warning against 300-600 px/s closers.
- **Mechanism**: panic radius scaled by the enemy's live closing speed
  (`get_move_speed()`, archived); fast-chaser projected positions in all
  path/side scoring; body-slide post-processor ONLY with corridor-lateral
  protection for both charge and projectile dodges (the A/B's 6x
  projectile regression came from omitting the latter).
- **Expected movement**: contact killing-blow count 48 → materially down,
  esp. members w3-sailor (8/8 contact), w5-loud (7/8), w8-gangster (7/9),
  w4-loud (6/9), w8-king (6/9).
- **Blast radius**: enemy-loop term + post-processor; the protection rule
  is the hard part (see A/B history before touching it).

## F3 — Volume bullet dodging (priority 3)

- **Failure mode**: 21/81 killing blows are projectiles; fisherman-w2 dies
  at t≤10 under 15-46 simultaneous 600 px/s shots (its 60 recorded proj
  hits are the worst column in the baseline); wildling-w12 takes 43.
- **Mechanism**: NEW — no archived implementation. Replace/extend the
  1-corridor bullet dodge with volume-aware gap scoring: every imminent
  shot contributes a TTI-weighted lane penalty to the 16-direction
  candidate scorer (generalizing `_proj_blocked_count` from a count to a
  weighted field), so the bot flows through bullet gaps instead of
  sidestepping one lane into another.
- **Expected movement**: ProjHits ↓ on fisherman (60), wildling (43),
  king (19), lucky (14); fisherman early-death count 7 → toward 0.
- **Blast radius**: projectile subsystem only; the fisherman member is a
  clean isolated testbed for it.

## F4 — Burst-interrupt caution mode (priority 4)

- **Failure mode**: 85% of deaths lose ≥half max HP in <5 s; the second
  and third hits of a burst land while the bot continues its committed
  behavior through the same threat cluster.
- **Mechanism**: on ≥2 hits within ~2 s (or >40% max HP lost within 3 s),
  enter a short maximum-caution state: zero loot/gold attraction, raised
  repel gains, widened panic radii, commitment timers halved so escapes
  re-evaluate immediately. Generalizes the existing HP-scaled
  `repel_caution` into an event-triggered mode.
- **Expected movement**: distribution shift — deaths with 3+ hits in the
  last 5 s become rarer; AvgDmg on surviving runs may rise (caution costs
  DPS uptime) — acceptable trade.
- **Blast radius**: one new state flag read by existing terms; low risk.

## F5 — Un-outrunnable-chaser intercept corridors (priority 5)

- **Failure mode**: 12/81 killing blows from boosting pursuers, with the
  highest burst damage of any class (avg 60 dmg in the final 5 s);
  concentrated on w11-loud (8) and w12-wildling/w11-lucky.
- **Mechanism**: treat chasers moving faster than the player with
  time-to-intercept <0.9 s as in-flight dash corridors so the proven
  dodge/crossfire machinery handles them (archived working code in
  `6dda860`).
- **Expected movement**: pursuer killing-blow count 12 → down; PursuerHits
  columns on w11-loud (27) and w12-wildling (32) ↓.
- **Blast radius**: enemy loop corridor synthesis; composes with F1.

---

## Protocol per feature

Implement on a branch → `wavelab.ps1 bed -Count 10` (chunked) → compare
per-member against the baseline table in `tools/BENCH.md` — aggregate must
improve with no member regressing by more than noise (≥2 runs) → user
reviews → merge or revert. The ledger's Snapshot column keeps every sweep
queryable; `bed-baseline-deaths.csv` is the reference death population.
