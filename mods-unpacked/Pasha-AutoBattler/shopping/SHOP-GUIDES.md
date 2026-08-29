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
- **Lock-and-save**: when a strong ON-PLAN weapon (tier 2+/combine, reachable
  next wave) is on offer but unaffordable, the shop LOCKS it (locked items
  survive rerolls and carry to the next wave), reserves its price, keeps shopping
  with the rest of the gold, and buys it next wave. Two rules keep it from
  hurting the aggressive-spend economy: save only for ON-PLAN weapons (an early
  version reserved gold for off-plan pistol combines and regressed Ranger
  3/3 -> 0/3), and keep shopping while saving (don't leave the shop early). With
  both, Ranger is back to 3/3 and it reliably secures key weapons (e.g. Chunky's
  Spiky Shield).

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

### Chunky (#6) -- Danger 1: wins ~1/3 (borderline)
Guide: brotato-builds.com/builds/Chunky. Tank: +25% max HP, every 3 Max HP = 1%
damage (HP is survival AND offence), Spiky Shield scales with armour. -100%
lifesteal, -50% HP regen and dodge (trap stats, excluded). Steering row already
suits it (food:bank, caution 0.75).

Plan: `weapon_type: melee`; max_hp 10 > armor 8 > percent_damage/attack_speed 6 >
melee_damage/crit/luck 4 > speed 3. No phase_boost (high base HP).

Batch (Danger 1, 2x, n=3): won 20 / died 14 / died 19 (1/3). The wins tank fine;
the losses had weak low-tier weapons (plank_1, spoon_2, lute_1) -- Chunky's
HP->damage still needs a real weapon, and the bot buys any melee weapon equally
rather than seeking Rock/Spiky Shield. Same shape as Brawler.

## Systemic finding after 6 characters
Ranged/kiting characters (Well Rounded, Ranger) and high-DPS ones (Crazy) win
3/3 easily -- kiting + any decent ranged weapon works. Fragile or damage-thin
MELEE characters (Brawler, Chunky) are borderline (~1/3): the bot fills weapon
slots with whatever on-type weapon appears, so unlucky runs get weak primitives.
The clear next systemic lever is WEAPON PREFERENCE -- letting a plan seek its
character's key weapons/sets by id (like weapon_set does for Mage's elemental
class) -- e.g. Brawler->unarmed/Claw, Chunky->Rock/Spiky Shield. This would lift
every melee character at once rather than per-character stat tweaks.

### Old (#7) -- Danger 1: wins ~2/3
Guide: brotato-builds.com/builds/Old ("Small Map Engineer"). Old's traits make it
easy (enemies -25% speed / -10 count, map -33%, +10 harvesting) and it has no
weapon restriction. The guide's optimal is engineering/turrets, but that needs
turret-aware steering + tool-weapon seeking (not built), so this uses a
bot-reliable ranged kite build riding the easy traits.

Plan: `weapon_type: ranged`; ranged_damage 8 > attack_speed 7 > harvesting 7
(cap 40) > percent_damage 6.5 > max_hp/armor 6 > crit 4.5 > dodge 4.

Batch (Danger 1, 2x, n=3): won 20 / died 19 / won 20 (2/3). The loss leaned into
MEDICAL GUNS (ranged but low-damage healers) -- the bot scores all on-type
weapons equally, so low-damage support weapons get bought like real damage
weapons. Reinforces the weapon-preference/quality need (now seen on ranged too,
not just melee). The engineering/turret build is the guide's optimal, revisitable
once tool-seeking + turret-aware steering exist.

### Lucky (#8) -- Danger 1: wins ~1/3 (borderline)
Guides: brotatodex.com/character/character_lucky + metabrotato.com
lucky-slingshot-build. +100 Luck, +25% stat gains, luck-scaled damage on gold
pickup -- but -60% attack speed and -50% XP. Steering row already gold-seeks
and never stands still (feeds the pickup damage).

Plan (tuned): attack_speed 10 > ranged_damage 8 > percent_damage/max_hp 7 >
armor 6 > harvesting 5 > luck only 4; phase_boost until wave 7 (x1.8 attack
speed, x1.6 HP). KEY LESSON: the first pass led with luck 10 and went 0/3
(w19/10/17) -- Lucky already STARTS at +100 luck, so buying more is diminishing
returns while the -60% attack speed starves DPS all run. Leading with attack
speed produced the first full clear: 1/3 (won 20 / died 12 / died 19). A
character's plan must weight what it LACKS, not what its gimmick names.
Remaining variance is the real handicap pair (slow kills + slow levels) --
borderline like Brawler/Chunky.

