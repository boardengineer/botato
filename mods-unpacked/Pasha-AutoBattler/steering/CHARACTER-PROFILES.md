# Character Profiles — Research Synopsis (2026-08-23)

Movement-relevant strategy per character, for extending the character-profile layer in
`world_view.gd`. The bot controls MOVEMENT only (plus pickup-by-walking-over); shop advice
is recorded only where it defines the character.

Sources per character: (1) decompiled game data (`items/characters/<name>/` and
`dlcs/dlc_1/characters/<name>/` — authoritative), (2) Brotato wiki, (3) Cephalopocalypse's
per-character Danger 5 guide transcripts (flattened transcripts were kept in the session
scratchpad; video titles cited in digests). Data/advice conflicts noted per entry — trust
the data file (e.g. Cyborg guide says 250%, data says 200).

Already implemented: **Builder** (phased gold + turret anchor, this file's reason for
existing), **Soldier** (prefers_still only — tap-move dodging not yet).

## Cross-cutting reusable terms

Build these ONCE; each covers several characters:

1. **HP-gated consumable value** (bot already prices fruit by missing HP — extend, don't replace):
   - Full-HP *seek* gate (pickup at max HP is the point): farmer (+1 harvesting at max), glutton (+1 explosion dmg at max), druid (luck roll any HP).
   - Stockpile-on-ground (skip fruit until damaged): chunky, ghost, ogre, lucky, vagabond, well_rounded baseline.
   - Worthless fruit (never detour): golem (no_heal), vampire (consumable_heal −100), pacifist late.
2. **Enemy-proximity-gated consumable pickup** (fruit = bomb; step on it only with enemies near): chef (explode+ignite), glutton (500% melee explosion). Inverse of the stockpile gate — needs enemy-count-near-fruit check.
3. **Material value phases** (Builder machinery generalizes):
   - Max greed: saver (never leave any — %dmg per 25 held + piggy bank), mutant (3× XP), loud, demon (materials=HP), jack, apprentice, one_arm, old, fisherman (w1 worth tanking hits).
   - Metered: buccaneer — one pickup per weapon-cooldown volley (pickup resets cooldowns; vacuuming wastes resets), keep a ground bank.
   - Gated on live enemies: lucky (pickup deals dmg — wasted with nothing on field).
   - Low/along-the-way: hiker (steps are income), ranger (clear speed first).
   - Combat-DPS pickup: sailor (blunderbuss refires per pickup — vacuum DURING elite orbits).
4. **Kite-radius multiplier**, static or stat-scaled: max = hunter, ranger, wounded, technomage; low = brawler, knight, wildling, crazy, generalist, gladiator, dwarf/ogre late; scaled by runtime stat = king (armor), generalist (lifesteal), creature (range decays per wave), captain/romantic (grow with wave).
5. **Contact-seeking / HP-band aggression** (inverse kiting, gated on HP band or hits-taken): bull (explode on hit; engage >60% HP, flee <30%), vampire (hover ~50% HP), lich (walk into things until ~55%, retreat, repeat), masochist (stack ~20 hits at wave start, back off at ~2/3 HP), wildling (facetank, widen only <~30%). Variant **herd-then-strike**: dwarf (clump ≥6 then charge through), ogre (chain overkill explosions), knight (spiral-stack), artificer (clump into swing arc).
6. **Anchors** (the Builder leash generalizes):
   - Own structures: engineer (turrets spawn grouped under you — pod play + prefers_still), streamer, multitasker, entrepreneur (scattered — largest cluster), renegade/king (medical turret on elite waves).
   - Center: demon (escape routes at ~0 HP), one_arm (from ~w5), old (−33% map), vagabond, masochist (elite waves), artificer.
   - Corner/edge: fisherman (~w10+, funnel one direction), saver (funnel for pierce), ranger (w7 eggs).
   - Perimeter orbit: pacifist (circle the edge all game), hiker (never stop — laps), creature (lap edges ~w16 for curse aliens).
   - Negative anchor: mage (stay OPPOSITE own turret to cover map).
   - Tree-keyed: cryptid = trees are REPULSORS (income per living tree; −100 range one-shots them on contact); explorer = trees are ATTRACTORS (route tree-to-tree, sweep corners).
7. **Avoid-kill target classes**: eggs (jack, saver, ghost wants the opposite), trees (cryptid always, diver w1), elites (gangster — never-kill viable, technomage, hiker, wounded, one_arm, early vampire), everything (pacifist — paid per enemy alive at wave end).
8. **Spawn-marker (red X) avoidance**: pacifist, jack, king, lich — never stand on spawn indicators (costs money/XP). New world_view term: repulsor on spawn telegraphs.
9. **Still-vs-moving spectrum**: soldier (still by default, instant fire resume, tap-move dodges, 200% pickup range collects passively) → streamer (still with 1s re-arm; relocate decisively then freeze; +40/40% while-moving on elite waves) → baseline → sick (stay engaged; lifesteal only heals in combat) → speedy/hiker/lucky/creature (never stand still; speedy loses 100 armor while stationary).
10. **Wave-clock phases**: cyborg (ranged kiting first half, melee dive second half — timer turns blue at the switch; 45s on the 90s boss wave), golem + masochist + crazy (end-of-wave dive/engage in last ~5–15s), streamer/engineer/ranger (end-of-wave pickup sweep), wounded (hard phase switch on first damage taken: center anchor + minimal twitch movement).

## Full regression bed — 2026-08-25 (arbiter-world-model @ 14588dc + dirty)

**INVALID AS AN ARBITER MEASUREMENT.** `wavelab.ps1 bed` (like `run`) defaults to `--arbiter=0`;
this sweep was run without `-Arbiter` and its own logs read `ARBITER off` — it measured the OLD
FIELD CONTROLLER that still ships in the build. Discovered during the regression hunt when two
arbiter arms on w5-loud (`ARBITER on`) scored 10/10 each against this bed's 2. The table is kept
as a field-controller datapoint (33 vs its own 49 record); the arbiter bed is re-run below with
`-Arbiter`. Historical bed numbers (19/31/37/49) were all field-controller runs; the only prior
arbiter bed is v3's 26. Rule: check the `ARBITER on` line in a run log before believing a number.

`wavelab.ps1 bed -Count 10`, all 10 members, speed 1, ledger Note "REGRESSION after
profiles+soldier11+bull6". **33/100** — field controller.

| member | arbiter v3 | field ctl record | **this bed** |
|---|---|---|---|
| w11-loud (croc + pursuers) | 0 | 0 | **0** (3.97 dmg/s; best ever 2.9) |
| w8-gangster | 3 | 5 | **4** |
| w5-loud (7 HP) | 3 | 9 | **2** |
| w4-loud (1 HP) | 1 | 5 | **1** |
| w3-sailor | 5 | 4 | **6** (best ever; first bench of the sailor row) |
| w3-renegade | 3 | 7 | **5** |
| w2-fisherman | 4 | 5 | **2** (knife-edge member; row inert before w10) |
| w12-wildling | 1 | 4 | **4** (first bench of the facetank row) |
| w8-king | 4 | 4 | **2** |
| w11-lucky | 2 | 6 | **7** (v3's −6 regression gone; best ever) |

Read: +7 over the last arbiter sweep, carried by lucky (+5), wildling (+3), renegade (+2), sailor
(+1), gangster (+1); given back on king (−2), fisherman (−2), w5-loud (−1). The gap to the old
controller's 49 is concentrated in the two fragile loud early waves (7 HP and 1 HP entries: 3 vs 14
combined) and renegade/fisherman/king. Those are near-perfect-avoidance members with no room for a
single hit — the natural next investigation is whether the standing-candidate full price for aimed
threats (eleventh Soldier pass, global) or the bonus-speed pursuer model changed their dodging; a
per-member A/B with `--arb-charprofile=0` and `--arb-bonusspeed=0` would attribute it. Nothing in
this bed suggests a broken mechanism: no member fell below its historical floor except w5-loud by
one, and every profile row that got its first bench (sailor, renegade, wildling, lucky) landed at or
above its member's history.

## ARBITER regression bed — 2026-08-25 (b56c850 + the aimedfull/neverstill knobs)

`wavelab.ps1 bed -Count 10 -Arbiter`, all 10 members, speed 1, ledger Note "ARBITER bed b56c850".
**93/100.** The only prior arbiter bed was v3's 26 (Aug 4); the field controller's all-time record
was 49.

| member | field ctl (today) | field ctl record | arbiter v3 | **arbiter now** |
|---|---|---|---|---|
| w11-loud (croc + boosted pursuers; won twice ever) | 0 | 0 (1 once) | 0 | **5** (1.9 dmg/s; prior best 2.9) |
| w8-gangster | 4 | 7 | 3 | **10** (6 dmg) |
| w5-loud (7 HP) | 2 | 9 | 3 | **10** |
| w4-loud (1 HP) | 1 | 5 | 1 | **10** (3 dmg) |
| w3-sailor | 6 | 6 | 5 | **10** |
| w3-renegade | 5 | 7 | 3 | **9** |
| w2-fisherman (knife-edge) | 2 | 7 | 4 | **10** |
| w12-wildling | 4 | 5 | 1 | **9** (138 dmg, lifesteal) |
| w8-king | 2 | 4 | 4 | **10** (2 dmg) |
| w11-lucky | 7 | 8 | 2 | **10** |

**The regression hunt, in full.** The earlier 33/100 bed was run without `-Arbiter` and measured
the old field controller; the "biggest regressions" (w5-loud 2, w4-loud 1, king 2, fisherman 2) were
that controller's numbers. Stage 1 of the hunt — per-arm controls on w5-loud and king-w8 with the
arbiter ON (`--arb-charprofile=0`, `--arb-bonusspeed=0`, `--arb-aimedfull=0`, `--arb-dpsref=0`) —
scored **10/10 on all eight arms**, against the field controller's 7 and 4 on the same beds. So no
change this session hurt either member; there was no arbiter-side regression to bisect (the commit
bisection driver was also broken — pwsh mangles a binary `git archive | tar` pipe — and was not
needed). The arbiter bed above is the real number: +67 over v3, +44 over the field controller's
record, with every fragile early-wave member perfect and the founding croc/pursuer bench won for
only the third, fourth, fifth, sixth and seventh times in its history.

Lessons recorded: always pass `-Arbiter` (run/bench/bed all default to the field controller) and
check the log's `ARBITER on` line; GDScript runtime errors live in `-iN.log.err`; never grep the
newest task-output file from inside a queued task (it finds itself).

## Priority shortlist (highest value ÷ effort)

1. **Engineer** — Builder anchor verbatim (structures spawn grouped) + prefers_still + end-of-wave sweep. Cheapest next profile.
2. **Saver / Mutant / Demon / Loud** — one-line profiles: raised gold value (Saver highest; Demon adds HP-scaled caution).
3. **Lich / Vampire / Masochist / Bull** — the HP-band contact-seeking term; one term, four characters; it fully inverts default steering, so bench carefully.
4. **Hiker / Pacifist** — perimeter-orbit anchor + never-still; pacifist adds spawn-marker repulsion (term #8 shared with jack/king/lich).
5. **Chef / Glutton / Lucky** — conditional pickup gates (enemy-proximity fruit bombs; enemy-gated material pickup).
6. **Cryptid / Explorer** — tree repulsor/attractor pair.
7. **Buccaneer** — pickup metering (needs weapon-cooldown state; most novel plumbing).
8. **Soldier tap-move + Speedy never-still** — refine the still spectrum both directions.

---

## Digests — base game

### apprentice
Mechanic: per level-up +2 melee/+1 ranged/+1 elemental/+1 engineering/−2 max HP; wants xp_gain. Advice (Ceph "Apprentice Danger 5 Guide"): lean into leveling; roam wide to collect (slingshot kills map-wide, drops land far); ~50 max HP before first elite; wave 11 hardest; space around shortest-range weapon. Bot: strong pickup + wide roaming; kite radius >1 and extra caution waves ~8–12 / while max_hp low. Confidence high.

### arms_dealer
Mechanic: weapons destroyed every shop (destroy_weapons), −95% weapon price, +30 harvesting, +33% damage-stat gains. Advice ("LET'S ROLL"): economy char — fast clears raise income; space by shortest-range weapon of the CURRENT set (changes every wave); don't hug fire turrets (spread burn), hug medical when hurt. Bot: strong pickup; dynamic kite radius from current loadout; suppress attack-turret anchoring. Confidence high/medium.

### artificer
Mechanic: explosions scale off elemental (+175% expl dmg, +4 size per elemental); only Tool/explosive weapons work (−100% dmg, −50% armor gains). Advice: clump hordes into single swings; center-ish position mid-game; elites are the danger (~w10–14); standoff range late with rocket launchers. Bot: loose center anchor + clump-then-strike; kite spike while elite alive; longer range after ~w12/ranged weapon. Confidence medium-high.

### baby
Mechanic: level-ups grant weapon slots (max 24), start 1 slot, +130% XP needed; wants xp_gain. Advice ("SO MANY WEAPONS"): hardest early game — cautious wide kiting waves 1–9; break every tree, chase loot/crates (XP bottleneck); negative speed mid-game; late: walk THROUGH crowds so back-side weapons attack; online ~12–15 weapons (~w13+). Bot: very high pickup; kite large early → aggressive crowd-contact once weapons ≥ ~10. Confidence high.

### beast_master
Mechanic: no weapons (pets only); lootworm pet collects materials with 10% doubling; +2 speed per pet stat. Advice ("Paws and Claws"): waves 1–3 leave big material clusters for the lootworm, sweep edges + full sweep at wave end; continuous loops/figure-8s so pets kill trailing enemies; late (Bot-o-Mines) go AFK near center. Bot: gold value slightly negative w1–3 with end sweep; large kite + loop movement; late phase → prefers_still + center anchor. Confidence high.

### brawler
Mechanic: fists, +50% AS unarmed, +15 dodge, −50 range/−50 ranged dmg. Advice: dive packs and stand punching ("all the money is right here"); stand on summoners; back off to fruit/medical when hurt. Bot: kite ×~0.3–0.5; prefers_still when surrounded & healthy; retreat-to-heal on HP drop. Confidence high.

### bull
Mechanic: weaponless; explodes when HIT (300% scaling); +20 HP/+15 regen/+10 armor. Advice ("WITHOUT Self Damage"): herd into a pile then dive so one explosion kills many; skip elites entirely; engage >~60% HP, pure-kite <~30% while regen refills; hover near (not on) spawn edges; use i-frames to push deeper. Bot: charge-densest-cluster mode with HP-phase toggle; never engage elites/bosses. Confidence high.

### chunky
Mechanic: +25% maxHP gains, +1% dmg per 3 max HP, consumables heal +3, no lifesteal/regen-mods halved, speed LOCKED at base. Advice: leave fruit on the ground as a health bank, collect when needed; contact acceptable; never stand still; short chases only (no speed). Bot: consumable value keyed to missing HP (avoid >~80%, seek <~50%); low kite radius; no speed assumptions. Confidence high.

### crazy
Mechanic: +100 range on Precise weapons, +25 AS, −30 dodge. Advice ("INSANE INCOME"): thief-dagger crits; walk into big groups to maximize income; dive the middle at end of wave; wave 9 peak farm. Bot: kite <1; seek densest cluster in last ~10s. Confidence medium.

### cryptid
Mechanic: +6 trees, 12 materials+XP per LIVING tree at wave end, +3 regen per living tree, −100 range, dodge cap 70, −50% enemy drops. Advice ("BEST BUILD I've Ever Had"): do NOT kill trees — with −100 range you one-shot them on contact, so stay clear; play area shrinks as trees spawn; cautious early-wave (regen not stacked), tanky late. Bot: NEW tree-repulsor term (inverse of Builder anchor); kite shrinks as living-tree count/regen rises. Confidence high.

### cyborg
Mechanic: minigun start, +200% ranged-dmg gains; at HALF-WAVE 100% of ranged dmg converts to engineering ×2 (timer turns blue). Advice: two phases every wave — ranged kiting + kill elite first half; second half play melee ("walk into everything"); boss wave switch at 45s. Bot: wave-clock phase — kite large t<half, small after; elite priority first half only. Confidence high.

### demon
Mechanic: buys items with Max HP; 50% of materials → +1 max HP per 13 at wave end. Advice: play hitless while HP is spent to ~1 ("several rounds perfectly"); stay mid-arena for escape routes; every material is future HP — pick up everything; late can hold center. Bot: high pickup; kite radius driven by current HP (near-死 → extreme avoidance); weak center anchor. Confidence high.

### doctor
Mechanic: +200% AS on Medical weapons, regen 5 (+100% gains), −100 AS, −50% armor gains. Advice: healing solved — take damage and heal back; keep ~110% speed; collect during the wave. Bot: kite slightly <1 (trade hits for pickups); otherwise default. Confidence medium-high.

### engineer
Mechanic: +10 engineering (+25% gains), −50% damage gains, structures spawn GROUPED near you at wave start (group_structures). Advice: "stand still in your little pod of turrets"; stand slightly behind them so enemies come through; drops pile in one place — sweep in last ~5s; pull elites through the field from the far side; leave pod only for trees/loot aliens. Bot: anchor = turret-cluster centroid, small radius; prefers_still; end-of-wave sweep; elite → far side of anchor. Confidence high. **Cheapest next profile.**

### entrepreneur
Mechanic: lose 100% held materials at wave START (spend everything in shop); −25% prices, +25% recycling, +50% harvesting gains, −50% dmg gains. Advice: turrets spawn scattered — pick the turret-dense side and drag enemies through; wrench knockback herds INTO the field. Bot: soft anchor to largest turret cluster; keep-turrets-between-self-and-enemies; pickup normal-high (mid-wave pickups are safe — only wave-start holdings vanish). Confidence medium.

### explorer
Mechanic: 12 trees + tree at wave start, lumberjack shirt (1-hit trees), +50 pickup range, +33% map, +25% enemies (+10% faster), −50% drops, −40% dmg. Advice: run tree to tree, sweep corners; don't chase enemies; ~125% speed needed for normal safety; wave 14 (slugs) most dangerous. Bot: seek-nearest-tree waypoint term + corner sweeps; low engagement priority; kite >1; extra caution w14–15. Confidence high.

### farmer
Mechanic: +20 harvesting, +3%/wave harvesting growth, +1 harvesting per consumable picked at MAX HP, −50% drops. Advice: the whole game is not-taking-damage; waves 1–8 route through every fruit at full HP; from ~w9 fruit is opportunistic only. Bot: consumable value high ONLY at HP==max; kite >1; phase switch ~w9. Confidence high.

### fisherman
Mechanic: +20 harvesting, free Bait every shop (each bait spawns extra enemies at every wave start), −50% enemy drops. Advice: wave 1 tank hits to grab everything (~65 to first shop); survive the wave-open burst; corner anchor late; danger spikes w6/10/11. Bot: pickup very high (max w1); corner anchor ~w10+; enlarged kite first ~10s of each wave. Confidence high.

### generalist
Mechanic: 3 melee + 3 ranged, melee/ranged stats feed each other. Advice: "position as a melee character"; loosen once lifesteal ~10–15%. Bot: kite <1; relax with lifesteal stat. Confidence medium.

### ghost
Mechanic: +30 dodge, dodge cap 90, −100 armor (double damage when hit). Advice: ethereal weapons scale per KILL — chase dense low-HP packs, clear w7 eggs; leave fruit as emergency heals (pick up AFTER a hit, not at full HP); dive groups (dodge i-frames). Bot: consumable negative at full HP → strong positive when hurt; tight engagement while unhurt → wide recovery kite after damage. Confidence high.

### gladiator
Mechanic: +20% AS per different weapon, melee only, −40 AS, −30 luck. Advice: position around the median (hatchet) range; stand on slug corpses; move TOWARD ring-attack elites. Bot: kite tuned to ~hatchet range; else generic melee. Confidence medium.

### glutton
Mechanic: every consumable EXPLODES on pickup (500% melee scaling); +1 explosion dmg per fruit at max HP; +50 luck. Advice ("8000 DAMAGE CRITS"): step on fruit only with enemies near it; lure packs over garden clusters then detonate; center-arena play; waves 1–5 perfect-HP snowball phase; fruit left at wave end auto-collects — don't sweep. Bot: richest profile — consumable value = f(enemies near fruit), negative alone; w1–5 max caution; loose center anchor; route kite paths through fruit when chased. Confidence high.

### golem
Mechanic: NO healing during waves (restores between), +33% maxHP/armor gains, +40 AS/+20 speed below half HP. Advice: damage avoidance is everything; spiral/circle to stack enemies; consumables worthless; END-OF-WAVE DIVE — last ~5s, dive the pack for materials (damage then is nearly free). Bot: consumable ≈0; kite high; wave-timer phase: final-seconds material dive; +20% speed under half HP usable in escape math. Confidence high.

### hunter
Mechanic: +100 range, +1% dmg per 10 range, −100% harvesting, −33% maxHP gains. Advice: fight at max distance from ~center; can be one-shot — movement is the skill; perpendicular to chargers; drops land FAR — travel to collect. Bot: max kite radius; high pickup with travel willingness. Confidence high.

### jack
Mechanic: +200% gold drops, +125% vs bosses, −70% enemy count, +175% enemy HP; always 3 elite waves, never hordes. Advice: grab every material; never stand on red X (blocked spawn = 3× materials lost); tight-spiral kite the croc elite; dodge out unkillable summoner elites; let eggs hatch late; chase loot aliens. Bot: pickup high; spawn-marker avoidance; small elite kite spiral; avoid-kill eggs mid-game+. Confidence high.

### king
Mechanic: +50 luck; +25% dmg&AS per Tier-IV weapon, −15% per Tier-I; +5 HP per T4 item. Advice ("INVINCIBLE"): survive early / monster late; stay OFF edges vs chargers (they wall-slide farther); fight elites near medical turret/garden; stand on dead slime-eye spots (w14+); can wade packs late. Bot: kite high early → shrink after ~w12/armor high; healing-structure anchor on elite waves; edge-avoidance margin. Confidence high/medium.

### knight
Mechanic: +2 melee dmg per armor, +3 armor, melee only, tier II+ only, −80% harvesting gains. Advice ("EASIEST Danger 5 Win"): tank everything; spiral to stack enemies; stand ON elites; sidestep charges from standstill then chase during cooldown. Bot: near-zero kite radius, seek enemy center of mass, spiral bias, tight elite engagement. Confidence high.

### lich
Mechanic: regen 10 + lifesteal 10; every heal tick damages a random enemy (scales with max HP); −50% all damage gains. Advice: WALK INTO enemies/projectiles; hold 50–66% HP; pick each material the instant it drops (never let piles merge — per-pickup heal procs); don't chase loot aliens; don't block spawns. Bot: HP-band contact-seeking (engage >~66%, retreat <~50%); immediate per-material pickup priority. Most bot-actionable of its batch. Confidence high.

### loud
Mechanic: +30% dmg, +50% enemies, −3 harvesting per wave end. Advice ("MORE POWER"): economy char — hoover materials (more drop than anyone can collect); chase shooter/spawner mobs before projectile floods; constant motion; 3+ loot aliens per lure. Bot: pickup max; wide roaming, no anchor; loot-alien seek; larger kite vs hordes. Confidence high/medium.

### lucky
Mechanic: +100 luck (+25% gains); chance per material PICKED UP to deal damage (15% of Luck); −60 AS, −50% XP. Advice: pickups are the weapon — WAIT to grab clusters until enemies are on the field; leave consumables banked for when hurt; never stands still; elites: disengage and survive. Bot: gold value gated on live-enemy count; consumable bank gated on HP; retreat anchor = consumable pile. Confidence high.

### mage
Mechanic: +5 elemental (+25% gains), −100% melee/ranged gains; starts Snake+Scared Sausage (burn spread). Advice: tag-and-run — touch range, retreat while burn ticks; stay on the OPPOSITE side of the map from own turret; sit on the octopus boss's head (ring slowest near center). Bot: pulse-engagement kiting; negative anchor to own turret; kite > melee default. Confidence medium-high.

### masochist
Mechanic: −100% dmg; +5% dmg per hit TAKEN (until wave end); +10 HP/+20 regen/+8 armor. Advice ("MOST PAINFUL"): run INTO packs at wave start to stack ~20 hits (small enemies/projectiles — 1 dmg through armor); back off ~2/3 HP, regen, re-engage; central on elite waves; engage the elite only in the final ~10–15s once stacked. Bot: hits-taken-gated contact seeking; center anchor on elite waves; delayed elite engagement by wave clock; avoid heavy hitters specifically. Confidence high.

### multitasker
Mechanic: 12 weapon slots, −5% dmg per extra weapon. Advice: 12 melee weapons = "field of protection" — walk into packs; corner+turret-cluster play in engineering variant; weakest at exactly 6 weapons. Bot: kite ×~0.6–0.7 once weapon count ≥ ~9; conditional structure anchor. Confidence medium.

### mutant
Mechanic: −66% XP needed (≈ triple levels), +50% item prices; wants xp_gain. Advice: materials are 3× levels — sweep center before wave end, chase crates, let eggs hatch. Bot: pickup well above baseline all waves, crate seek, kite ~1.2–1.4, never still. Confidence high.

### old
Mechanic: −33% map, −25% enemy speed, −10% enemies, −10 speed, +10 harvesting. Advice: no room to kite — don't try; income short → collect everything; pull elites/bosses over structures. Bot: pickup strongly positive; kite ×~0.6–0.7; center bias (dodge room is the scarce resource); structure anchor on elite waves. Confidence high.

### one_arm (One-Armed)
Mechanic: 1 weapon slot, +200% AS, doubled damage-stat gains. Advice ("The WORST Class?"): melee w1–5 (drops land near); swap ranged ~w5; then "stay towards the center — more options to dodge"; never fight elites; weakest w5–9; wave 20 = evasive loops collecting health. Bot: pickup strong; phase at ~w5–6: contact-range → center anchor + normal/large kite; elite avoidance flag. Confidence high.

### pacifist
Mechanic: 0.65 materials+XP per enemy ALIVE at wave end; −100% damage; lumberjack shirt. Advice: circle the arena PERIMETER all game; walk away from spawn points; NEVER step on red X (cancelled spawn = lost income); reach trees before wave end; consumables heal 0 once worm-stacked. Bot: perimeter-orbit anchor, never still, spawn-marker repulsion, tree seeking, consumable ≈0 late. Confidence high.

### ranger
Mechanic: +50 range, +50% ranged gains, −25% maxHP gains, ranged only. Advice ("SO MUCH DAMAGE"): fight from center at max distance; clear speed beats mid-wave pickups (sweep leftovers at end); w7 play near edge (don't kill eggs); elites: back way up. Bot: kite max; low mid-wave pickup + end sweep; w7 edge anchor; elite kite spike. Confidence high/medium.

### renegade
Mechanic: +2 projectiles/+1 pierce, −50 accuracy, −400% dmg (+10% per different T1 item), ranged only. Advice ("CRAZIEST Class"): must get CLOSE to elites to land the spray; medical-turret anchor; shallow-angle dodges; cluster the wave-20 bosses. Bot: kite ×~0.6–0.7 vs elites/bosses; boss-clustering (don't split the pair); turret anchor; extra distance from floaters. Confidence medium-high.

### saver
Mechanic: +1% dmg per 25 HELD materials, +15 harvesting, Piggy Bank (+20%/wave-start compound), +50% prices. Advice: compound interest — vacuum EVERYTHING (opposite of Builder), pickup range prized; corner/edge play funnels enemies for spears. Bot: highest material value in roster; corner/edge anchor; caution early waves. Confidence high.

### sick
Mechanic: −1 HP/s drain, +25 lifesteal, no regen. Advice: healing only while HITTING things — never idle away from combat; brief disengage when HP dips, re-engage fast. Bot: stay-in-weapon-range bias (avoid over-kiting to empty corners); quick re-engage after dodges. Confidence high.

### soldier
Mechanic: can't attack while moving; +50% dmg & AS while still; +200% pickup range; +10 speed. Advice ("Kill Elites in SECONDS"): tap-move — fire resumes instantly on stop; move only to dodge; pickup range collects passively (don't roam). Bot: prefers_still (done) + tap-move dodge style (short bursts, stop immediately); near-zero mid-wave pickup seek. Confidence high.

### speedy
Mechanic: +30 speed, +1 melee dmg per 2% speed, −100 armor WHILE STANDING STILL. Advice: never stop moving (~double damage when still); circle elites continuously; danger is out-driving your own reflexes. Bot: never_still flag (penalize zero velocity — inverse of soldier); clearance margins scaled by speed stat; slow/repeat passes over material clusters (fast skim misses pickups). Confidence high.

### streamer
Mechanic: +3% of held materials per FULL second standing still (cap 25/s ≈ 867 held); +40% dmg & AS while MOVING; −50% drops; slower per 30 held. Advice ("INVINCIBLE MONEY MACHINE"): stand motionless near own turrets nearly all wave; every move resets the 1s tick — relocate decisively then freeze; end-of-wave XP/material loop; elite/boss waves = move constantly (the moving bonuses). Bot: prefers_still with min-still-duration >1s (no micro-jitter!); structure anchor; pickup high below ~867 held, ~0 above; end-of-wave sweep; moving-mode on elite waves. Richest still-profile. Confidence high.

### technomage
Mechanic: 2 free turrets, structure AS per elemental, −100% melee/ranged gains, +75% XP needed. Advice ("BURN IT ALL DOWN"): keep-your-distance DoT play; do NOT try to kill elites — survive/kite them; collect actively (low pickup radius hurts). Bot: kite ×~1.5; elite-avoid flag; high pickup; mild turret-coverage bias. Confidence medium-high.

### vagabond
Mechanic: all weapons count for all set bonuses; −5 armor/−5 dodge; −50% luck/harvesting gains. Advice: heavy negative speed early — stay near CENTER (can't chase); intercept loot aliens the moment they spawn; late = dodge-tank wading; leave health crate until damaged. Bot: center anchor; kite <1; consumable HP-gated; loot-alien priority; shrink patrol if speed stat <0. Confidence medium.

### vampire
Mechanic: per % MISSING HP: +2% dmg (+1% lifesteal per 3, +1 armor per 5); consumables heal 0; no regen. Advice ("IMMORTALITY AWAITS"): deliberately take damage at wave start; hover ~50% HP (≤2/3, never full, never near death); wade groups once stacked; avoid early elites; fruit worthless. Bot: HP-band controller targeting ~0.5 HP ratio — kite→0 above band, normal in band, retreat-but-keep-hitting below; consumable ≈0; early elite avoidance. Confidence high.

### well_rounded
Mechanic: +5 HP/+5 speed/+8 harvesting, nothing behavioral. Advice (Ceph's beginner guide = the game's baseline doctrine): center-ish play, collect everything + end sweep, fruit only when hurt, break trees, chase loot aliens, hug elites to burst them early. Bot: THE BASELINE the other profiles deviate from — nothing special needed. Confidence high.

### wildling
Mechanic: +30% lifesteal on Primitive weapons, tier ≤2 only. Advice: facetank and heal back — "dodge only as much as needed to not die"; piggies > trees; ~2% speed at run end is fine; lifesteal caps ~10 HP/s so avoid true swarms. Bot: kite ×~0.3–0.5 scaled by HP (widen <~30%); strong pickup; loot-goblin chase; no anchor. Confidence high.

### wounded
Mechanic: die_in_one_hit; tardigrade absorbs exactly one hit; +5 speed, +8 harvesting; all defense items banned. Advice ("ONE HIT KILL", Nightmare): kill at range before contact; never see the elite; side/corner bias by wave type; leave materials rather than risk it; AFTER the tardigrade pops: tiny tap movements near map center. Bot: kite ×1.5–2; pickup ~half value, threat-discounted; elite repulsion; phase trigger on first damage → center anchor + minimal amplitude. Confidence high (Nightmare-sourced specifics medium).

## Digests — Abyssal Terrors DLC

### buccaneer
Mechanic: materials worth double; picking one up RESETS all weapon cooldowns; −100 AS (weapons barely fire on their own); −50% drops. Advice ("HIGHEST DPS"): pick up ONE at a time, spaced so each reset lands on weapons actually cooling; vacuuming a pile = ~3s unable to attack; keep a ground bank; run group-to-group; orbit elites near add packs for resets. Bot: metered pickup (throttle ~1 per volley, suppress while weapons ready); never still; elite = mid-radius circle near other clusters. Confidence high.

### builder — IMPLEMENTED
Mechanic: uncollected materials at wave end → turret stats (+1% AS/+1 range per 5; tiers at 30/150/300 structure_range = +1 projectile each); −75% stat gains from pickup; −30 pickup range; turret spawns center, copies best ranged weapon. Advice (Ceph "The GIGATURRET"): waves 1–4 collect everything (economy first); feed the turret w5→max tier ("powered up by wave 12"); then take some, not all; play around the turret early, ON it later; let elites/bosses die to the turret. Implemented: 3-phase gold value (0.8 / −2.0 / +0.4) + turret anchor leash from phase 2, `BOTLOG BUILDER phase=` telemetry.

### captain
Mechanic: +60 XP per free weapon slot, double level-up stats, triple XP needed; enemies gain +2 HP/+2 dmg permanently EVERY wave. Advice ("HARD MADE EASY"): mostly a shop puzzle; be increasingly careful — enemy damage compounds. Bot: kite radius growing with wave (~1.0→~1.4 by w20); else default. Confidence medium.

### chef
Mechanic: consumables EXPLODE and ignite on pickup (burn = 5× consumable value); +200% dmg vs burning, weak vs unburned; +35 luck. Advice ("EN FLAMBÉ"): wait to step on fruit until enemies are in range; drag packs over ground consumables; full-HP food pickup is CORRECT (inverse of default). Bot: consumable gate = enemies within explosion radius (else avoid); route through fruit when chased. Confidence high.

### creature
Mechanic: weapon damage scales with Curse; −10 range and −5 XP gain EVERY wave end; +1 curse/level. Advice ("EASIEST ABYSS WIN"): get close (range shrinks anyway); lap the arena EDGES ~w16 for curse-alien spawns; never stand still; materials worth most early (XP decays). Bot: kite shrinking with wave; edge patrol mid/late; pickup high early → taper; never still. Confidence high.

### curious
Mechanic: +2 loot aliens per wave, loot aliens strengthen per kill; +2% XP per different item. Advice ("MOST AWESOME CHARACTER"): kill every loot alien — that IS the economy (~38 free items); they flee on spawn — chase immediately, even tanking hits; spawns on 5s marks — abandon chase if <5s left in wave. Bot: seek-loot-alien term overriding kiting, cutoff at wave timer <~5s; all-pickups high; no anchor. Confidence high.

### diver
Mechanic: Harpoon Gun (min range!) + melee; ranged hits mark enemies +300% damage taken 3s; +250% enemy HP. Advice ("ULTIMATE POWER"): keep enemies OUTSIDE harpoon min range so the debuff lands first; orbit elites at harpoon range, re-space when debuff drops; wave 1 don't kill trees (can't be debuffed — wasted autofire). Bot: kite >1 (hold harpoon range, esp. elites); avoid-kill trees on wave 1 only. Confidence high.

### druid
Mechanic: +3 fruit drops; 33% chance +1 Luck per fruit eaten (any HP); 33% of fruit is POISONED (unblockable ~8–11 dmg); no regen/lifesteal — fruit is the healing. Advice ("BREAK The Game EVERY TIME"): eat everything at high HP including red fruit; when HP unreliable keep a healing bank on the ground and stop chain-eating reds; don't stand on fresh tree drops. Bot: fruit strongly positive at HP >~65%; below: seek safe fruit only, cap consecutive pickups by HP budget. Confidence high.

### dwarf
Mechanic: kill ≥6 enemies with ONE hit → +engineering (compounds into melee dmg); melee only, −100 AS, −20 dodge. Advice ("Build Up to MASSIVE DAMAGE"): flee first to CLUMP enemies, then wade in and kill the group with one swing; time swings (walk in fresh); after ~w9 density does it for you; elites = pure evasion (awful single-target). Bot: herd-then-strike — hold outside weapon range until nearby count ≥ ~6, then drive through cluster center; elite → max kite. Confidence high.

### gangster
Mechanic: steals an item every shop (chance to spawn a random elite); each elite KILLED permanently buffs future elites (+15% HP); always elite waves, never hordes. Advice ("STEAL TO SURVIVE"): if you can't fight an elite effectively, RUN — never-killing-elites all run is a real strategy (avoids the stacking); decide fight-or-flee at wave START, not mid-fight. Bot: elite avoid-kill flag (default full-avoid unless a strength heuristic clears it); large elite kite radius. Confidence high (heuristic medium).

### hiker
Mechanic: +5 gold per 10 STEPS, +1 max HP per 80 steps, −50% drops, −5 speed. Advice ("GOTTA GO FAST"): NEVER stop — income and HP are literally steps; big perimeter laps (w16–18 "circles around the outside"); curved turns, no instant reversals (reversal registers as motionless); leave materials — steps compensate; never fight elites. Bot: never_still + perimeter-loop anchor + reversal penalty (the arbiter's W_REVERSE helps already); low pickup detour value; elite flee. Confidence high.

### ogre
Mechanic: enemies overkilled ≥2× max HP EXPLODE, chaining; melee only, −50 AS, −10 speed; first two special waves always hordes. Advice ("INSTANT WAVECLEAR"): clump then one-shot chains (Dwarf's pattern); very slow early — discipline until speed fixed; leave consumables until damaged; kite-disengage-return vs charging elites; don't break drooler houses. Bot: herd-then-strike shared with dwarf; consumable HP-gate; cautious early → wade late; elite kite-and-return cycles. Confidence high.

### romantic
Mechanic: hits on low-HP enemies can CHARM them (fight for you 8s then die into materials); −3% dmg and −1 armor per 5 Curse, +1 curse EVERY wave (decay all run). Advice ("MY ARMY NOW"): normal SMG kiting; loss = entering boss fights with decayed armor — caution scales up all run; elites/bosses can't be charmed. Bot: kite growing with wave/curse stat, jump on elite/boss waves; exclude charmed enemies from the threat field (readable: charm state already checked in world_view `get_charmed_by_player_index`). Confidence medium.

### sailor
Mechanic: naval weapons +200% vs CURSED enemies; +25 curse (more cursed spawns); dodge cap 20; −100% harvesting gains. Advice ("7000 DAMAGE ATTACKS"): no dodge safety net — never walk into attack strings; kill cursed enemies (money + easy kills); ELITE TECH: blunderbuss refires on every material pickup — circle the elite while continuously vacuuming materials so it never stops firing. Bot: pickup strongly positive and KEPT high during elite/boss waves (route orbit through drops); moderate kite; slight bias toward cursed enemies. Confidence high.

---

## Implementation status (built 2026-08-23)

`CHARACTER_PROFILES` in `world_view.gd` is a table of rows; an absent character or absent key is
baseline, so the table records only real deviations. `gather()` resolves the row into a plain
`profile` Dictionary (numbers only — the scorer never learns a character's name), which
`player_movement_behavior.gd` hands to `Arbiter.choose(..., profile)`.

Built, all ablatable with `--arb-charprofile=0`:

1. **Caution** — multiplies the five threat weights before `_prepare` (composes with pin escape via
   one shared save/restore). >1 keeps distance, <1 tolerates contact. Supports `caution_phases`
   (wave-banded) and `caution_per_wave` (compounding, for captain/romantic).
2. **Engage** — contact seeking: cost for ENDING far from the nearest target, capped
   (`ENGAGE_NORM`/`ENGAGE_CAP`). Gated by `engage_hp` (HP band) and/or `engage_pack` (clump must form
   first). Suppressed while any boss lives unless the row sets `engage_boss` (knight only) — the
   research is unanimous that these kits walk into trash, never elites. Deliberately a separate
   pull, not a threat discount, so dashes and corridors still outscore it.
3. **Anchor** — one two-sided ring in the arbiter: `anchor_radius` costs straying out (leash),
   `anchor_inner` costs closing in (keep-out). Modes resolve the point: `builder` (BuilderTurret,
   phase-2+), `structures` (centroid of own structures — the Engineer "pod"), `center`,
   `perimeter` (center point + inner only, so the cheapest floor is the rim and the bot laps it),
   `away_structures` (mage). `anchor_wave` delays engagement.
4. **Still** — `prefer` sets `prefers_still`; `never` adds `NEVER_STILL_COST` to the ZERO candidate
   (speedy loses 100 armor standing, hiker's income is distance). Stillness also now gets hysteresis
   stickiness like any other heading, which is what stops Streamer's 1-second income tick being
   reset by a twitch.
5. **Food modes** — `full_hp` (farmer/druid: paid for eating at max HP), `bomb` (chef/glutton: value
   = enemies within `FOOD_BOMB_RADIUS` of the fruit, negative when alone), `bank` (mildly negative at
   full HP — the ground is the safest inventory), `none` (golem/vampire), else baseline missing-HP.
6. **Gold modes** — flat `gold`, `gold_phases` (wave-banded), `builder` (turret-tier phases),
   `enemy_gated` (lucky: pickups deal damage, worthless on an empty floor), `metered` (buccaneer:
   reads live `player.current_weapons[].._current_cooldown`, so gold is only worth stepping on while
   something is actually cooling).

Telemetry: `BOTLOG PROFILE char=<id> <row>` once per character, plus the existing
`BOTLOG BUILDER phase=`.

Note: `prefers_still` is now table-driven, so `--arb-charprofile=0` also disables Soldier's
stand-still. That makes the control arm cleaner (it is character-specific logic) but means the flag
is no longer a pure arbiter-only ablation for that character.

### Builder second pass — THE TIGHT LEASH (2026-08-25, `20260825-w8-builder-d6-hp17`: the user's
Steam run, wave 9 replay, Danger 6, 17 HP, three shredders, turret tier 2 = feed phase)

User: "get the bot to stay closer to the builder turret". New `anc=` telemetry (px to the profile
anchor) showed the old leash — radius clamp(turret range, 220, 420) → 420 at tier 2, weight 12 —
holding the bot at a **mean 611–675 px** from the turret (max ~1,100): outside the turret's kill
zone most of the wave. Fix: `BUILDER_ANCHOR_MIN/MAX` 140/240 and a per-row `anchor_w` multiplier
(new generic key; Builder 2.5 → slope 30 per 300 px) so the leash can out-argue crowd room but not
a live threat; `--arb-leash=<px>` sweep knob. A/B on the bed: old **1/3, avg dmg 29, mean 611–675
px** → tight **3/3 (two at 0 dmg), avg dmg 8, mean 196–271 px**, kills unchanged (~405), materials
43–64 vs 12–32 (standing in the kill zone means walking over some drops — the guide's "a material
here or there is no big deal"). The guide's "playing directly on top of the turret" from mid-game
is now what the bot does.

### Bull and Pacifist strategies (built 2026-08-24, UNMEASURED — no snapshots exist)

Sources: full transcripts of Cephalopocalypse's "How to Beat Bull WITHOUT Self Damage" and "Pacifist
Danger 5 Guide and Walkthrough", plus decompiled mechanics.

**Bull** — weaponless; every damage instance that lands (armor-reduced; dodged hits do NOT trigger)
detonates a 150 px explosion at 300% of melee+ranged+elemental (`bull_explosion_stats`, base 30);
+20 HP, +15 regen (+50% regen mods), +10 armor. Guide doctrine: kite in loops so the crowd bunches,
then dive so ONE hit kills the pile ("take the hit in the middle of a big group"); dodge procs give
i-frames to push deeper; back off and regen when low; never fight elites (without self-damage items)
but keep farming the trash on elite waves; stand beside spawns, never on the red X (relocates the
spawn); burst the pile right before the horn; slashers flee — don't chase. Row:
`caution 0.5 / caution_below [0.6, 1.3]` (kite hard while regen refills), `engage 14, engage_hp 0.6,
engage_mode cluster` (NEW: candidate priced by bodies inside the blast at its END position, boss
excluded, plus 0.4× nearest pull to start a pile), `engage_pack 3`, `engage_boss "trash"` (farm on
elite waves, never the elite), `engage_end_hp 0.4 / end_secs 8` (pre-horn burst), `dps 0` (no
weapons — the kill reward is noise), `avoid_births 90`.

**Pacifist** — 0.65 materials+XP per enemy ALIVE at the horn (`main.manage_harvesting`, halved on
horde waves); −100% damage; lumberjack shirt. Stepping on a red X (`EntityBirth`, 72 px marker)
cancels the spawn = lost income. Guide doctrine: lap the outside edge all wave with hands batting the
crowd away; walk AWAY from spawns; loot aliens are uncatchable; consumables heal 0 once worms stack;
trees are the only kills and crates — reach them before the horn; elites: just stay away; chargers:
stop if head-on then change direction, keep moving if from the side. Row: `anchor perimeter
(inner 520)`, `still never`, `caution 1.2`, `food none`, `dps 0` (NEW key: kill reward ×0),
`loot_value 0` (NEW), `tree_value 5` (NEW: trees from `spawner.neutrals` as rewards),
`avoid_births 160` (NEW: active `EntityBirth` markers priced as small standing AoEs).

New generic mechanisms this added: `dps` scale, `loot_value`, `tree_value`, `avoid_births` (serves
jack/king/lich too — not yet on their rows), `caution_below`, `engage_mode cluster`, `engage_boss
"trash"`, `engage_end_hp`. Targets now carry `TG_BOSS`.

**Pacifist — MEASURED 2026-08-24 on the user's failing run** (`20260824-pacifist-current`: wave 6,
Danger 6, six hands, harvesting 76, but dodge 15 / armor 3 / regen 1 / speed −2; the bed loads at
34/34 HP). Profile resolves live, zero errors. Five arms × 3 runs, **0/15 valid survivals**, every
death to CHARGERS (3–7 hits/run, plus slashers and 212 px/s bullets):
default perimeter (inner 520) 2 deaths + 1 harness artifact; `--arb-inner=400` 0/3; generic
`--arb-charprofile=0` 0/3 and FASTEST deaths (t=14–27); `--arb-latent=2.5 --arb-dash=2.0` 0/3;
`--arb-centermode=450` (rim → center anchor) 0/3 with the bot clear of walls (min edge 56–97) and
still 7 charger hits. Attribution: not the rim, not the wall — a Pacifist never thins its chargers,
so they accumulate all wave and land on a potato with 15 dodge and −2 speed that cannot sidestep a
1000 px/s dash in the 0.4 s wind-up. The guide's rim lap is played on 60 dodge, 20+ regen and bought
speed with snail/ugly tooth slowing the crowd 35%. **Verdict: build ceiling, not steering.** The
profile is kept as designed (rim orbit is right once the defensive stats exist). New sweep knobs:
`--arb-inner`, `--arb-centermode=<radius>`. Untested idea: the guide's "stop if the charger comes
head-on, then change direction" — the arbiter already dodges corridors perpendicular; a stop-then-
turn variant would need a dash-specific candidate.

**Pacifist second pass — THE ANNULUS (2026-08-24 late, `20260824-w2-pacifist-d6-hp3-last`: the
user's new 12-HP Pacifist that died on wave 3 twice in one live log):** the live BOTLOG series
showed the rim orbit running the WALL BAND itself (edge 24–48 along the top and right walls) with
the crowd in a conga line behind and every hit landing pinned — at inner 520 on a 2164×1536 arena
the "cheapest floor" is 250 px from the short walls, and the swarm fills the inward escape. Fixes:
(1) orbit is now an ANNULUS — `anchor_inner 340, anchor_radius 560` — so the lap runs mid-arena
with ≥200 px of wall room; (2) spawn-marker keep-outs moved to a new `KIND_MARK` that prices
contact only and is skipped by crowding/enclosure (a ring of red X's was reading as a surround).
Measured on the wave-3 bed: baseline **0/3, 12 dmg each, dead at t=17–26, min edge 12–36** →
annulus **2/3 survived, avg dmg 9, min edge 84–108**. Wave-6 bed unchanged at 0/3 (chargers —
the build-ceiling verdict above stands). Bull inherits KIND_MARK through `avoid_births`.

### One-Armed — MEASURED (2026-08-24, the user's losing Steam run)

Bed `20260824-w9-one_arm-d6-hp36-ghost_axe`: wave 10 replay, Danger 6, **36 HP**, one tier-3 ghost
axe (3,949 dmg the previous wave), 10% lifesteal, dodge 6, armor 2. A MELEE One-Armed — the guide's
row assumed the ranged build it recommends from ~wave 5 (centre leash 520, caution 1.1), which holds
a melee fighter away from the contact that feeds its lifesteal. Built: generic **`if_melee`** row
overlay (applied when the loadout has no `RangedWeaponStats`; `_all_melee`) — One-Armed's overlay
plays it like Wildling: caution 0.7, `caution_below [0.35, 1.3]`, `engage 8 / engage_hp 0.35`, and
a WIDE centre leash (620) because every death landed at edge 12–24.

Five arms × 3, **0/15**: base row avg dmg 80 (kills 186–250); overlay 87 (up to 279 kills);
overlay + `--arb-pin=1` 73 (`pfire` 7–10/run — the escape fires and the brawl drags it straight
back); overlay + leash 620 **63 (best)**; leash + pin 77. Per hit on this wave: baby alien 9,
chaser 9, charger 12, 220 px/s bullet 15 → four hits kill the 36-HP body, and one run absorbed 116
through lifesteal without surviving. Verdict: the melee overlay is kept (it is the right shape and
the cheapest arm), but **36 HP at wave 10 Danger 6 is a build ceiling** — the guide plays One-Armed
melee only through wave 5 and is ranged with room to kite by here. Steering cannot buy HP.

**Second pass — the user asked "if it just gets cornered and hit repeatedly, how does more HP
help?"** — and the interleaved timelines proved the ceiling call premature: HP was being REFILLED
between hits (17→33, 11→27 via lifesteal+regen); the damage arrived as clusters at the wall; and the
bot went to the wall AT FULL HP, chasing rim spawns — engage 8 + kill reward 14 outbid the wall
term's ~13 and the 620 leash cost ~5 there. Built **`fight_room`** (generic): a candidate ending
inside N px of a wall earns no engage pull and no kill reward (costs untouched, so it still leaves);
One-Armed melee overlay and Bull get 220. Result on the bed: still 0/3 (avg dmg 61), but the
death modes split — runs still drifting to the wall now do so under THREAT costs (herding: "away
from 30 enemies" points at a wall), while one run died entirely mid-arena (hits at edge 333–650,
9+13 in one second). Closing arms: `--arb-wall=32` 0/3 with only **6/20 hits in the wall band**;
`--arb-predict=16` 0/3, 8/16. Refined verdict: the chasing-to-the-rim bug was real and is fixed;
the remaining wall drift is the arbiter's unsolved herding problem (not One-Armed-specific); and
70% of the damage now lands mid-arena in the brawl, where HP and armor genuinely are the lever.
Lifesteal heals 8–11 between clusters on this build; it needs a body that survives the cluster.

**Bull sixth pass — THE DAMAGE DIVE (2026-08-25, user: "allow dives that don't kill enemies if
the bot can survive and there's a good amount of damage to be dealt").** Bodies the blast only
HURTS (killability < 0.5) used to pay full contact price and a pile of them vetoed the dive. Now,
while the dive is armed, they pool separately and bill at most `DAMAGE_DIVE_HITS` (2) hits — the
detonating hit plus one follow-up — provided `hp_ratio >= DAMAGE_DIVE_HP` (0.5) and
`blast × (killable + surviving bodies in blast) >= DAMAGE_DIVE_MIN` (350; with a 156 blast that is
three bodies, fewer when mixed with killables). Fail either and full price as before; elites,
bullets, dashes and out-of-blast bodies never pool. Row key `damage_dive: true`; the resolver
passes `hp_ratio` and `blast` (= the explosion reference). Measured NEUTRAL on both beds (w10 0/3,
dmg 166–188, kills 210–287; w5 3/3, dmg 93–106) — these waves carry almost no blast-surviving
bodies besides stray pursuers. The w11 pursuer horde (five live deaths, 46 pursuer hits) is where
it should show; no bed exists for it yet.

**Bull fifth pass — "still needs to be more aggressive" (2026-08-25 AM).** The test-game save was
the same 07:55 state as the w10 bed and the launcher log was still the pre-fix (band 0.6) run, so
the impression predates the fixes. Baseline on the band-0.25 build: 0/3, 183–213 dmg, 245–348
kills, dive armed 28–33 s of ~45, **10–14 s of `pack` dead time** (fewer than 3 enemies within
320 px → engage 0, no pull at all). Built generic `engage_pack_seek` (fraction of engage kept as a
plain nearest-enemy pull while no pile exists; resolver drops cluster mode for it; telemetry
`eblk=seek`). Bull at 0.6 measured WORSE: 0/3, deaths at t=38–42 (vs 43–53), kills 187–232,
nearest-enemy mean 159–182 (no closer). Hunting stragglers scatters the pile before it forms —
the guide's loop-to-gather in numbers. Reverted to 0 for Bull; key kept for kits that want it.
Verdict unchanged: the Bull is already diving 28–33 s a wave at ~8 kills per hit; on this bed the
limit is sustain, not aggression.

**Bull fourth pass — the wave-10 deaths analysed (2026-08-25, bed `20260825-w9-bull-d6-hp26`:
wave 10, Danger 6, 64 HP, 16 armor, 21 regen, 0 dodge, explosion 156; live deaths at w10 corner
and 5× on the w11 horde).** Live w10 timeline: dove well early, then at 37/64 the 60% band
disarmed the dive and never re-armed — 20 s of kiting at 52–65% while the un-thinned crowd grew
22→47 and herded it into a corner; died with the dive OFF. w11 horde: 46 pursuer hits — 250 HP vs
a 156 blast, yet the flat kill_ref 90 admitted them to the one-hit trade. Fixes: band 0.6→0.25,
`explosion_ref` (kill reference = real blast damage from live stats, `BOTLOG DPSREF explosion=`),
`EXPLODE_KILLABLE_MIN 0.5` (one-hit pricing only for bodies that die to one blast), `--arb-engagehp`
knob. Bed results, all 0/3: baseline 174–204 dmg (`hp`-mode 18–25 s); fixed band 0.4 181–205;
`--arb-engage=2` 171–200; band 0.2 149–211; band 0.0 154–222 with **hits fully paid (ok=142–182),
375 kills / 255 mats, died 4 s short**. Hit attribution: ~36 hits/wave × 5.4 = 4.3 dmg/s incoming
vs ~2.3 HP/s regen; unpaid (retreating) hits were 25–35% of damage at band 0.4 and 0% at band 0 —
and survival did not change. Verdict (supported this time by the timeline): the dive works — every
blast ~8 kills, the crowd is cleared, income is huge — and the wave is a **sustain ceiling** for a
21-regen / 0-dodge Bull; the guide's Bull here runs 34→100 regen, dodge, and 50 luck for fruit.

**Bull third pass — MEASURED, and the passivity root-caused (2026-08-25, bed
`20260824-w4-bull-d6-hp33` = wave 5, Danger 6, 33 HP, the user's own run; "the bull play is too
passive").** Live log: 33/33 HP nearly all wave, hovering 80–270 px from a crowd that grew to 92.
New telemetry `eng=`/`eblk=` on the ARB line showed the dive was NEVER armed: `eblk=boss` every
second on a wave with no boss, and the run's **stderr** (`-iN.log.err`, which the error check had
not been reading) held 4,884 `Invalid operands 'String' and 'bool' in operator '!='` — the
`engage_boss "trash"` rule compared against `true` aborts `_engage()` every frame in GDScript 3,
so engage resolved to null and the Bull was a pure kiter whose kills came from enemies walking into
it. Fixed with `is bool` / `is String` guards. First-ever measured Bull, n=3:
baseline (gate crashing) 3/3, ~104 kills, ~95 mats, 13 hits, crowd peaking 46–64, avg dmg 47 →
**fixed: 3/3, 132–134 kills, 110–129 mats, 29–32 hits, crowd peaking only 31–36, avg dmg 98,
HP ending 16–19/33** with `eng=14 eblk=ok` 20–24 s of 40, `pack` 12–17 s (crowd cleared — nothing
to dive), `hp` 2–6 s (regen pause). Per-body cluster reward (cap 8), EXPLODE_CROWD 0.35, and the
`--arb-engage`/`--arb-cnear` knobs from the cadence pass are all in effect. The earlier
"per-body pricing didn't move the needle" and cadence-arm results were measured with the gate
crashing and are void.

**Bull second pass — THE EXPLOSION TRADE (2026-08-24 late):** re-reading the first-pass row
against the scorer exposed why the dive could never fire: every body in the pile was priced as a
separate contact hit, so three bodies in the blast cost ~48 to stand against while the cluster
reward tops out at 14 — the bot would kite forever. But Bull's FIRST landed hit detonates a 150 px
explosion that kills everything killable in the blast; the second and third hits never arrive.
Built `explode_trade` (generic key): while the dive is armed (engage > 0, i.e. inside the HP band),
contact costs of killable bodies whose horizon position lies inside `ENGAGE_BLAST` of the
candidate's END position pool and cap at the single largest coefficient — one hit, not N. Bodies
outside the blast, unkillable ones, bullets and dashes pay full price, so the dive is still vetoed
by anything the explosion would not answer. Also `kill_ref 90` on the row: with no weapons the
measured DPS reference sits at the 20 HP floor and nothing past wave 5 would count as killable;
the explosion is 30 base at 300% scaling, so the row states its reach. `fight_room 220` added in
the One-Armed pass (no diving into rim piles). **Still unmeasured — no Bull run exists in any save
rotation and DebugService has no character override.** Boot-clean; wiring-verified on the Soldier
and Dwarf beds (the changed `_prepare` path runs for everyone). Harvest one to bench; the risk to watch is the cluster dive committing into a
pile that contains a charger.

### Soldier eleventh pass — STANDING PAYS FULL FOR AIMED THREATS (2026-08-25)

User: "the bot stood still against too many enemies" (Steam run; the Steam copy loads the user's
own rezipped workshop build, verified constant-for-constant identical to the tree for Soldier;
Steam's godot.log carries only the PROFILE prints, no timeline). Bed `20260825-w4-soldier-d6-hp10-
stood` (wave 5 replay, Abyss — `current_zone 1`, lobsters confirm — 15 max HP, six shredders):
n=10 → 8/10, and both deaths were **bullets taken at `mv=(0,0)`** with `still=61 sok=1`, 3–10
projectiles airborne, including 200 px/s shots visible for two seconds. Root cause: the threat time
discount (down to MIN_DISCOUNT 0.15 past the horizon) encodes "a later frame can still dodge this"
— true for a moving potato, FALSE for the standing candidate, which is precisely what refuses to
move; so a slow bullet 300 px out cost the stand ~4 against the 16-point floor until it was too
close to sidestep on a 15-HP body. Fix (arbiter, all characters): the ZERO candidate takes **no time
discount on KIND_PROJ / KIND_DASH threats** (`_p_aimed`). Result n=10: **9/10, avg dmg 6** (was 8/10,
avg 9), slow-bullet (200 px/s) hits 5 → 1 across the ten runs, still-share unchanged (~90%), kills
unchanged (~110). The remaining death was two 550 px/s bullets plus one 200 — 0.5 s of warning on a
15-HP body is inside the sidestep time. Regressions: see below.

### Soldier strategy — MEASURED (2026-08-24, w2-d5-hp4-smg snapshot, n=3/arm)

Field report drove a third pass: the bot "does not sufficiently stop to shoot and runs away to its
demise". Root cause was a model falsehood: the DPS term paid moving candidates as if their weapons
fired, but Soldier's do not (`can_attack_while_moving = 0`) — kiting looked like free DPS, so the bot
kited, killed nothing, and lost by attrition. Fix: `fire_still` row key → standing collects a DOUBLED
kill payout, moving keeps only a 0.4× approach gradient, plus a flat FIRE_STILL_FLOOR when anything
is inside true weapon range (the scaled payout alone was ~3 on trash waves — under the room term's
wander pressure).

Measured on the genuine wave-2 snapshot (kills/mats/gold now in the WAVELAB RESULT line):
generic steering = **0 kills, 0 materials** every run (~9% still-frames — guns silent all wave);
floor 8 = 3/3/0 kills; **floor 16 + caution 0.7 = 15/12/3 kills, mats tracking 1:1, 20–48%
still-frames, and LOWER damage taken (avg 3 vs 4)** — standing and killing thins the swarm, so it is
also the safer policy. Remaining variance (the 3-kill run) looks spawn-position dependent.

**Tenth pass — THE STUTTER GATE (fire while fleeing):** user: "if it's running away and the speed
cost isn't too great it should try to fire." The tap gate had used `last_still_gap` (cost of a
FULL-HORIZON stand vs the move) — the wrong measure, since a stutter is the chosen move at 50%
speed, not a stand; every flight looked uninterruptible. Now the arbiter re-scores the winning
heading at `STUTTER_SPEED_FRAC` (0.5, must match TAP_MOVE/(TAP_MOVE+TAP_STOP)) with the same
scorer and exposes `last_stutter_gap`; the movement behaviour taps whenever that gap < TAP_SAFE_GAP
(35) and not pin-escaping (the wall-room gate no longer applies to taps — it exists to stop
STANDS re-anchoring at walls, and a stutter is not an anchor). Measured: colossus wave **2/3
survived, both survivors at 65–66/66 HP through 164–236 damage, 262–267 kills** (previous 6 runs
at the new admission threshold: 1/6); wave 9 **3/3, 0 damage, 579–588 kills** (unchanged — the
stutter gate never has to fire where the stand already wins). The remaining colossus death is the
early-burst mode (t=20, 26 kills) — spawn-position dependent, n=3.

**Ninth pass — TRADE-POOL ADMISSION (colossus snapshot = wave 17 elite, 66 HP, sustain build):**
field report "runs around too much without fighting back". Baseline 0/3 dead in 15–22 s, still
14–26%, kills 5–17; killers = pursuers at ~25/touch (74–94 of ~110 dmg), plus a 1 HP/s
`item_blood_donation` drain. Sweeps of trade budget (1.5), AoE weight (0.4) and stand floor (30)
were ALL null — the stand was being evicted by something none of them touched. `BOTLOG DPSREF`
(new) showed kill_ref=186 while wave-17 pursuers carry 10+24×16 = 394 HP → killability 0.32,
just under the 0.35 pool-admission bar: NOTHING entered the trade pool, every body billed the
stand at full price, and the budget that won wave 9 never engaged. `--arb-tradekill=0.15`
(admit anything that dies within ~6 s of standing fire): **1/3 survived, runs 54–60 s, kills
170–270, survivor healed to 66/66 through 159 damage taken** — the sustain build working once the
bot stands. Doubling the budget alongside added nothing (1/3, more damage) so TRADE_HP_SHARE
stays 0.5; TRADE_KILLABLE_MIN is now 0.15 by default. New knobs: `--arb-trade`, `--arb-floor`,
`--arb-tradekill`; new telemetry `sok=` (stand permission) on the ARB line and `BOTLOG DPSREF`.

**Eighth pass — CORNER ESCAPE (w12-d6-hp28 snapshot = wave 12, the run's FIRST ELITE wave,
gargoyle):** field report "the soldier bot gets cornered". Built: (1) pin-escape mode armed via the
profile (`pin: true`) with every stand perk yielding while it runs — escape at the loss of firing;
(2) a wall-DWELL trigger (PIN_DWELL 40 frames inside 150 px) because the stuck-test never arms on a
stutter-stepper; (3) the decisive piece — `_stand_ok` gates EVERY stand perk (floor, kill-discount,
trade budget, crowd-share, taps) on ≥ FIRE_STILL_WALL_MIN 220 px of wall room, because telemetry
showed the escape firing 3–4×/run (`pfire=`) and the perks re-anchoring the stand at the wall's edge
each time until the crowd pushed it in. With the gate the edge series bounce OUT of the wall band
repeatedly instead of pinning once. Result: still **0/3** on this wave (avg dmg 56 vs 83 baseline;
`--arb-predict=16` also 0/3) with deaths now spread across chasers/pursuers/baby aliens/gargoyle
bullets rather than one pin signature — consistent with the guide's stated loss condition (first
elite at < ~40 max HP; this run has 28). Verdict: steering has done its part; this wave is a
build/HP ceiling. Wave-9 regression check of the gate: **3/3, 0 damage every run, 564–604 kills,
pfire=0** — the gate and dwell trigger never fire on a wave the stand controls, so they are free
where the profile is winning and only engage where it was dying.

**Seventh pass — THE DAMAGE TRADE + aggressive stutter (w8-d6-hp42 snapshot = wave 9, the
run-killer):** field report: "the bot starts running away and never starts fighting again once
enemies get close." The spiral's arithmetic: a close crowd prices the stand as the SUM of every
body's contact cost, flight prices near zero, so flight wins every frame — but flight fires nothing,
the crowd never thins, the gap never closes. Fix: standing's contact costs from KILLABLE bodies
(killability > TRADE_KILLABLE_MIN 0.35) pool and cap at `current_hp × TRADE_HP_SHARE 0.5` — a
bounded fee for uninterrupted fire, shrinking as HP drops; elites/bullets/dashes stay outside the
pool at full price. Stutter tuned aggressive: TAP_MOVE 4→2 (~50% travel speed, more volleys),
TAP_SAFE_GAP 25→35. Measured on wave 9 Danger 6 (42 HP): baseline **0/3, avg dmg 59, kills
155–332**; with trade+stutter **3/3 full 60 s clears, avg dmg 5 (two at ZERO), kills 574–593, gold
~640, still 65–70%** — the wave that ended the user's run became a farm.

**Sixth pass — TAP-MOVE INTERLEAVE (the breakthrough) + DPS-aware killability:** the game fires
every ready weapon on the FIRST frame movement input is exactly zero (weapon.gd should_shoot) and the
+50%/+50% standing stats apply the same frame (player.gd check_not_moving_stats — no timer; only
Streamer's tick delays). Movement is instant-velocity. So the movement behaviour now interleaves
moving with stop-frames whenever the arbiter's chosen move is REPOSITIONING rather than a dodge
(gate: arbiter exposes `last_still_gap` = cost(stand) − cost(best); tap only under TAP_SAFE_GAP 25):
TAP_MOVE 4 frames travel, TAP_STOP 2 frames volley = ~67% travel speed with near-continuous fire.
Separately, killability (both the kill reward and the standing discount) now references the CURRENT
loadout's measured DPS (`_refresh_kill_ref`, 1 s of fire, floored at the old 20, capped 600,
`--arb-dpsref=0` control) instead of a static 20 HP. Measured, both user snapshots, n=3:
w6-d5 3/3 survived, avg dmg 3 (was 11), kills **180/182/185** (was 24–150); w3-d6 — previously 1/3
with 13–30 kills — **3/3, avg dmg 1, kills 69–78, two 0-damage clears on each bed.**

**Fifth pass — crowd-share + discount 0.9 (w5-d5-hp17-6guns snapshot, the user's own run):** with the
kill-discount at 0.75 the bot still spent 60-90% of the wave relocating (still 9-39%, kills 33-87):
mid-game trash at 15-30 HP has killability ~0.4 so the discount only shaved a third, and the room +
enclosure terms structurally pay every flee candidate (which ENDS farther from the swarm) over the
stand. Fix: FIRE_STILL_KILL 0.9 and FIRE_STILL_CROWD 0.5 — the standing candidate pays half the
crowding/enclosure costs, because those terms measure how bad a spot is for a potato that must
escape it, and a firing Soldier is thinning it instead. Measured: **best run 83% still, 150 kills,
143 mats, 0 damage taken** (previous best 87 kills / 20 dmg); avg dmg 25 → 11; one death remains in
3 (charger dashes + chasers, full-priced correctly — not a standing-into-death pattern). Variance
across runs is high; n=3.

**Fourth pass — the kill-discount (from Cephalopocalypse's Soldier transcript, mined in full):** the
human stands while trash is actively APPROACHING, because standing is what kills it before contact
("move towards it and stop"; deliberate tanking of charge-through elites). The threat model priced
every approach as if the body survives to touch — false exactly when standing shoots it down. Fix:
contact threats carry a killability field (T_KILL, same KILL_HP_REF falloff as target values) and the
STANDING candidate's contact coefficients are discounted by `FIRE_STILL_KILL (0.75) × killability`;
moving candidates pay book price (fleeing shoots nothing); projectiles/dashes untouched. Measured on
the user's genuine w3-d6-hp11 run: control = 0 kills / 0 mats / 6 gold every run; profile =
**30/13/15 kills, mats 1:1, gold 36/19/21, still-share 22–37%**, survival parity 1/3 both (n=3,
11 HP on Danger 6 — the steering pacifism is fixed; survival there is now a build/HP problem).

### Soldier strategy (built 2026-08-23, second pass)

Three pieces on top of `still: prefer` (which doubles the DPS payout for the ZERO candidate):
1. **Stop-bonus** (arbiter continuity term): mid-dodge, hysteresis handed every keep-going candidate
   ~w_hyst that stopping did not get — a tax on the tap-mover's core move. The ZERO candidate now
   prices level with continuing whenever `prefers_still`, so a dodge ends the instant threat terms
   stop demanding motion. Threats (15–65) still trivially outbid the 1.2 bonus while live.
2. **Mid-wave gold stays 0.3** — the +200% pickup radius collects passively; detours cost firing time.
3. **End-of-wave sweep** (`gold_end: 1.6, end_secs: 8`): in the final seconds gold jumps to seek
   value and — generically — any anchor lifts, so pod-dwellers can actually leave to sweep.
   Engineer and Streamer got the same keys (`end_secs: 6`, per the "~5 seconds remaining" guide line).

This built the **wave-clock plumbing** (`world_view.wave_time_left` from `main._wave_timer.time_left`;
0 when the timer is stopped, which correctly reads as "wave over"), which unblocks cyborg/golem/
masochist phases below.

### Not yet built (needs game-state plumbing)

- **Wave-clock phases beyond the end-sweep** (cyborg's half-wave ranged→melee switch; golem/masochist
  end-of-wave dives). The clock itself is now plumbed (`wave_time_left`); these need caution/engage
  keys banded on it, analogous to `gold_end`/`end_secs`.
- **Tree repulsor/attractor** (cryptid/explorer). Trees are queued via
  `entity_spawner.queue_to_spawn_trees`; where LIVE trees are held still needs locating.
- **Spawn-marker avoidance** (pacifist/jack/king/lich). The red-X telegraph scene is not in
  entity_spawner.gd — find what `spawn()` instantiates.
- **Corner anchoring** (fisherman/saver funnel play) is approximated by `perimeter` today.
- **Charmed-enemy threat exclusion** (romantic) — `world_view._add_unit` already skips charmed units,
  so this is likely already correct; unverified.


## Tracker reproduction: Pacifist, brotatotracker.com run #31194 (2026-08-25)

Real Nightmare (danger 6) Abyss win, unmodded, no retries, rebuilt wave by wave
from `/api/runs/31194/waves/{n}` with `tools/tracker2build.py` + the WaveLab
`--wavelab-build` mode (every stat matched the record exactly, 20/20 waves).
Snapshots `20260825-w{n}-pacifist-d6-hp*-tracker31194.json`. Bot replay,
ARBITER on, speed 1, random seed per iteration, 3 iterations per wave:

| wave | event | HP | result | avg dmg | note |
|---|---|---|---|---|---|
| 1 | | 10 | 3/3 | 0 | |
| 2 | bullet hell | 11 | 3/3 | 6 | |
| 3 | | 13 | 3/3 | 3 | |
| 4 | bullet hell | 23 | 3/3 | 13 | |
| 5 | | 25 | 3/3 | 8 | |
| 6 | fog | 27 | 3/3 | 17 | |
| 7 | bullet hell | 37 | **1/3** | 38 | died at 38 s and 43 s |
| 8 | bullet hell | 40 | **1/3** | 84 | died at 45 s and 50 s |
| 9 | | 45 | **2/3** | 71 | died at 43 s |
| 10 | | 73 | 3/3 | 70 | |
| 11 | elite | 77 | 3/3 | 133 | |
| 12 | bullet hell | 95 | 3/3 | 78 | |
| 13 | fog | 107 | 3/3 | 120 | |
| 14 | bullet hell | 123 | 3/3 | 205 | |
| 15 | elite | 132 | 3/3 | 92 | |
| 16 | | 136 | 3/3 | 191 | |
| 17 | elite | 137 | 3/3 | 217 | |
| 18 | fog | 166 | 3/3 | 189 | |
| 19 | bullet hell | 179 | 3/3 | 200 | |
| 20 | two bosses | 183 | 3/3 | 296 | |

Total 55/60. The human won every wave with this build; the bot's gap is waves
7-9 (37-45 HP, 100+ threats, 25-30 live bullet-hell projectiles at 550 px/s
for 7 each, plus 90 slow projectiles on w9). Every death shares one signature:
the bot is at the map edge (`edge=12..36`) and 700-1200 px outside the
perimeter annulus (`anc`, band 340-560) when the contact hits land
(viperfish/anglerfish 8-12 each). From wave 10 on, 21+ regen and 60+ HP carry
the same play. Next: w7/w8 bed for the edge-pinning under bullet hell.

### Pacifist w7/w8 fix pass (2026-08-26) — pin dwell, orbit, decision interval

Beds: the tracker w7 (37 HP) and w8 (40 HP) snapshots above, ARBITER, speed 1,
random seeds. Baseline 1/3 + 1/4 (≈2/7). Weight knobs first (n=4 per wave):
anchor ×3 4/4 + 2/4, wall ×3 3/4 + 2/4, both 1/4 + 0/4 — noise, as the
arbiter's own note on pinning-by-weight predicts.

1. **`pin_dwell` row key** (+ `--arb-pindwell`): the Soldier's wall-dwell
   trigger generalised to any pin row. The Pacifist slides along the wall
   under bullet hell, so the stuck detector never fires (`pesc=0`). Pacifist
   row `pin: true, pin_dwell: 60`. Arms, n=5 per wave (w7 + w8): dwell 25
   **3/10**, dwell 45 **6/10**, dwell 70 **8/10**.
2. **`orbit` row key** (+ `--arb-orbit`): outside `anchor_radius` the
   outward radial component of the heading costs, inward pays, tangential
   earns half, ramped by distance out. Pacifist `orbit: 30`. With dwell 60,
   n=5 per wave: default (orbit 30) **8/10**, orbit 0 **7/10**, orbit 60
   **4/10** — 30 kept, evidence thin; 60 clearly walks into the crowd.
3. **`tick_step`**: the pin counters count `choose()` calls; under a decision
   interval they silently stretched (w4/w9 deaths at `edge<110` for 4 s with
   `pfire=0`). Fixed by telling the arbiter the interval. After the fix, n=5:
   tracker w4 4/5, **w8 5/5**, w9 3/5; Soldier w12-d6 1/5 (0/3 before),
   colossus 3/5 (2/3), w5-d6 15-HP 3/5 then 8/10 every-tick, w5-d5 6guns 5/5.

Full sweep after 1+2 (before 3): 55/60 again, redistributed — w7 3/3, w8
1/3, w9 1/3, w4 2/3. Pooled w8 since the fix: 5/5 + 4/5 + 1/3 = 10/13 vs
2/7. **w9 stays open**: escapes fire (`pfire` 3–5) but the bot is herded
outward through 40–94 slow 13-damage projectiles and finished by narwhal /
slasher contacts — a projectile-field dodging problem, not pinning.

**Lag** (user report: "the game lags when the wave gets fuller"): new `us=`
field in the ARB line = microseconds in gather+choose. Empty field 0.2 ms;
100+ threats **8–12 ms per physics tick** against a 16.7 ms budget — the
steering is the late-wave stutter. Built an adaptive decision interval
(`--arb-every`: skip alternate ticks while a decision costs > 5 ms). A/B,
n=10: loud-w11 (croc chain-dasher + boosting pursuers) every-tick **6/10 vs
adaptive 3/10**; fisherman w2 9 vs 10; Soldier w5-d6 8 vs 7; tracker w7+w8
7 vs 8. The 33 ms reaction gap is fatal exactly on the dasher bed, so the
**default is every tick**; `--arb-every=0` opts into adaptive for lag-bound
live play. ARBITER bed with adaptive on: 89/100 (loud-w11 3, fisherman 8,
wildling 8, renegade 10, rest 10) vs 93 — the loud-w11 drop is the interval.

### Wave 9 dive (2026-08-26) — open

Bed `20260825-w9-pacifist-d6-hp45-tracker31194.json` (45 HP, 9 armor, 32
dodge, 19 regen; no Nightmare event; 100+ threats, 40–94 slow 13-damage
projectiles from shrimp/bat/dragonfish/hermit in the crowd). Timelines: the
bot holds the annulus (`anc` 330–600) at full HP for ~22 s, then drifts out
to `anc` 800–1200 / `edge` 12–36 as the slow-lane count passes ~20; every
hit of every death lands there, as bursts (narwhal/slasher 10 + plankton 4 +
a 13 bullet inside ~2 s) that 19 regen cannot cover. Escapes fire
(`pfire` 3–5) and it returns to the wall.

Arms, n=6 unless noted (pooled where repeated):

| arm | w9 | w7 | w8 |
|---|---|---|---|
| default (orbit 30, anchor ×1, dwell 60) | 6/11 | 7/8 | 10/13 |
| anchor ×2 (`--arb-anchor=24`) | **10/12** | 6/6 | 3/6 |
| anchor ×1.5 | 2/6 | | |
| orbit 45 | 10/12 | 3/6 | 2/6 |
| anchor ×2 + orbit 45 | 4/6 | 3/6 | 2/6 |
| orbit ramp from inner radius (`--arb-orbitfrom=340`) | 3/6 | | |
| wall ×2 | 5/6 | | |
| scan 250 / 150 px (slow-lane warning) | 4/6 / 4/6 | | |

Anchor ×1 → ×1.5 → ×2 reads 6/11 → 2/6 → 10/12: the knob space is at the
noise floor. Orbit ≥45 costs waves 7/8 outright. The slow-projectile-scan
hypothesis (lane floors summing into an outward gradient) is refuted by the
scan arms. Defaults kept. What is left is structural: the bot needs to
prefer crossing a thin lane early (while `anc` < 600) over being walked to
the wall — a lookahead longer than 0.8 s on the herding direction, or a
"where will I be in 3 s" runway term against the crowd rather than the wall.
`orbit_from` row key / `--arb-orbitfrom` added for the experiment (default =
anchor_radius, no behaviour change).

## Tracker reproduction: Explorer, brotatotracker.com run #27048 (2026-08-26)

Nightmare Abyss win, unmodded, no retries: tasers -> thunder swords, speed
35-49, 10-15 HP through w5, 38 at w10, regen 48-60 late; fog 5/11/18, horde
12, elites 15/17. Built 20/20 waves with zero stat mismatches
(`20260826-w{n}-explorer-d6-hp*-tracker27048.json`).

**Baseline sweep (row `{caution: 1.3}`), 3 per wave: 58/60** — every wave
3/3 except w9 (33 HP) 1/3: both deaths two 22-damage `v=300` bullets taken
at edge 36-42 (the Explorer has no armour; the same shot did 13 to the
Pacifist). Wave 20 clears by killing both bosses at 64-73 s. But income:
kills near-human from w6, materials ~30% of the human's on w1-5 and ~45%
after; the human fells 5-30 trees a wave.

Row built, each key measured (arms n=3 income / n=6 survival):

| key | evidence |
|---|---|
| `gold: 2.0, tree_value: 6.0` | w2-5 materials +~15%; `trees=` (new RESULT field) shows the tree lap was already at parity (w2 10/10, w4 15-16/15, w9 25-27/25) |
| `anchor: center 700` | w9 5/6 on, 5/6 off, but avg damage 34 vs 52; w4 income neutral |
| `engage: 6, engage_hp: 0.5` | w9 6/6 on vs 5/6 off; w4 kills +8%; w2 kills flat at 11-13 |
| `caution_phases [[8,1.3],[99,0.8]]` | at 11-15 HP caution x0.6 / engage x2 only added damage (w2 "both" died at 11 s, kills 8-13); at 33 HP caution x0.6 6/6, kills 433-483 vs 419-447, materials 216-255 vs 200-223 |
| rejected | pin-dwell 60 (w9 2/6), wall x2 (4/6), engage x2 (w9 4/6, w2 kills 8-12 + damage) |

Pooled w9: 14/30 (47%) before the row -> 24/27 (89%) with it.

**Final sweep (finished row): 59/60** — w9 2/3, everything else 3/3, bosses
down at 47-59 s. Income vs the human over 20 waves: kills 6,398 vs 7,002
(91%), trees at parity, in-wave materials 3,586 vs 7,304 (49%). Leftover
materials become bonus gold at wave end (`main.clean_up_room`, sampled after
the RESULT line), and the human's bonus gold is only 2-34 a wave, so the
human is collecting in-wave what the bot leaves for the bag. Open: in-wave
pickup with a 200 px kit — the bot kills but does not walk the drops.
`--arb-caution=<mult>` added (multiplier on the resolved row caution).

## Drop collection (2026-08-26)

Built three pieces: drops priced to the ATTRACT RIM (`profile.pickup_radius`,
150 x (1 + pickup_range/100), Explorer 225 px) instead of contact; a
`PICKUP_TAKEN` bonus (`--arb-taken`) for a move that ends inside the rim of a
drop it started outside; a row key `sweep` (`--arb-sweep`) multiplying drop
value while no enemy is inside `sweep_radius` (420). Explorer w4/w5/w9 arms
(n=4): full / no-taken / no-sweep / neither = 51/45/51/50, 51/48/53/44,
243/207/232/236 materials — noise. Fisherman w2 (12 HP, pickup-heavy) A/B
n=10: taken 9/10, no-taken 9/10. Kept as modelling (rim + taken); `sweep`
left off every row. The premise was wrong: per kill the bot already collects
what the human does (w1-5: 0.69/0.82/0.68/0.60/0.67 vs 0.76/0.94/0.69/0.59/
0.67 materials per kill); the late-game "49%" compared the tracker's gold
VALUE with the watcher's material COUNT. Income tracks kill rate, full stop.

## Tracker reproduction: Masochist, run #29392 (2026-08-26)

Six Lutes, 20 HP / 8 armour / 20 regen at w1 -> 113 HP, 21 armour, 39 regen,
80 dodge, 35 lifesteal at w20; bullet hell 2/3/6/8/11/16/19, elites 12/17,
horde 14, fog 7/13/15. Existing row `{caution 0.6, engage 12, engage_hp 0.66,
anchor center 520}` untouched. **Sweep 59/60**: w9 (39 HP) 2/3, the death an
edge hit chain after a correct below-band disengage; bosses down at 51-66 s.
Versus the human: kills 5,447 vs 5,946 (92%), early pickups at parity, and
the bot takes LESS damage per wave than the human on most waves (30->182 vs
14->264) — the HP-band row already plays the character; the guide's
hits-taken gating would be an optimisation, not a fix. w9 arms queued and
not run (band 0.5/0.8, pin-dwell) — superseded by the Jack work.

## Jack w11 croc bed (2026-08-26) — open, with two model fixes

`20260826-w11-jack-d6-hp31-croc.json`: the user's Steam run, Jack at wave 11
(first elite wave, croc), Danger 6, 31 HP, five laser guns + blunderbuss.
"The bot walks into the croc's encircling attack after the elite mutates."
0/5 baseline, **0/35 across every arm** (AoE x2.5, clock off, horizon 1.2,
dash x2, hop on/off, dash-fix on/off). Everything two-shots 31 HP: pillar 18,
pursuer 25, croc slash 26, croc contact 23.

The attack (croc.tscn): after the state change, `ChargingShootProjectiles-
Behavior2` drops 10 pillars ON the player's position, `projectile_spawn_
spread 500` on borders = a ring of radius **250** (spread / 2), 157 px apart,
every 45 frames while move-locked; pillar_projectile arms at 0.54 s, disarms
at 0.68 s (animation method track), footprint ~50 px.

Evidence (new telemetry: `PHIT` carries the pillar's animation clock and
distance; `PCHOICE` the last decision's six cheapest candidates; `PHIST` the
previous 40 decisions): every pillar hit lands at anim 0.57-0.63 with the bot
5-43 px from the pillar. The history before a hit: ring appears (`a10`) with
the bot at its centre; standing still already costs 950-1,100 (boosted
pursuers on 31 HP); every heading 60-90; the scorer picks a bearing 11 deg off
a pillar — a FULL pillar hit in its own pricing — because the gap centre and
every other bearing carry more pursuer/croc cost, then drifts 4 deg toward
the pillar over the next re-decisions. The ring is modelled correctly; the
bot buys the pillar as the cheapest exit. What it lacks is a two-step plan
(stay inside the ring 0.68 s, circling off the pursuers, then leave) or a
commit to the gap centre against myopic drift.

Fixed on the way (kept):
- **Dash model** (`--arb-dashfix=0` reverts): the game applies charge_speed
  AS bonus_speed, so adding it again in flight priced a croc dash at 1,550
  px/s instead of 950; and the lane never ended (INF) while the charge stops
  at charge_duration (~520 px). loud-w11 A/B n=10: fix 7/10 vs 6/10.
- **Hop candidates** (`--arb-hop=0` disables): 8 half-speed headings, offered
  only with a telegraph or dash inside 420 px, executed as the tap duty
  cycle (2 on / 2 off) for every row. Never the winner on the croc bed
  (pursuer pressure), longest time-to-death with it (mean ~30 s vs 17 s).

## Tracker reproduction: Streamer, run #22113 (2026-08-26) — standing income

Nightmare Abyss win, six slingshots, armour to 61, **12-75 steps a wave**, 630-1,130
gold a wave from the standing tick. Game rule (player.gd): `NotMovingTimer`, 1 s,
repeating, starts when movement is zero; each timeout pays `min(25, max(1, 3% x
held gold))`; ANY moving frame stops it and the next stand starts from zero.

Built `stand_income` (row key; `--arb-stand=<mult>`): the tick in the pickup unit
(`per_sec x gold_value`) is paid to the standing candidate over the horizon, and a
move pays back the progress of the current second; `--arb-standcommit` adds a whole
tick to the price of BREAKING a stand (the one-frame flickers that reset the timer
were priced at a fraction of a tick and never stopped). Telemetry: `stand=` (points/s),
`ticks=` (full seconds stood per sample), `breaks=`; the watcher now prints `gain=`
(gold at wave end minus wave start) because `mats=` counts pickups only and never
saw the tick — the first reading of these arms on `mats=` was wrong.

**Sweep (stand_income on): 60/60**, bosses at 20-22 s. Income per wave, gold gained
(n=4 per arm; human = gold collected that wave):

| wave | stand off | x1 | x3 | x1 + commit | human |
|---|---|---|---|---|---|
| 8 (315 held) | 127-225 | 216-300 | 301-658, **2/4 died** | 291-439 | 632 |
| 10 (363 held) | 261-360 | 434-559 | 453-539 | 438-525 | 848 |
| 13 (268 held) | 161-223 | 304-433 | 500-595 | | 865 |

Row: `stand_income: true` (x1) + commit 1.0. x3 is the human's income on the safe
waves and lethal on the 33-HP one; a `stand_w` per-wave phase is the obvious next
step. `ticks=` shows a full second completes in ~60% of samples with the commit rule.

## Scapegoat revive (2026-08-26)

item_scapegoat (entities/units/pet/scapegoat): a pet that enemies target
instead of the player; when it dies, a player inside its 100 px
HealingTriggeringZone (20 px above the body) refills it over 3 s and it
rises. Built as a HELD reward: a dead goat's zone is `[pos, REVIVE_VALUE 30,
attracted=false, rim=100]`; the arbiter pays the value to every move that
ENDS inside the rim (so standing there keeps earning and leaving costs the
same), the approach is priced like any pickup. Row-independent; `--arb-revive`
sweeps it (0 = off). Telemetry `BOTLOG GOAT died/revived after=Ns`.

Bed: tracker run #33670 (Loud, six daggers, 133 HP) has the goat from wave
18; snapshots `20260826-w18..20-loud-d6-hp*-tracker33670.json`. Revives
observed: died 27 s -> revived 33 s (5.9 s dead), died 16 s -> 30 s. n=3:

| wave | revive on: dmg | revive off: dmg | gain on / off |
|---|---|---|---|
| 18 | 15 / 86 / 22 (41) | 78 / 102 / 71 (84) | 1050 / 1032 |
| 19 | 146 / 76 / 108 (110) | 129 / 171 / 123 (141) | 1858 / 1832 |
| 20 | 38 / 38 / 0 | 0 / 38 / 38 | bosses dead at 21-29 s |

9/9 either way; damage taken roughly halves on the elite wave and drops a
quarter on wave 19, income unchanged. Kept.

## ARBITER bed 2026-08-26 late (hop + dash fix + drop pricing + Streamer stand + scapegoat)

loud-w11 3, gangster 10, w5-loud 10, w4-loud 10, sailor 10, renegade 10, fisherman 9,
wildling 9, king 10, lucky 10 = **91/100** (previous full beds: 93 at b56c850, 89 with the
adaptive interval on). loud-w11 sits at 3-7 across every bed this month; the two cancelled
partial beds today had it at 6 and 6 on this same code.

## Crowd runway (2026-08-27) — Pacifist w9 herding

The w9 death mode (holds the annulus ~20 s, then 100 chasers walk it to the
wall over a few seconds; every 0.8 s step locally right, the sum a corner)
is a horizon problem: the wall runway prices the wall 2.4 s out, nothing
priced the CROWD that far. Added W_ROOM_FAR: the same crowding measure taken
at FAR_T (2 s) along the bearing, threats extrapolated the same way, moving
candidates only (`--arb-roomfar`, `_p_far`). Pacifist w8+w9, n=6:

| arm | w9 | w8 |
|---|---|---|
| off (--arb-roomfar=0) | 2/6 | 3/6 |
| x1 (W_ROOM_FAR 3) | **4/6** | **5/6** |
| x2 | 3/6 | 4/6 |

9/12 at x1 vs 5/12 off. Kept at x1, GLOBAL (every row, like the wall
runway). Income unchanged: the Pacifist's materials are `pacifist`
living-enemy harvesting (gain= ~410 every arm), not pickups; its w9 pickup
count was 9-16 before any of these changes too -- the "220 materials" I
chased was the Explorer bed, not this one. No regression.

### Streamer stand phase (2026-08-27)

Row `stand_phases [[10,1.0],[99,3.0]], stand_below [0.5,1.0]` (x1 through w10,
x3 from w11, x1 below half HP). Phased sweep 60/60, ends full HP from w11 on;
gold gained per wave vs the original x1 sweep: w12 764-816 (was ~270), w13
554-772, w14 823-926, w16 925-978, w17 728-863, w19 922-1058. x3 held survival
at 36+ HP everywhere; w8/w10 stay x1 (x3 was 2/4 there). Human's per-wave gold
was 615/739/559/939/828/952 on those waves -- now within reach.

## ARBITER bed 2026-08-27 (+ crowd runway + Streamer stand phases)

loud-w11 4, gangster 9, w5-loud 10, w4-loud 10, sailor 10, renegade 10,
fisherman 10, wildling 8, king 10, lucky 9 = **90/100** (prev 91). The -1 is
noise on the fragile members (gangster/lucky -1 each, both usually 10;
loud-w11 +1); the crowd runway is neutral on the bed and 9/12 vs 5/12 on the
Pacifist w8/w9 waves it targets. Kept global at W_ROOM_FAR 3.

## Pacifist caution phase (2026-08-27) — wave-9 herding

The w9 death is the weaponless kit fleeing: it flees the nearest threats, and
once density peaks (~w9: 100+ threats, 46-114 live projectiles) fleeing
EVERYTHING is a walk to the wall. The human took 54 damage all wave (mostly one
narwhal) and won; the bot takes 67-97 and died ~half -- a steering gap, not a
build ceiling. Lower caution = flee less = stay off the wall.

w9 arms (n=8): caution 1.2 (baseline) 4/8, 1.0 6/8, 0.9 4/8; anchor x2 5/8,
roomfar x2 5/8, both 5/8 -- caution 1.0 is the only real lever, ~1.0 the sweet
spot (0.9 over-commits). But w8 (40 HP) WANTS the 1.2 (1.0 -> 3/8), and w6 is
8/8 at any caution, so it phases: `caution_phases [[8, 1.2], [99, 1.0]]`.

Verification at the row default, n=12: w9 **8/12** (was 4/8), w8 4/12
(unchanged -- the phase keeps 1.2 there; w8 is a genuinely weak wave, not a
regression), w6 8/8. Kept.

## Pacifist wave-8 lethality (2026-08-27)

w8 is bullet_hell (human took 54 dmg, won; bot 67-97, died ~half). Not the w9
herding -- 78% of deaths ARE at the wall, but the leaky-dwell corner escape was
a measured WASH (A/B both 6/10; kept only as --arb-pinleak knob). The lever is
LETHALITY: the default 4 makes a low-HP weaponless kit read every hit as
certain death and spiral into flight; lowering it keeps methodical dodging.
Unlike caution (uniform threat cut, hurt w8), lethality targets only the
HP-proportional panic. Added a `lethality` row key (default const 4;
--arb-lethality still wins for sweeps).

w8 lethality n=20: default(4) 9/20, 3 -> 13/20, 2 -> 10/20. Row set to
lethality 3.0. Verify at the row default (caution phase + lethality 3), n=12:
w6 10/12, w7 9/12, w8 7/12 (was ~45%), w9 8/12 (holds), w10 12/12. Kept.

## Tracker reproduction: Lich, run #30861 (2026-08-28)

Nightmare Abyss win, six spiky shields (contact weapon, damages on touch),
lifesteal 10-23, regen 10-34, armour to 32 -- a heal-by-contact facetank.
Schedule is bullet-hell heavy (w1/3/6/8/11/13/14), horde 12/15, elites 18.

**Baseline sweep (row `{gold 2.0, caution 0.6, engage 12, engage_hp 0.66}`):
59/60** -- only the w20 double-boss dropped one (2/3). Survival is basically
solved; the Lich facetanks everything. The one weakness: `eng=0` at low HP on
the boss (engage disarms below 66%), so the heal-by-contact kit STOPS fighting
exactly when it needs the lifesteal, and bleeds against bosses that give no
trash to walk into.

Fix: **engage_hp 0.4** (was 0.66) -- the bot heals by contact, so it should
fight deeper than the human's manual "hold 50-66%". w15 horde + w20 boss, n=6:
engage_hp 0.66 6/12, 0.4 8/12 (w15 3->5/6, w20 3/6 neutral), 0.25 8/12; 0.4
kept (safer). Re-sweep at 0.4: bullet-hell waves all 3/3 (no over-commit),
survivors end much healthier everywhere (w16 100/99, w18 117-146 HP). The w20
double-boss stays ~50% -- a projectile-dodging ceiling (death = orbiter +
scaled_stargazer, same family as the Jack croc bed), not an engage problem.

## Lich boss ceiling was a bug (2026-08-28)

The w20 ~50% "projectile-dodging ceiling" was not a ceiling. Capture showed
`eng=0` for the WHOLE wave at full HP -- engage disarms on any boss/elite wave
by the default rule (`engage_boss` false), so the heal-by-contact Lich never
ran its spiky-shield/lifesteal loop and died to attrition at 636 dmg though the
human tanked 1003 and lived. Data: human w20 dmgTaken 1003 (eel 287, dead_whale
188, mad_dragonfish 174 -- "orbiter" = eel_pivots). Fix: `engage_boss: "trash"`
(keep farming boss-wave trash, like the Bull). n=10: w20 **9/10** (was ~50%,
survivors 86-180 HP), w18 elite **10/10**. Lesson: check eblk=/eng= before
calling a boss wave a dodging problem -- engage_boss defaults OFF.

## Jack croc bed + AoE footprint (2026-08-28)

The 0/35 croc bed was PARTLY a modeling bug. A circular telegraph's modeled
radius was `(_projectile_radius + base.length()) * 2.2`: base.length() (the
hitbox offset, ~20) double-counts (it already shifts the centre), and 2.2 was
tuned for a wider-than-collision telegraph. For a croc ring pillar (23 px hit
collision, offset 20) that gave ~110 px -- and with pillars 157 px apart on the
ring, two adjacent modeled discs fully overlap: the model showed a SOLID WALL,
no threadable gap, so every heading through the ring scored as a full pillar
hit (PCHOICE: bearing 11 deg off a pillar was the cheapest exit).

Fix: drop base.length() from the radius, default mult 2.2 -> 1.5 (--arb-aoemult).
Croc aoemult sweep n=8: 2.2(fixed) 0/8, 1.5 1/8, 1.0 2/8. Regression n=8:
butcher 8/8 both (blade uses the RectangleShape2D path, untouched), colossus
6/8 -> 7/8 at 1.0. So opening the ring is safe on the pillar beds.

Croc still ~25% though: the ring was one of three simultaneous threats
(boosting pursuers 25 dmg, chain dashes, 700 px/s slashes) on a 31 HP kiter --
a near build ceiling even with correct modeling. Unlike the Lich boss (an
engage-disarm bug, fully fixed), the croc bed is a real fragility ceiling; the
modeling fix is a genuine correctness win that helps every pillar/ring wave.
