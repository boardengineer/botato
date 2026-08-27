# RunLoader

Load any public [brotatotracker.com](https://brotatotracker.com) run at a
chosen wave. The mod fetches the run's record and the build it had at that
wave, rebuilds it through the game's own run data (character, weapons, items,
level-up upgrades, gold, level, elite and Nightmare-event schedule, every
stat), and opens that wave's shop as if you had just cleared the wave before
with exactly that build.

## Use

- Title screen: a panel in the top-left corner. Enter the run id (the number in
  `brotatotracker.com/run/<id>`) and the wave, press **Load**.
- Command line: `--runloader=<run id>:<wave>` loads on reaching the title
  screen. Add `--runloader-quit=1` to build, save, print one
  `RUNLOADER BUILT ...` line and quit (for tooling).

Requires the ModLoader. No dependencies on other mods.

## Limits

The authoritative list lives at the top of `run_loader.gd`; in short:

1. **Not seed-exact.** Spawns, drops, shop rolls and the elite species are
   rolled by your game. Same build, same wave type — not the same fight.
2. **DLC content needs the DLC.** Abyss runs, Nightmare difficulty and every
   Abyssal Terrors item/weapon/character; the loader refuses such runs when the
   DLC is not active.
3. **Modded runs do not resolve.** Ids from other mods are skipped and listed.
4. **Game-version drift.** Rebalanced or renamed items load as the current
   version.
5. **Your current saved run is replaced.** The previous run save is copied to
   `runloader_previous_run.json` next to it.
6. **The shop is fresh.** The record has no shop offer, rerolls, locks or bans.
7. **No endless waves, no co-op.**
8. **Stats match the record's snapshot moment**; the shop purchases after that
   moment belong to the next wave's record.