### Mutant (#9) -- Danger 1: ~1/3, near-misses (borderline)
Guide: brotato-builds.com/builds/Mutant ("XP Scaling"). Real traits: -66% XP
needed (levels ~3x faster; hit lvl 32-35 by run end) and +50% item prices
(item-poor: ~30 items vs the usual ~45-50). Ranged kiting, balanced weights,
min_buy 3 against the inflated prices.

Batch (Danger 1, 2x, n=3): died 19 / WON 20 / died on the final boss (w20).
The XP engine works exactly as intended; both deaths were near-misses. Run 1
stacked THREE medical_gun_3 (the low-DPS healer) -- vs run 2's three shredders
which won. Note the tension with Old: blanket medical-gun avoidance regressed
Old 2/3->0/3 (its healing matters), so any fix here should be per-character
avoid_weapons or a one-support-weapon cap, not a global rule. Left as-is for
now -- the deaths are boundary-line, not systematic.

### Generalist (#10) -- Danger 1: ~1/3, both deaths at wave 19 (borderline)
Guide: brotatodex.com/character/character_generalist ("Cactus & Slingshot
Hybrid"). Must run 3 melee + 3 ranged; melee damage boosts ranged and vice
versa. NO advisor change needed for the split: the game's max_melee/ranged
weapons caps flow through the scorer's has_weapon_slot_available check, and
every batch run produced a clean 3/3 build (rocks/cacti clubs/fists + pistols/
javelins) -- including the guide's cactus route once.

Plan: `weapon_type: any`; melee_damage 8 = ranged_damage 8 > max_hp/attack_speed
6.5 > percent_damage 6 > armor 5.5 > crit/harvesting 5 > luck 4.

Batch (Danger 1, 2x, n=3): died 19 / WON 20 / died 19. Boundary-line: the
structure is right, both losses were one wave short. Same near-miss shape as
Mutant.

### Loud (#11) -- Danger 1: wins ~2/3
Guides: brotatodex.com/character/character_loud ("Enemy Overload Farmer") +
metabrotato.com best-loud-build. +30% damage, +50% enemies (the kills ARE the
economy), harvesting decays -3/wave (trap stat, excluded). Steering row already
gold-seeks and never stands still.

Plan: `weapon_type: ranged`; attack_speed 9 > ranged_damage 8 > max_hp 7.5 >
percent_damage 7 > crit 5.5 > lifesteal/armor 5; no harvesting.

Batch (Danger 1, 2x, n=3): died 19 / WON / WON -- the last win with an
all-tier-4 board (2x shredder_4 + 4x pistol_4) and single-wave kill counts up
to ~950. The extra-enemy income funds a monster build; one wave-19 near-miss.

### Multitasker (#12) -- Danger 1: ~1/3 (borderline)
Guide: brotatodex.com/character/character_multitasker ("12-Stick DPS"). 12
weapon slots, +20% damage, -5% per extra weapon -- volume wins. max_weapons 12;
combines self-defer to a full board (would_combine needs no free slot), which
matches the guide's "don't combine until full" for free.

Batch (Danger 1, 2x, n=3): WON 20 (full 12 board, mixed tiers) / died 9 (a full
board of tier-1s and only 13 items -- filling 12 slots early spreads gold too
thin for stats) / died 19. The volume build works once tiers develop; the
early-game slot-fill vs stat-depth tension is its real weakness.

### Wildling (#13) -- Danger 1: ~1/3 (borderline)
Guide: brotato-builds.com/builds/Wildling ("Lifesteal Setup"). +30% lifesteal
with Primitive weapons (stick start); weapon_set set_primitive locks the board
to stick/rock/spear/hatchet/sharp tooth/cactus mace/slingshot/torch. Offence
leads; lifesteal/regen weights low (the class bonus IS the sustain). Steering
row is already an aggressive melee engager.

Batch (Danger 1, 2x, n=3): died 19 / WON 20 / died 18 -- every run a clean
all-primitive board. The set's weapons are cheap and cap out low (boards sat at
tier 1-2), so the late waves are tight. Borderline, same w18-19 wall.

