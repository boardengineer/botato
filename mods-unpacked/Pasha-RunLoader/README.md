# RunLoader

Load any public [brotatotracker.com](https://brotatotracker.com) run at a
chosen wave. The mod fetches the run's record and the build it had at that
wave, rebuilds it through the game's own run data (character, weapons, items,
level-up upgrades, gold, level, elite and Nightmare-event schedule, every
stat), and opens that wave's shop as if you had just cleared the wave before
with exactly that build.

## Use

- Title screen, top-left panel:
  - **Browse**: pick character / danger / zone / outcome, press **Search**.
    Rows read `#id  date  player  wave/waves  level  kills  [retries N] [endless]`,
    25 per page, newest first; modded runs are hidden (and counted). Select a
    row: the run id fills in, the wave picker caps at the last loadable wave,
    and a one-line preview of that wave's build appears (HP, level, gold,
    weapons, item count). Change the wave to preview another.
  - **Load**: opens that wave's shop with the recorded build. A run id can
    also be typed directly (the number in `brotatotracker.com/run/<id>`).
- Command line: `--runloader=<run id>:<wave>` loads on reaching the title
  screen; `--runloader-query=<character|any>:<danger|any>:<zone|any>:<outcome|any>`
  (e.g. `character_pacifist:6:1:Won`) lists page 1 as `RUNLOADER ROW` lines
  plus a `RUNLOADER LIST total=..` line. Add `--runloader-quit=1` to quit
  after the load / list (for tooling).

Requires the ModLoader. No dependencies on other mods.

## Limits

The authoritative list lives at the top of `run_loader.gd`; in short:

1. **Not seed-exact.** Spawns, drops, shop rolls and the elite species are
   rolled by your game. Same build, same wave type — not the same fight.
2. **DLC content needs the DLC.** Abyss runs, Nightmare difficulty and every
   Abyssal Terrors item/weapon/character; the loader refuses such runs when the
   DLC is not active.
3. **Modded runs do not resolve.** The browser hides them (the API cannot
   filter them; they are dropped and counted); a modded id loaded by hand has
   its unknown ids skipped and listed.
4. **Game-version drift.** Rebalanced or renamed items load as the current
   version.
5. **Your current saved run is replaced.** The previous run save is copied to
   `runloader_previous_run.json` next to it.
6. **The shop is fresh.** The record has no shop offer, rerolls, locks or bans.
7. **Retried and endless runs are listed.** A retried wave was died on at least
   once with that build and its per-wave stats may mix attempts; endless runs
   load only up to the zone's last wave (the picker caps there). No co-op.
8. **Stats match the record's snapshot moment**; the shop purchases after that
   moment belong to the next wave's record.
