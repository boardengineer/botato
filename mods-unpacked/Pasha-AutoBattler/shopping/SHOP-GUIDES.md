# Auto-shopping: build plans from internet guides

The bot shops and picks level-ups on its own via a small `shopping/` layer,
gated by `AutobattlerOptions.enable_autobattler` so human runs are untouched.
Each character's build plan (`build_plans.gd`) encodes an internet build guide
*as data*; `shop_advisor.gd` turns the offering + current build + gold into
buy / reroll / go / level-up decisions; two UI extensions execute them
(`extensions/ui/menus/shop/base_shop.gd`, `.../ingame/upgrades_ui.gd`).

## How a plan is scored
- **Items** are scored by their own stat effects, weighted by the plan's
  `stats` map (the guide's priority order becomes the weights). So Fertilizer
  scores through `stat_harvesting`, Heavy Bullets through `stat_ranged_damage`,
  etc. -- item IDs are not hardcoded; the bot reads what each item actually
  gives. Harvesting's weight collapses past `harvest_cap` so the bot pivots off
  economy on schedule. Named items whose value is a special (non-stat) effect
  get an `item_bonus` by id.
- **Weapons**: a buy that would combine (3-of-a-kind -> tier up) scores ~100
  (almost always take it, mirrors the game's own combine predicate). An
  on-type empty-slot weapon scores well and scales with tier. A wrong-type
  weapon on a typed plan, or any weapon when the board is full and it will not
  combine, scores negative (skip).
- **Economy**: Brotato pays no interest, so banked gold is wasted damage. The
  shop buys everything scoring above `min_buy`, then rerolls (down to a small
  `reroll_keep` buffer, up to `max_rerolls`) to surface more items and combines,
  then leaves. Reroll price rises per paid roll, so cost self-limits it.

## Testing
`--wavelab-run=<character>:<danger>` (WaveLab) starts a fresh run at wave 1 and
lets the bot play AND shop it autonomously, printing one `WAVELAB RESULT` per
wave, `BOTLOG SHOP` per shop, and a final `WAVELAB RUN_DONE`. Iterate at
`--wavelab-speed=2`; confirm any passing build's survival at speed 1 (per the
bench-speed rule -- time_scale > 1 can distort survival).

---

## Character plans

### Well Rounded (#1, top-left) -- Danger 1: WON (20/20)
Guide: brotato-builds.com/builds/Well-Rounded ("Beginner's SMG"). Ranged SMG +
Double Barrel; rush Harvesting to 21+, then ranged damage / attack speed, then
lifesteal and defence. Ranged suits the already-tuned kiting arbiter.

Plan: `weapon_type: ranged`; stat weights harvesting 10 > ranged_damage 8 >
attack_speed 7 > percent_damage 6.5 > lifesteal 6 > max_hp 5 > crit 4.5 >
armor 4 > dodge 3; `harvest_cap 40`.

Tuning found (Danger 1, 2x, then confirmed at speed 1):
- **First run died wave 10** with 759 gold unspent and an incoherent weapon set
  (it had bought a melee **knife** on a ranged plan). Two fixes:
  1. **Spend the gold.** `reroll_keep 5`, `max_rerolls 15`, `min_buy 2` (was
     10/2/3). Banked gold is wasted at low danger.
  2. **Reject off-type weapons.** A typed plan now scores wrong-damage-type
     weapons negative, so the kiter never fills a slot with melee.
- **Result: full clear.** Same wave 10 went from death to survived; the run
  won 20/20 with an all-ranged build (laser gun, pistol tier 3, ghost scepters,
  Double Barrel Shotgun tier 4) and 52 items.
- Open: late defence (armor/dodge) scales a little light -- wave 19 spiked to
  ~198 damage taken (survived from a 149 HP buffer). A candidate refinement is
  to lift armor/dodge weight in the late game.