### Pacifist (#14) -- Danger 1: 0/3, HARD (needs steering, not shopping)
Guide: brotatodex.com/character/character_pacifist ("Peaceful Hand"). -100%
damage + -100 engineering: ALL damage stats are trap stats. Income is 0.65
mats+XP per enemy ALIVE at wave end -- the kill-everything logic is INVERTED.
weapon_set set_support (Hand/taser utility), harvesting first, defence second.
Harness gives it a Hand start (the pistol does nothing at -100% damage).

Batch (Danger 1, 2x, n=3): died 10 / 8 / 6 -- up from the first pass's 4/7/5
(Hand start + a hard defensive phase_boost roughly doubled early survival) but
nowhere near a clear. Pacifist's real lever is the HERDING STEERING (row was
tuned at Danger 6 in the tracker project on developed builds); the shop cannot
carry a character that does no damage. Left as a documented hard case -- future
work is on the steering side, not the plan.

### gold_floor (plan key)
Saver-style permanent hold: keep min(gold_floor, half the shop's bank) in
reserve because the materials THEMSELVES are a damage stat (Saver: +1% dmg per
25 kept). Default 0 = the usual spend-everything economy for every other char.

### Gladiator (#15) -- Danger 1: ~1/3, first clear after two fixes
Guide: brotato-builds.com/builds/Gladiator ("Multi Weapon"). +20% attack speed
per UNIQUE melee family, no ranged, -40% attack speed base, -30 luck. Two fixes:
1. **Systemic melee starter** (harness): a melee-plan character with no forced
   start now begins with a Stick, not a pistol it can barely use. Reads the
   plan's weapon_type via load(build_plans). Helps every no-forced-start melee
   char (Brawler/Chunky/Multitasker/Gladiator).
2. **unique_weapons plan flag** (Gladiator only): reject a NON-combining
   duplicate of a family already held (wastes a unique slot) but KEEP combines
   (they tier a family up without losing uniqueness). A first version rejected
   ALL held families incl. combines -> 6 families stuck at tier 1 (died 14),
   which the fix corrected.

Batch (Danger 1, 2x, n=3): died 17 / WON 20 / died 14 -- up from 0/3 (19/15/17
with the wasted pistol + duplicate families). Every run now builds 6 distinct
families with real tiers (claw_4, hatchet_4, ...). Borderline but structurally
correct.

### unique_weapons (plan key) + systemic melee start
unique_weapons: for per-distinct-family bonuses -- keep combines, reject
non-combining held-family duplicates. Harness: melee-plan chars start with a
Stick (reads weapon_type), after the explicit map (Mage->wand, Pacifist->hand).

### Saver (#16) -- Danger 1: 0/3 (near-misses 16/17/17), gold_floor validated
Guide: brotatodex.com/character/character_saver ("Piggy Bank Economy"). +1%
damage per 25 materials KEPT, Piggy Bank interest, +50% item prices. The one
character where hoarding is a damage stat -> gold_floor. Spear/melee, survival
stats lead.

gold_floor tuning: a flat "hold half the bank up to 400" from wave 1 OVER-held
-- died 15/18/18 with 774-913 gold banked but only 22-36 items and low tiers
(starved the build the guide says to fund first). RAMPED fix: nothing before
wave 5, then +5%/wave of the bank capped at 35% and 250 absolute. Result:
16/17/17, gold held down to ~330-530, healthier early HP, better tiers. Still
0/3 but every death a late-wave near-miss -- borderline like the others. The
gold_floor mechanism is validated as a safe tunable (default 0 = unchanged).

### Sick (#17) -- Danger 1: wins 2/3 (hitrate_pref fixed it)
Guide: brotato-builds.com/builds/Sick ("SMG Setup"). +25% lifesteal, -1 HP/sec,
-100% HP regen (trap, excluded). The sustain scales with HIT COUNT, so a generic
ranged plan that bought wands/single-shots starved it: baseline 0/3 (died
11/14/16). Added hitrate_pref: score weapons by hits/sec (nb_projectiles * 60 /
cooldown, clamped, x1.6) -- SMG cd 4 -> ~+19, pistol cd 60 -> ~+1. Result: 2/3
(died 16 / WON / WON) with SMG/shredder/double-barrel/shuriken boards. (Run 3
won WITH medical guns -- for a hit-rate lifesteal kit their sustain is fine,
unlike Old, which is why weapon avoidance must stay per-character.)

### hitrate_pref (plan key)
For hit-count kits (lifesteal/on-hit procs): bonus per hit/sec from
wdata.stats (nb_projectiles * 60 / cooldown). Favours SMG/minigun/multi-shot
over slow single-shots. Off by default.

### Farmer (#18) -- Danger 1: 0/3, economy-slow (borderline)
Guide: metabrotato.com farmer-build-pruner-guide ("Material Hoarder"). +20
harvesting, +3 harvesting/wave, -50% GOLD DROPS. Economy-first ranged.

Batch (Danger 1, 2x, n=3): baseline died 10/19/12; + early phase_boost (HP/armor/
attack speed to wave 7) -> died 18/12/12 (floor lifted on the collapse runs).
Still 0/3: the -50% gold drops keeps it ITEM-POOR (13-14 items vs the usual
30-45) -- harvesting compounds too slowly to out-farm the drop penalty before
Danger-1 mid-waves kill it. When the economy does ignite it reaches w18-19 with
real builds (shredder_4, double barrels). Borderline; phase_boost kept for the
floor.

### Ghost (#19) -- Danger 1: WON 3/3 (after ghost_axe start fix)
Guide: brotatodex.com/character/character_ghost ("Ethereal Axe Dodge"). +30
dodge, DODGE CAP 90 (vs usual 60), -100 armor. Survival is ENTIRELY dodge:
weight it 12 (far above all), armor weight ZERO (a trap: -100 base amplifies
hits). weapon_set set_ethereal (ghost axe/flint/scepter).

Like Mage, Ghost has no forced start, so the harness pistol + set_ethereal ->
weaponless -> died wave 4. Added ghost_axe to the harness start map. Result:
WON / WON / WON with pure ethereal boards (ghost axes/flints/scepters to tier 4).
The dodge-cap tank is a strong bot fit once it has its weapon.

### Speedy (#20) -- Danger 1: 0/3 baseline (14/18/18, borderline)
Guide: brotato-builds.com/builds/Speedy. +30 speed CONVERTS TO MELEE DAMAGE,
-100 armor while still (+ -3 base) = armor trap (weight 0); steering row
"still: never" keeps it moving. Melee, speed as a damage stat (weight 9),
stick harness start. Batch: died 14/18/18 -- borderline melee, w18-19 wall.
Baseline; retune later.

### Entrepreneur (#21) -- Danger 1: 0/3 baseline (16/10/19)
Guide: brotato-builds.com/builds/Entrepreneur. Economy monster (-25% prices,
+50% stat gains, +25% recycle) but -50% to ALL damage mods. Baseline: ranged,
harvesting-heavy, stacked damage/attack speed to fight the penalty, min_buy 1.5
(cheap items). Batch: died 16/10/19 -- the economy delivers (run 3: 53 items,
tier-4 board, reached the final boss) but -50% damage caps kill speed.
Borderline; the guide's engineering route (turrets bypass the penalty) is the
deeper fix the bot can't do well.

### Engineer (#22) -- Danger 1: WON 3/3 (turrets work!)
Guide: brotato-builds.com/builds/Engineer ("Turret Setup"). Damage from
STRUCTURES: +10 engineering, wrench start, -50% a damage mod. weapon_set
set_tool (wrench/screwdriver), engineering weight 12, survival stats.

Batch (Danger 1, 2x, n=3): WON / WON / WON with full wrench+screwdriver boards
(tier 3-4). SURPRISE: the turret build works well under the bot -- the tools
auto-place structures and engineering scales them, so the arbiter just survives
while turrets kill (no turret model needed in steering). IMPLICATION: the
engineering route (set_tool + engineering) is a viable future optimization for
the OTHER turret/economy chars the guides point there -- Old, Explorer,
Entrepreneur -- which are borderline on direct-damage plans.

### Explorer (#23) -- Danger 1: wins 2/3
Guide: brotatodex.com/character/character_explorer. Large map +33%, +12 trees,
+10 speed, +50 pickup, -40% damage. Steering tuned in the tracker project.
Shopping baseline: ranged, economy (harvesting) + stacked damage to offset -40%,
speed 5. Batch: died 10 / WON / WON -- bimodal: a slow economy start collapsed
(wave 10) but two runs' tree/crate economy ignited into shredder builds (56-60
items). Better than the tracker's pure-fragility read; the shop's economy focus
helps.

