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
- **phase_boost** (optional): before `until_wave`, the named stats' weights are
  multiplied. Lets a fragile kit front-load survival (dodge/HP) through the
  opening, then revert to its offence weights -- the shop analogue of the
  steering caution_phases. Applies to level-up picks too.
- **weapon_set** (optional): lock weapon buys to one weapon class by set id
  (e.g. `set_elemental` for Mage, whose -100% ranged/melee means only elemental
  weapons deal damage). A weapon outside the set scores negative even if it would
  combine. Off-plan weapons offered by crates/level-ups are recycled for gold
  rather than kept (they would waste a slot).

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

### Brawler (#2) -- Danger 1: wins ~1/3, floor lifted from wave 8 to 15
Guide: brotato-builds.com/builds/Brawler ("Speed Demon"). Melee, Claw/unarmed:
attack speed + melee damage + crit lead; cap dodge fast; HP regen + some HP/armor
to survive the short range. Steering already suits it (world_view row
caution 0.5, engage 8 -- it closes to melee).

Plan: `weapon_type: melee`; offence weights attack_speed 9 > melee_damage 8 >
crit 7 > dodge 7 > hp_regen 6 ...; `harvest_cap 0` (no economy).

Tuning found (Danger 1, 2x, batch of 3 per config -- single runs are too noisy):
- **Offence-first**: died waves 8 / 16 / 18 (0/3). The 10-HP opening collapses
  when RNG gives a slow start.
- **Defence-first** (whole run): died wave 16 -- WORSE. Kill speed is a melee
  kit's real defence; over-weighting dodge/armor killed enemies too slowly.
- **phase_boost** (survival early, offence late): before wave 7, x2.2 max_hp,
  x1.8 dodge, x1.8 hp_regen, x1.5 armor. Died 15 / 18 / **won 20** (1/3). The
  floor jumped 8 -> 15 (the early collapse is gone) and it produced the first
  full clear. Not a reliable win yet, but a clear, correct improvement.
- Open: still dies mid/late (~15-18) on the unlucky runs -- a fragile melee kit
  under the bot is genuinely harder than a ranged one (Well Rounded took ~0
  damage; Brawler takes some every wave). More consistency would need mid-game
  defence or better weapon-combine sequencing.

### Crazy (#3) -- Danger 1: WON 3/3
Guide: brotato-builds.com/builds/Crazy ("Knife Pro"). Precise weapons + crit.
Crazy starts with a knife, gets +100% Precise class bonus, +25% attack speed,
but -30% dodge (dodge is a TRAP stat here -- excluded from the plan). Knife/melee
route fits its start and its melee steering row (caution 0.7, engage 6); the high
attack speed kills fast enough that the fragility never bites.

Plan: `weapon_type: melee`; crit_chance 10 > melee_damage 8 > attack_speed 8 >
crit_damage 7 > percent_damage 6.5 > max_hp 6 > armor 5 (no dodge). Early
phase_boost (until wave 6: x1.8 max_hp, x1.5 armor/regen) for the squishy start.

Batch (Danger 1, 2x, n=3): WON 20 / WON 20 / WON 20. All-melee precise builds
(knives to tier 4, hatchets, spears, sharp teeth). Far more consistent than
Brawler -- the attack-speed + precise-bonus DPS is the difference.

### Ranger (#4) -- Danger 1: WON 3/3
Guide: brotato-builds.com/builds/Ranger ("SMG Range Scaler"). Pure ranged
(cannot use melee), +50 range, +50% ranged damage, -25% max HP. Kiting -- suits
the arbiter like Well Rounded; needs no phase_boost.

Plan: `weapon_type: ranged`; ranged_damage 10 > attack_speed 8 > harvesting 8
(cap 35, economy start) > percent_damage 7 > crit 6 > range 5 > armor/dodge 5;
max_hp only 3 (the -25% penalty makes HP items weak).

Batch (Danger 1, 2x, n=3): WON / WON / WON. All-ranged builds (pistols, revolvers,
laser guns, shredders, double barrel, shuriken). Ranged kiters are the arbiter's
strong suit.

### Mage (#5) -- Danger 1: WON 3/3 (with fixes)
Guide: brotato-builds.com/builds/Mage ("Taser Wizard"). Mage does damage ONLY
through elemental weapons: -100% ranged AND melee damage gains, +elemental.

Plan: `weapon_set: set_elemental` (taser/wand/flamethrower/torch/lightning shiv);
elemental_damage 10 > attack_speed 8 > percent_damage 6.5 > luck 5.5 (find burn
items) > armour/hp_regen/max_hp 5; early phase_boost for the squishy start.

Two fixes were needed and are why the first pass was inconsistent:
1. **Wand start.** Mage has no forced starting weapon, so the harness gave it a
   pistol -- which does ~0 (the -100% ranged). On unlucky runs it couldn't kill
   -> couldn't earn -> couldn't buy wands -> death spiral (died wave 6). The
   harness now starts elemental-only characters with a wand (explicit list: the
   penalties are effect_reduce_stat_gains keyed by custom_key hash, not a
   readable stat_ranged_damage, so an effect scan cannot detect them).
2. **Recycle off-plan crate weapons.** Crates/level-ups offer random weapons;
   auto-taking a plank etc. wastes a slot on a 0-damage weapon. The level-up
   auto-take now discards (recycles) any weapon scoring negative for the plan.

Batch (Danger 1, 2x, n=3, both fixes): WON / WON / WON. Builds are wands, tasers,
lightning shivs, torches (elemental, tiered up). Open: 1-2 stray non-elemental
weapons still slip in via some crate path the discard does not catch -- minor,
never blocks the win. Note: Mage kills slowly (burn DoT), so waves run their full
length; runs take ~12-15 min at 2x (batch timeout raised to 18 min).
