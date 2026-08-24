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