### Doctor (#24) -- Danger 1: 1/3 near-misses (WON/17/18)
Guide: brotatodex.com/character/character_doctor ("Medical Gun Medic"). +200%
attack speed with MEDICAL weapons, -100% with all others -> only medical weapons
work (the INVERSE of Old -- proof weapon prefs must be per-character). weapon_set
set_medical, medical-gun harness start, ranged damage + attack speed + HP regen.

Batch (Danger 1, 2x, n=3): WON / died 17 / died 18 -- all full medical-gun boards.
The heal-DPS engine works; the bottleneck is uneven combining on a single-family
board (run 3 had three tier-1 medical guns). A future combine-sequencing pass
for single-family builds would help.

### Hunter (#25) -- Danger 1: 1/3 (16/15/WON)
Guide: brotato-builds.com/builds/Hunter ("Crossbow Setup"). +100 range, +1% dmg
per 10 range, +25% crit mods, -100% harvesting (trap). Crit-range ranged plan
(crit 10 > ranged_damage 8 > range 7 > crit_damage 7). Batch: died 16 / 15 /
WON. The win was a generic ranged snowball (53 items); Hunter's real power is
concentrated in the CROSSBOW (crit + pierce), which the generic ranged plan
doesn't specifically seek. A crossbow/precise-set bias is a future optimization.

### Artificer (#26) -- Danger 1: WON 3/3
Guide: brotatodex.com/character/character_artificer ("Explosive"). +175%
explosion damage, +4% explosion size per elemental damage, -100% base damage,
-50% armor. weapon_set set_explosive (plank/shredder), plank harness start,
elemental + attack speed lead (blast size + rate), glass cannon (armor/dodge/
regen low). Batch: WON / WON / WON with pure plank+shredder boards (tier 4).
The explosion damage bypasses the -100% base, and the steering row's pack-engage
lands AoE well -- a strong bot fit.

### Arms Dealer (#27) -- Danger 1: 0/3 baseline (8/18/18)
Guide: brotato-builds.com/builds/Arms-Dealer ("Rich Fast"). Weapons -95% price,
DESTROYED entering each shop, min 1 offered -> power goes into PERMANENT items/
stats; the board resets every wave. Plan: weapon_type any, % damage + harvesting
+ survival, min_buy 1.5. Batch: died 8 / 18 / 18. The rebuy works (runs 2-3 had
full 6-weapon boards + 47-50 items); run 1 was a bad early refill. Note: the
per-wave wpn= heartbeat often reads 0 (mid-shop-transition snapshot) -- cosmetic,
it kills fine (435 kills/wave). Borderline; a "force-rebuy 6 weapons each shop"
behaviour would firm up the early game.

### Streamer (#28) -- Danger 1: 0/3 baseline (13/16/18)
Guide: brotato-builds.com/builds/Streamer ("Material Slingshot"). Materials while
NOT MOVING. Steering (tracker work) stand_income/stand_phases/still:prefer farms
by standing. Shopping baseline: ranged, armour + HP early, harvesting. Batch:
died 13/16/18 -- item-poor (12-27 items). Likely the stand-to-farm behaviour
trades combat uptime for materials, slowing the build at Danger 1; a shop/steering
income-vs-DPS balance is a future tune. Borderline, climbing.

### Cyborg (#29) -- Danger 1: 1/3 (16/11/WON)
Guide: brotatodex.com/character/character_cyborg ("Minigun Ranged-Engi Hybrid").
+200% ranged damage that CONVERTS to engineering mid-wave -> ranged_damage is the
core stat. Ranged plan (ranged_damage 10 leads, + engineering + lifesteal +
defence); minigun is tier-3+ only so pistol start then buy up. Batch: died 16 /
11 / WON -- the win rode a minigun_4 + shredder board. Ranged->engi works; the
run that drifted into icicles/wands (off-plan) died early. Baseline.

### Glutton (#30) -- Danger 1: 0/3 baseline (18/16/16)
Guide: brotatodex.com/character/character_glutton ("Explosive Eating"). +50 luck,
+1% explosion dmg per consumable at MAX HP (permanent), fruit explodes on pickup
(steering food:bomb AoE). Route spans two sets (Pruners->explosives) so
weapon_type any; max HP 8.5 + luck 8 + melee/elemental lead. Batch: died 18/16/16
-- reaches mid-late but the `any` type lets boards drift off the explosion plan.
Baseline; an explosion-set focus (or Pruner->explosive phasing) is a future tune.
