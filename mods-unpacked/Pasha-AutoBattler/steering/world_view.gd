extends Reference

# Turns live game state into the plain arrays the arbiter scores.
#
# The split is deliberate: everything that knows about Brotato's node layout
# lives here, and the scorer knows only geometry. That keeps the scorer
# replayable offline against recorded states, which is what weight tuning and
# any later learned scorer both need.

const BODY_RADIUS_FALLBACK = 20.0
const THREAT_RANGE = 620.0       # threats past this cannot reach us inside the horizon
const PICKUP_RANGE = 900.0
const STATIONARY_SPEED_SQ = 100.0

# -- Pillar lifecycle --
#
# From pillar_projectile.tscn's "shoot" animation (length 1.05 s). Its method
# track fires disable_hitbox at 0, enable_hitbox at 0.54, disable_hitbox again
# at 0.68, stop at 1.04. So a pillar is LETHAL FOR 0.14 s out of 1.05 -- 13% of
# its life -- and is a completely harmless telegraph for the 0.54 s before that.
#
# A pillar is a CLOCK, not a wall, and that distinction is the whole gargoyle
# problem. Its State1 attack lays down 25 stationary pillars over a 700 px
# spread; pricing each as live from the instant it appears makes that field read
# as solid, when in fact most of it is passable at any given moment and there is
# a timed corridor straight through. The old model could not see time, so it
# could not see the corridor.
# These are the PILLAR's numbers and they are only a fallback. Stationary
# attacks do not share a clock: a gargoyle pillar is armed 0.54-0.68 of a 1.05 s
# animation, a butcher slash 0.48-0.60 of a 0.70 s one. Hardcoding one type's
# timings mistimes every other -- and it mistimes them in the DANGEROUS
# direction, telling the bot a blade arms later than it does. So the window is
# read off each projectile's own animation and these only apply when that fails.
const AOE_ARM_FALLBACK = 0.54
const AOE_DISARM_FALLBACK = 0.68
const INF_TIME = 1e9             # "does not stop being a threat inside any horizon"
const AOE_RADIUS_MULT = 2.2      # telegraph footprint is wider than the rest-pose collision
const AOE_RADIUS_MAX = 320.0

# -- Blade decomposition --
#
# A gargoyle pillar is a blob; a butcher's slash is a 273 x 28 px blade that
# sweeps 265 px in the 0.12 s it is armed. Collapsing both into one circle is
# what makes the slash undodgeable: reach = 136.5 + 19 = 155, times
# AOE_RADIUS_MULT, caps at a 320 px disc -- against a hitbox that is 14 px thin
# in the direction the dodge actually happens. Roughly 23x too wide.
#
# Two failures follow, and they compound. The dodge that works (a ~40 px step
# perpendicular to the blade) is not representable at all. And since slashes
# spawn ON the player and arm in 0.48 s, escaping a 320 px disc is impossible at
# ~300 px/s net -- so every candidate direction scores badly, the term goes flat
# across the compass, and it stops discriminating. That is the same saturation
# that made room18 score 0/10.
#
# So an elongated hitbox becomes a LINE of small circles along its long axis.
# The threat model stays circles-only -- the scorer is untouched -- but the thin
# perpendicular gap becomes expressible.
const BLADE_SEGMENTS_MAX = 6     # cap: a 10:1 blade would otherwise cost 10 threats
const BLADE_MARGIN = 1.25        # the blade sweeps ~37 px between physics frames,
                                 # and we only sample it once, so pad a little
const DEFAULT_PROJ_DAMAGE = 6.0
const DEFAULT_CONTACT_DAMAGE = 5.0
const AOE_DAMAGE = 10.0

# Reuse the arbiter's tuple layout.
const KIND_PROJ = 0
const KIND_CONTACT = 1
const KIND_DASH = 2
const KIND_AOE = 3

const TARGET_EXTRA = 220.0       # targets are collected this far past weapon range,
                                 # matching the arbiter's acquisition band
const KILL_HP_REF = 20.0         # killability falloff floor; see _refresh_kill_ref --
                                 # the live reference is the player's own measured
                                 # DPS, so "killable" means killable BY THIS BUILD
const KILL_TIME = 1.0            # seconds of sustained fire that define "killable":
                                 # a body that dies inside one second of shooting is
                                 # halfway killable at exactly ref = its HP
const KILL_REF_MAX = 600.0       # sanity cap; past this everything reads killable
                                 # anyway and a bad stats read cannot go to infinity
const EXPECTED_EXCHANGES = 2.0   # contacts an unkilled enemy gets before it dies anyway
const EGG_VALUE = 60.0           # a spawner is worth far more dead than its own damage
                                 # suggests: everything it hatches is future damage too

# -- Character profiles --
#
# Generic steering prices every pickup and every position the same way for
# every character; some characters break those assumptions by design and the
# fix belongs HERE, in the layer that knows what a character IS, not in the
# scorer. The scorer stays pure geometry: it is handed a profile dictionary
# of already-resolved numbers and never learns a character's name.
#
# Research behind the table lives in CHARACTER-PROFILES.md next to this file
# (decompiled effect data + wiki + per-character Danger 5 guides). The design
# rule from that research: 63 characters do NOT need 63 behaviours. They need
# six reusable mechanisms, and a character is a row of numbers selecting them.
#
#   gold / gold_phases / gold_mode   what a material on the floor is worth
#   food                             what a consumable on the floor is worth
#   caution / caution_phases         multiplier on every threat weight
#   engage (+engage_hp/engage_pack)  contact seeking; the inverse of kiting
#   anchor (+radius/inner/wave)      a place worth fighting near, or away from
#   still                            "prefer" standing, or "never" stand
#
# Absent character or absent key = baseline, so the table only records real
# deviations and an unlisted character behaves exactly as before. The whole
# layer is ablatable with --arb-charprofile=0, which is the honest control arm
# for every claim any of these rows makes.
#
# First profile, and the worked example for the rest: the Builder.
#
# The Builder converts materials left uncollected at wave end into turret
# stats (RunData.add_bonus_gold -> convert_bonus_gold -> structure_range,
# which is the turret's level/size XP: +1% attack speed and +1 range per 5
# materials, +1 projectile at 30/150/300), takes -75% stat gains from
# normal pickup and -30 pickup range. Gold on the ground is therefore worth
# MORE than gold in the bag -- but not always, and not equally.
#
# The material policy is PHASED, following Cephalopocalypse's Danger 5
# guide ("The GIGATURRET"): waves 1-4 collect EVERYTHING, because economy
# and defensive stats have to come online before the turret matters and a
# starved shop loses the run before the turret can win it; from wave 5
# feed the turret -- leave materials down until it hits its final tier at
# 300 structure_range ("power up the turret by wave 12 so it can kill the
# elite"); once maxed, materials only buy attack speed/range at steep
# diminishing returns, so go back to taking SOME ("not all of them") for
# levels and defense -- priced mildly positive so the bot picks up what it
# passes but never detours hard.
#
# The turret itself only shoots what comes within ITS range, and the only
# thing that reliably drags enemies through that circle is the player
# standing in it ("let the elite explode on our turret", "stay near our
# turret so the bosses die to it"). The anchor hands the arbiter the
# turret's position and range so staying near it is a scored preference,
# not an override. It engages with the feed phase, not before: phase 1 is
# a roaming-collection phase, and a leash would cost every material lying
# outside it.
const GOLD_VALUE = 0.8
const BUILDER_ECON_WAVES = 4     # last wave of collect-everything (guide: "wave four or five")
const BUILDER_GOLD_VALUE = -2.0  # feed phase: mild -- shapes paths between equals,
                                 # never outbids a dodge
const BUILDER_GOLD_LATE = 0.4    # maxed turret: take what we pass, skip detours
const BUILDER_TURRET_MAX_LEVEL = 3
const BUILDER_ANCHOR_MIN = 220.0 # leash radius bounds around the turret's own range:
const BUILDER_ANCHOR_MAX = 420.0 # roomy enough to kite inside, tight enough to matter

# -- Mechanism constants --
#
# Scale note, because it decides whether any of this is safe: the arbiter
# prices a threat at 15-65 after lethality scaling, and the pickup term is
# w_pickup(1.0) * value * closed. So every gold number below is a TIE-BREAKER
# between otherwise-similar candidates and none of them can outbid a dodge.
# Food and engage sit an order higher (up to ~12), matching w_dps at 14 --
# they are allowed to shape a fight, never to walk into a corridor.
const ENGAGE_PACK_RADIUS = 320.0 # "is a pack forming" test for the herders
const FOOD_MAX = 12.0            # cap on the healing one fruit is priced at
const FOOD_BANK_FULL = -0.8      # hoarders price stepping on fruit at full HP as a
                                 # mild COST: the ground is the safest inventory
const FOOD_FULL_SEEK = 6.0       # characters PAID for eating at full HP
const FOOD_BOMB_RADIUS = 220.0   # chef/glutton: a fruit is a grenade, and its value
const FOOD_BOMB_PER = 3.0        # is the enemies standing in its blast, not its heal
const FOOD_BOMB_MAX = 9.0
const FOOD_BOMB_ALONE = -1.5     # detonating on an empty floor wastes the whole pickup
const METER_COOLDOWN_MIN = 12.0  # buccaneer: frames of cooldown that make a weapon
                                 # worth spending a pickup to reset

# -- The table --
#
# Keys, all optional:
#   gold          float   flat material value (baseline GOLD_VALUE)
#   gold_phases   Array   [[max_wave, value], ...]; first match wins
#   gold_mode     String  "builder" | "enemy_gated" | "metered"
#   food          String  "bank" | "full_hp" | "bomb" | "none"
#   caution       float   multiplier on threat weights (>1 keeps more distance)
#   caution_phases Array  [[max_wave, value], ...]
#   caution_per_wave float added per wave elapsed (compounding-danger characters)
#   engage        float   contact-seeking strength (inverse kiting)
#   engage_hp     float   seek contact only while hp_ratio is ABOVE this
#   engage_pack   int     seek contact only once this many enemies are close
#   anchor        String  "builder" | "structures" | "center" | "perimeter"
#                         | "away_structures"
#   anchor_radius float   outer leash: cost for straying past it
#   anchor_inner  float   inner keep-out: cost for being closer than it
#   anchor_wave   int     anchor only engages from this wave on
#   still         String  "prefer" | "never"
const CHARACTER_PROFILES = {
	# --- Economy: materials are the win condition ---
	"character_saver": {"gold": 2.5, "anchor": "perimeter", "anchor_inner": 460.0,
			"caution_phases": [[6, 1.25], [99, 0.9]]},
	"character_mutant": {"gold": 2.0, "caution": 1.2, "still": "never"},
	"character_demon": {"gold": 2.0, "caution": 1.4, "anchor": "center",
			"anchor_radius": 520.0},
	"character_loud": {"gold": 2.0, "caution": 1.15, "still": "never"},
	"character_baby": {"gold": 2.0, "caution_phases": [[10, 1.5], [99, 0.65]]},
	"character_jack": {"gold": 1.8, "caution": 1.1},
	"character_old": {"gold": 1.8, "caution": 0.7, "anchor": "center",
			"anchor_radius": 420.0},
	"character_fisherman": {"gold": 1.8, "anchor": "perimeter",
			"anchor_inner": 440.0, "anchor_wave": 10},
	"character_apprentice": {"gold": 1.6, "caution": 1.25},
	"character_arms_dealer": {"gold": 1.6, "caution": 0.95},
	"character_hunter": {"gold": 1.5, "caution": 1.5},
	"character_technomage": {"gold": 1.5, "caution": 1.5, "anchor": "structures",
			"anchor_radius": 420.0},
	"character_curious": {"gold": 1.5, "caution": 0.9},
	"character_crazy": {"gold": 1.4, "caution": 0.7, "engage": 6.0, "engage_hp": 0.5},
	"character_entrepreneur": {"gold": 1.2, "anchor": "structures",
			"anchor_radius": 380.0},
	"character_knight": {"gold": 1.2, "caution": 0.5, "engage": 6.0,
			"engage_boss": true},    # the one kit told to stand ON the elite

	# --- Economy inverted: the floor is the better wallet ---
	"character_builder": {"gold_mode": "builder", "anchor": "builder"},
	"character_beast_master": {"gold_phases": [[3, -0.6], [99, 0.9]], "caution": 1.2},
	"character_hiker": {"gold": 0.3, "caution": 1.3, "anchor": "perimeter",
			"anchor_inner": 480.0, "still": "never"},
	"character_ranger": {"gold": 0.3, "caution": 1.6},
	"character_wounded": {"gold": 0.4, "caution": 2.0},

	# --- Pickups as a weapon: WHEN you step on it is the whole skill ---
	"character_lucky": {"gold_mode": "enemy_gated", "gold": 1.6, "food": "bank",
			"still": "never"},
	"character_buccaneer": {"gold_mode": "metered", "gold": 2.0, "still": "never"},
	"character_sailor": {"gold": 1.8, "caution": 1.05},
	"character_lich": {"gold": 2.0, "caution": 0.6, "engage": 12.0, "engage_hp": 0.66},
	"character_chef": {"food": "bomb"},
	"character_glutton": {"food": "bomb", "anchor": "center", "anchor_radius": 560.0,
			"caution_phases": [[5, 1.4], [99, 1.0]]},
	"character_farmer": {"food": "full_hp", "caution": 1.4},
	"character_druid": {"food": "full_hp"},
	"character_golem": {"food": "none", "caution": 1.5},
	"character_vampire": {"food": "none", "caution": 0.6, "engage": 12.0,
			"engage_hp": 0.6},
	"character_ghost": {"food": "bank", "caution": 0.9},
	"character_chunky": {"food": "bank", "caution": 0.75, "still": "never"},
	"character_ogre": {"food": "bank", "caution_phases": [[8, 1.1], [99, 0.6]],
			"engage": 10.0, "engage_pack": 6},
	"character_vagabond": {"food": "bank", "caution": 0.8, "anchor": "center",
			"anchor_radius": 460.0},

	# --- Contact seekers: damage taken is the resource ---
	"character_bull": {"caution": 0.5, "engage": 14.0, "engage_hp": 0.6},
	"character_masochist": {"caution": 0.6, "engage": 12.0, "engage_hp": 0.66,
			"anchor": "center", "anchor_radius": 520.0},
	"character_wildling": {"gold": 1.4, "caution": 0.55, "engage": 8.0,
			"engage_hp": 0.3},
	"character_brawler": {"caution": 0.5, "engage": 8.0, "engage_hp": 0.35},
	"character_dwarf": {"caution": 0.7, "engage": 10.0, "engage_pack": 6},
	"character_artificer": {"caution": 1.1, "engage": 5.0, "engage_pack": 4,
			"anchor": "center", "anchor_radius": 560.0},

	# --- Anchored: a place worth fighting near (or away from) ---
	"character_engineer": {"anchor": "structures", "anchor_radius": 260.0,
			"still": "prefer", "gold_end": 1.6, "end_secs": 6},
	"character_streamer": {"anchor": "structures", "anchor_radius": 240.0,
			"still": "prefer", "gold_end": 1.6, "end_secs": 6},
	"character_multitasker": {"anchor": "structures", "anchor_radius": 320.0,
			"caution": 0.75},
	"character_mage": {"anchor": "away_structures", "anchor_inner": 500.0,
			"caution": 1.2},
	"character_pacifist": {"food": "none", "anchor": "perimeter",
			"anchor_inner": 520.0, "still": "never", "caution": 1.2},
	"character_creature": {"gold_phases": [[8, 1.8], [99, 0.9]],
			"caution_phases": [[8, 1.2], [99, 0.8]], "anchor": "perimeter",
			"anchor_inner": 460.0, "anchor_wave": 10, "still": "never"},
	"character_one_arm": {"gold": 1.6, "caution_phases": [[5, 0.7], [9, 1.4], [99, 1.1]],
			"anchor": "center", "anchor_radius": 520.0, "anchor_wave": 5},
	"character_king": {"caution_phases": [[12, 1.4], [99, 0.8]]},

	# --- Still / never-still ---
	# Soldier is the tap-mover: +50% damage AND +50% attack speed while
	# stationary, fire resumes the instant it stops (no re-arm delay), and
	# +200% pickup range vacuums drops without walking to them. So: stand and
	# shoot (prefers_still doubles the DPS payout for the ZERO candidate, and
	# the stop-bonus in the arbiter's continuity term lets a dodge end the
	# moment the threat clears), never detour for gold mid-wave (0.3 -- the
	# pickup radius does the collecting), then sweep what the vacuum missed in
	# the final seconds when standing has nothing left to shoot at.
	# fire_still is the load-bearing key: weapons only fire while stationary, so
	# the arbiter's kill reward pays double when standing and near-nothing when
	# moving (see FIRE_STILL_* in the arbiter). Field report that forced it: the
	# bot kited constantly, never fired, and lost by attrition. caution below 1
	# leans the same way -- a potato that must stand to shoot has to accept more
	# incoming pressure than one that can retreat at no cost to its DPS.
	# gold 1.2 (was 0.3): the passive-vacuum theory underestimated how far away
	# a tap-moving Soldier kills things -- drops accumulate at weapon range and
	# the stand never walks there. Above-baseline value makes repositioning
	# paths route THROUGH drop fields; the stand-floor and trade budget still
	# outrank it wherever shooting matters, so it shapes the walk, not the fight.
	# pin: the stand-and-shoot behaviour is also how this kit gets CORNERED --
	# the stand holds while the crowd closes the exits (wave-12 field report).
	# Pin escape overrides every fire_still perk while it runs: no floor, no
	# kill-discount, no trade budget, no taps -- escape at the loss of firing.
	"character_soldier": {"still": "prefer", "fire_still": true, "pin": true,
			"caution": 0.7, "gold": 1.2, "gold_end": 2.0, "end_secs": 10},
	"character_speedy": {"still": "never", "caution": 1.15},

	# --- Caution-only rows ---
	"character_captain": {"caution_per_wave": 0.02},
	"character_romantic": {"caution_per_wave": 0.02},
	"character_gangster": {"caution": 1.4},
	"character_explorer": {"caution": 1.3},
	"character_diver": {"caution": 1.25},
	"character_generalist": {"caution": 0.8},
	"character_gladiator": {"caution": 0.8},
	"character_doctor": {"caution": 0.85},
	"character_sick": {"caution": 0.85},
	"character_renegade": {"caution": 0.75},
}

const WINDUP_ANIM_LENGTH = 0.4   # enemy_charge_prep_animation.tres: start_shoot at 0, shoot at 0.4
const SIN_DRIFT_HORIZON = 0.8    # must match Arbiter.HORIZON: how far a weaving bullet strays

# -- Weaving bullets --
#
# Projectile._physics_process moves a bullet by (velocity + sinusoidal_offset),
# where sinusoidal_offset = sin(sinusoidal_time) * sinusoidal_motion * 0.5. So
# the sine is a VELOCITY perturbation, and every input to it is readable: phase,
# amplitude and rate all live on the projectile.
#
# The old model ignored that and smeared the bullet instead, widening its radius
# by half-amplitude x horizon. That is a defensible bound for a gentle weave and
# catastrophic for a violent one. Bullet-hell variants differ 12x in amplitude:
#
#   BulletHell_*_3      50-75   ->  +20-30 px      (fine)
#   BulletHell_Top etc.   100   ->  +40 px         (fine)
#   BulletHell_0      250,250   ->  +141 px
#   BulletHell_2          400   ->  +160 px
#   BulletHell_*_2       +-600  ->  +240 px        (a 257 px BLOB per bullet)
#
# With 14-21 bullets up, the +-600 variants blanket the arena: every candidate
# direction sits inside something, the term goes flat across the compass and
# stops discriminating. That is the same saturation that made room18 score 0/10
# and made a butcher blade undodgeable as a 320 px disc -- and it matches the
# observed failure exactly, where the bot does NOT thrash but calmly walks into
# a wall while nothing is chasing it, because nothing pulls it anywhere better.
#
# So sample the sine instead of smearing it: integrate the bullet's real path
# over the scan window and emit a few small circles where it WILL be. Same
# threat model, same scorer, correct geometry.
# -- Orbiting projectiles --
#
# Some bosses carry their projectiles as their OWN children instead of handing
# them to the EnemyProjectiles container. The predator spins nine of them on a
# Pivot (corrupted_tree/pivot.gd) at radii 250-600, rotation_speed 1.2 rad/s,
# destroy_on_hit = false, damage scaling to ~23 by wave 20.
#
# gather() only scanned main's EnemyProjectiles children, so these never entered
# the threat list at all. Not mispriced -- ABSENT. No amount of scoring helps
# against a hazard that is not in the model, and this one is a permanent
# 420 px/s flail wrapped around a 15000 HP boss on the final wave.
#
# They are sampled along their ARC rather than given a straight-line velocity:
# at 1.2 rad/s the pivot turns 0.96 rad across one horizon, so a tangent would
# put a 350 px orbiter hundreds of px from where it really goes. Same treatment
# the weaving bullets get, and for the same reason.
const ORBIT_SAMPLES = 4
const ORBIT_SMEAR_MAX = 60.0     # px of residual widening per sample

const SIN_SAMPLES = 4            # circles per weaving bullet
const SIN_SMEAR_MAX = 60.0       # px of residual widening we still allow per sample,
                                 # covering the phase drift between samples
const SIN_SIGNIFICANT = 60.0     # amplitude below this, one straight-line threat with
                                 # the old cheap widening is already accurate enough

# -- Contact persistence --
#
# Every threat tuple carries the expected number of damage applications it
# lands over one horizon. For anything that fires once and is spent -- a
# bullet, a pillar, a completed dash -- that is 1. For a body it is not.
#
# Every enemy in the game shares attack_cd = 30 frames, so the hit RATE carries
# no information: a body you are touching lands HORIZON * 60 / 30 = 1.6 hits
# regardless of species. What differs enormously is how long it keeps touching
# you, and that is pure speed ratio. You shed a 150-speed pursuer almost at
# once; you do not shed a 350-speed lamprey at all while the potato moves ~470.
#
# The horizon truncation is what makes this matter. Pricing only 0.8 s is sound
# when the next decision can undo the exposure -- but against something you
# cannot outrun the next decision cannot, and every future horizon inherits the
# same contact. Each horizon separates you by (1 - ve/vp) of the closing gap,
# so the expected number of horizons spent attached is the geometric sum
# 1 / (1 - ve/vp): 1.0 for a stationary egg, ~1.5 for a pursuer, ~3.9 for a
# lamprey, and divergent as the enemy approaches your speed -- hence the cap.
#
# This replaces a flat CONTACT_TICKS = 1.6 that priced every body as a brush.
# The flat constant is why w2-fisherman needed --arb-contact=3 to survive
# (lampreys at 350 and chasers at 380) while the same override did nothing on
# w12-wildling and mildly hurt w4-loud: one number cannot be right for a body
# you cannot escape and a body you can walk away from.
const CONTACT_RATE = 1.6         # HORIZON * 60 / attack_cd; uniform across all enemies
const PERSIST_MAX = 4.0          # cap on horizons-attached, for ve >= vp
const TICKS_ONCE = 1.0           # bullets, pillars and dashes connect at most once

var threats = []
var rewards = []
var targets = []
var chargers = []                # idle chargers whose cooldown may expire soon
var mitigation = 1.0             # share of incoming damage that actually lands
var far_corner = Vector2.ZERO
var body_radius = BODY_RADIUS_FALLBACK
var weapon_range = 1000.0
var prefers_still = false
var current_hp = 1.0
var player_speed = 1.0           # sets how sticky every body is; a fast build
                                 # genuinely can afford to brush past things a
                                 # slow one must never touch
# Per-frame resolved profile handed to the arbiter: already-plain numbers, so
# the scorer never learns a character's name. Empty = pure baseline steering.
# Keys the arbiter reads: anchor, anchor_radius, anchor_inner, caution,
# engage, never_still.
var profile = {}
var wave_time_left = 1e9         # seconds until the wave ends; 1e9 when unreadable


# Sweepable via --arb-persist=<cap>, so this mechanism can be ablated like any
# weight. Note persist=1 reproduces the old flat CONTACT_TICKS = 1.6 exactly:
# the floor then clamps every separation to 1.0, so speed stops mattering. That
# makes it the honest control arm rather than an approximation of one.
var persist_max = PERSIST_MAX


# Arm/disarm window for a stationary attack, in animation-time, read off the
# animation's own method track: the key that calls enable_hitbox and the next
# one that calls disable_hitbox. Cached per Animation resource -- keying by name
# would collide, since a pillar and a slash both call theirs "shoot".
var _aoe_window_cache = {}

# Sweepable: --arb-aoeclock=0 reverts to "every un-spent telegraph is live right
# now", which is exactly how stationary attacks were priced before 2026-08-19.
# That makes the pre-fix behaviour an exact control arm rather than a guess at one.
var aoe_clock = 1.0

# Separate from aoe_clock on purpose: --arb-movingclock=0 reverts ONLY the
# in-flight telegraph timing, leaving the stationary pillar clock (committed and
# validated) in place. Without this, the control arm would revert two changes at
# once and could not attribute either.
var moving_clock = 1.0

# Sweepable: --arb-orbit=0 stops scanning boss subtrees for attached
# projectiles, restoring the previous behaviour where they were invisible.
var orbit_scan = 1.0

# Sweepable: --arb-mblade=0 puts flying blades back on the single fat circle,
# leaving the stationary decomposition untouched, so the control arm isolates
# exactly this change.
var moving_blade = 1.0

# Sweepable: --arb-bonusspeed=0 reverts enemy speed to bare current_stats,
# restoring the boost-blind threat model as an exact control arm.
var bonus_speed_scan = 1.0

# Sweepable: --arb-dpsref=0 pins the killability reference back to the static
# KILL_HP_REF, restoring build-blind kill values as an exact control arm.
var dps_ref_scan = 1.0
var _kill_ref = KILL_HP_REF      # refreshed per gather from live weapon stats
var _kill_ref_logged = -1e9      # last value announced on BOTLOG DPSREF

# Sweepable: --arb-charprofile=0 disables ALL character-specific logic at once,
# so "generic strategy on this character" stays an exact control arm.
# --arb-goldval overrides just the Builder's gold value (0 = ignore, positive
# = generic greed) to sweep the avoidance separately from the anchor.
var char_profile = 1.0
var gold_value_override = null

# Sweepable: --arb-blade=0 reverts to one inflated circle per stationary hitbox,
# which is exactly how blades were priced before, so the comparison is exact.
var blade_split = 1.0

# Sweepable: --arb-sweep=0 falls back to the blade's live pose instead of the
# union of everything it covers while armed, so the previous behaviour stays an
# exact control arm.
var sweep_union = 1.0

# Sweepable: --arb-sine=0 restores the single smeared circle, so the previous
# behaviour is an exact control arm.
var sine_sample = 1.0


# Value of a keyed track at or before `at`, held (not extrapolated) outside the
# key range -- which is how Godot itself samples a track before its first key.
func _held_value(keys: Array, at: float):
	if keys.empty():
		return null
	var out = keys[0][1]
	for k in keys:
		if k[0] <= at + 0.0001:
			out = k[1]
		else:
			break
	return out


func _aoe_profile(anim) -> Dictionary:
	var nm = anim.current_animation
	if nm == "" or not anim.has_animation(nm):
		return {"arm": AOE_ARM_FALLBACK, "disarm": AOE_DISARM_FALLBACK, "swept": false}
	var track = anim.get_animation(nm)
	var key = track.get_instance_id()
	if _aoe_window_cache.has(key):
		return _aoe_window_cache[key]

	var arm = -1.0
	var disarm = -1.0
	var pos_keys = []
	var ext_keys = []
	for ti in range(track.get_track_count()):
		var ttype = track.track_get_type(ti)
		if ttype == Animation.TYPE_METHOD:
			for ki in range(track.track_get_key_count(ti)):
				var when = track.track_get_key_time(ti, ki)
				var method = track.method_track_get_name(ti, ki)
				if method == "enable_hitbox":
					if arm < 0.0:
						arm = when
				elif method == "disable_hitbox" and arm >= 0.0 and disarm < 0.0:
					disarm = when
		elif ttype == Animation.TYPE_VALUE:
			var path = String(track.track_get_path(ti))
			if path.ends_with("Collision:position"):
				for ki in range(track.track_get_key_count(ti)):
					pos_keys.push_back([track.track_get_key_time(ti, ki), track.track_get_key_value(ti, ki)])
			elif path.ends_with("Collision:shape:extents"):
				for ki in range(track.track_get_key_count(ti)):
					ext_keys.push_back([track.track_get_key_time(ti, ki), track.track_get_key_value(ti, ki)])

	# `windowed` says a REAL enable_hitbox/disable_hitbox pair was found, as
	# opposed to the fallback guess. Only a real window may be applied to a
	# MOVING projectile: ordinary enemy bullets have no method track at all, and
	# applying the pillar's 0.54 s fallback to them would tell the bot a live
	# bullet is harmless for half a second.
	var profile = {"arm": AOE_ARM_FALLBACK, "disarm": AOE_DISARM_FALLBACK,
			"swept": false, "windowed": false}
	if arm >= 0.0:
		profile["arm"] = arm
		profile["disarm"] = disarm if disarm >= 0.0 else track.length
		profile["windowed"] = true

	# Union of every pose the collision box holds WHILE ARMED.
	#
	# This is the difference between planning against the blade and planning
	# against a stale stub. Both tracks' first key sits at the arm moment, so
	# during the whole 0.48 s wind-up -- the only time a dodge can actually be
	# planned -- sampling the live pose returns the blade's STARTING pose: a
	# 60x34 stub at x=-122, when the blade goes on to sweep a 306x34 region
	# centred at x=+1. The centre is 123 px wrong and the extent 5x too small,
	# so the bot sidesteps one end and the sweep takes it anyway. At ~1900 px/s
	# of sweep against a 470 px/s potato, reacting once it starts is hopeless.
	if not pos_keys.empty() and not ext_keys.empty():
		var lo = Vector2(1e9, 1e9)
		var hi = Vector2(-1e9, -1e9)
		var seen = 0
		for k in pos_keys:
			var when2 = k[0]
			if when2 < profile["arm"] - 0.0001 or when2 > profile["disarm"] + 0.0001:
				continue
			var c = k[1]
			var e = _held_value(ext_keys, when2)
			if e == null:
				continue
			lo.x = min(lo.x, c.x - e.x); hi.x = max(hi.x, c.x + e.x)
			lo.y = min(lo.y, c.y - e.y); hi.y = max(hi.y, c.y + e.y)
			seen += 1
		if seen > 0:
			profile["swept"] = true
			profile["centre"] = (lo + hi) * 0.5
			profile["half"] = (hi - lo) * 0.5
	_aoe_window_cache[key] = profile
	return profile


func apply_overrides(d: Dictionary) -> void:
	if d.has("persist"):
		persist_max = max(float(d["persist"]), 1.0)
		print("WORLDVIEW persist_max=%.2f" % persist_max)
	if d.has("aoeclock"):
		aoe_clock = float(d["aoeclock"])
		print("WORLDVIEW aoe_clock=%.0f" % aoe_clock)
	if d.has("blade"):
		blade_split = float(d["blade"])
		print("WORLDVIEW blade_split=%.0f" % blade_split)
	if d.has("sweep"):
		sweep_union = float(d["sweep"])
		print("WORLDVIEW sweep_union=%.0f" % sweep_union)
	if d.has("sine"):
		sine_sample = float(d["sine"])
		print("WORLDVIEW sine_sample=%.0f" % sine_sample)
	if d.has("movingclock"):
		moving_clock = float(d["movingclock"])
		print("WORLDVIEW moving_clock=%.0f" % moving_clock)
	if d.has("orbit"):
		orbit_scan = float(d["orbit"])
		print("WORLDVIEW orbit_scan=%.0f" % orbit_scan)
	if d.has("mblade"):
		moving_blade = float(d["mblade"])
		print("WORLDVIEW moving_blade=%.0f" % moving_blade)
	if d.has("bonusspeed"):
		bonus_speed_scan = float(d["bonusspeed"])
		print("WORLDVIEW bonus_speed_scan=%.0f" % bonus_speed_scan)
	if d.has("dpsref"):
		dps_ref_scan = float(d["dpsref"])
		print("WORLDVIEW dps_ref_scan=%.0f" % dps_ref_scan)
	if d.has("charprofile"):
		char_profile = float(d["charprofile"])
		print("WORLDVIEW char_profile=%.0f" % char_profile)
	if d.has("goldval"):
		gold_value_override = float(d["goldval"])
		print("WORLDVIEW gold_value_override=%.2f" % gold_value_override)


# Expected damage applications from a body over one horizon: how often it hits
# while attached, times how many horizons it stays attached. See the
# CONTACT_RATE block above for the derivation.
func _contact_ticks(enemy_speed: float) -> float:
	var separation = 1.0 - enemy_speed / player_speed
	return CONTACT_RATE / max(separation, 1.0 / persist_max)


func gather(main, player) -> void:
	threats = []
	rewards = []
	targets = []
	chargers = []
	far_corner = ZoneService.current_zone_max_position
	body_radius = _body_radius(player)
	mitigation = _mitigation(player)
	player_speed = max(float(player.get_move_speed()), 1.0)

	var pos = player.position
	var range_sq = THREAT_RANGE * THREAT_RANGE
	var pickup_sq = PICKUP_RANGE * PICKUP_RANGE
	var spawner = main._entity_spawner

	# The wave clock, for phase behaviours keyed to it (end-of-wave sweeps now;
	# cyborg's half-wave switch later). _wave_timer is Main's own Timer node --
	# time_left is 0 while it is stopped (between waves), which correctly reads
	# as "the wave is over, sweep" rather than as a huge remaining duration.
	wave_time_left = 1e9
	if "_wave_timer" in main and main._wave_timer:
		wave_time_left = float(main._wave_timer.time_left)

	weapon_range = _weapon_range(player)
	_refresh_kill_ref(player)
	var character_id = RunData.get_player_character(0).my_id
	# char_profile = 0 (--arb-charprofile=0) empties the row, which is what makes
	# "this character, generic steering" an exact control arm rather than an
	# approximation of one.
	var row = {}
	if char_profile != 0.0 and CHARACTER_PROFILES.has(character_id):
		row = CHARACTER_PROFILES[character_id]
	prefers_still = row.get("still", "") == "prefer"
	if character_id != _announced_char:
		_announced_char = character_id
		print("BOTLOG PROFILE char=%s %s" % [character_id,
				"baseline" if row.empty() else str(row)])

	var target_reach = max(THREAT_RANGE, weapon_range + TARGET_EXTRA)
	var target_range_sq = target_reach * target_reach

	for enemy in spawner.enemies:
		_add_unit(enemy, pos, range_sq, target_range_sq, pickup_sq)
	for boss in spawner.bosses:
		_add_unit(boss, pos, range_sq, target_range_sq, pickup_sq)

	var projectiles = main.get_node_or_null("EnemyProjectiles")
	if projectiles:
		for p in projectiles.get_children():
			if not (p is Projectile):
				continue    # BulletHell wave containers live here too
			if not p._hitbox or not p._hitbox.active:
				continue
			_add_projectile(p, pos, range_sq)

	# Projectiles a boss keeps as its own children never reach that container.
	# Bosses only: they are few, so walking their subtrees is cheap, and every
	# attached-projectile design in this game is a boss mechanic.
	if orbit_scan != 0.0:
		for boss in spawner.bosses:
			_add_attached(boss, pos, range_sq)

	current_hp = float(player.current_stats.health)
	var max_hp = max(float(player.max_stats.health), 1.0)
	var missing_hp = max_hp - current_hp
	var food_mode = row.get("food", "")
	for c in main._consumables:
		if c.position.distance_squared_to(pos) < pickup_sq:
			rewards.push_back([c.position,
					_food_value(food_mode, c.position, missing_hp, spawner)])
	var gold_value = _gold_value(row, player)
	for g in main._active_golds:
		if g.position.distance_squared_to(pos) < pickup_sq:
			rewards.push_back([g.position, gold_value])

	profile = {}
	if not row.empty():
		var caution = _caution(row)
		if caution != 1.0:
			profile["caution"] = caution
		if row.get("still", "") == "never":
			profile["never_still"] = true
		if row.get("fire_still", false):
			profile["fire_still"] = true
		if row.get("pin", false):
			profile["pin"] = true
		var engage = _engage(row, current_hp / max_hp, pos, spawner)
		if engage > 0.0:
			profile["engage"] = engage
		_resolve_anchor(row, spawner)


# "Killable" is relative to the guns doing the killing, and pinning it to a
# static 20 HP is why a maxed build still tiptoed around elites it could
# delete: killability read an 800 HP elite as 0.02 forever, so neither the
# kill reward nor the Soldier's standing discount ever learned the build had
# outgrown the number. The reference is now the damage the CURRENT loadout
# deals in KILL_TIME seconds of fire, measured from live weapon stats
# (weapon.stats is post-init, so attack-speed and damage purchases are already
# in the cooldown and damage fields; crits and conditional bonuses are not --
# the estimate runs conservative). Floored at the old constant so a naked
# early build behaves exactly as before, capped so a bad read cannot explode.
func _refresh_kill_ref(player) -> void:
	_kill_ref = KILL_HP_REF
	if dps_ref_scan == 0.0 or not ("current_weapons" in player):
		return
	var dps = 0.0
	for w in player.current_weapons:
		if not is_instance_valid(w) or not w.stats:
			continue
		var nproj = 1.0
		if "nb_projectiles" in w.stats:
			nproj = max(float(w.stats.nb_projectiles), 1.0)
		dps += float(w.stats.damage) * nproj * 60.0 / max(float(w.stats.cooldown), 1.0)
	_kill_ref = clamp(dps * KILL_TIME, KILL_HP_REF, KILL_REF_MAX)
	if abs(_kill_ref - _kill_ref_logged) > 25.0:
		_kill_ref_logged = _kill_ref
		print("BOTLOG DPSREF dps=%.0f kill_ref=%.0f" % [dps, _kill_ref])


# The Builder's phased material value -- see the character-profiles block.
# Phase state is read off the run, not tracked: the wave number and the
# turret's own XP stat (structure_range) fully determine the phase, so a
# mid-run save/load or a WaveLab snapshot injection lands in the right
# phase for free. --arb-goldval overrides ALL phases at once, so a sweep
# can still price gold flat.
var _builder_phase = -1          # last announced phase, for the BOTLOG line only
var _announced_char = ""         # ditto: which character's row we already logged


# Value of the first phase row whose wave ceiling has not been passed.
func _phase_value(phases: Array, fallback: float) -> float:
	for p in phases:
		if RunData.current_wave <= int(p[0]):
			return float(p[1])
	return fallback


func _gold_value(row: Dictionary, player) -> float:
	var mode = row.get("gold_mode", "")
	if mode == "builder":
		return _builder_gold_value()
	if gold_value_override != null:
		return gold_value_override
	# End-of-wave sweep: characters that spend the wave NOT collecting (Soldier
	# stands and lets its tripled pickup radius vacuum; Engineer holds its pod)
	# still want the leftovers, and the last seconds are when collecting them
	# costs the least -- the spawner has wound down and, per the Golem guide,
	# damage taken right before the horn is nearly free. Deliberately a no-op
	# for the Builder: its feed phase exists precisely to LEAVE the floor full.
	if row.has("gold_end") and wave_time_left <= float(row.get("end_secs", 8.0)):
		return float(row["gold_end"])
	var base = float(row.get("gold", GOLD_VALUE))
	if row.has("gold_phases"):
		base = _phase_value(row["gold_phases"], GOLD_VALUE)
	if mode == "enemy_gated":
		# Lucky's pickups DEAL DAMAGE (dmg_when_pickup_gold, 15% of Luck), so a
		# material collected on an empty floor is a wasted shot. Let it lie
		# until there is something for it to hit.
		return base if not targets.empty() else 0.0
	if mode == "metered":
		# Buccaneer: a pickup RESETS every weapon cooldown, and one pickup pays
		# the same whether one weapon was waiting or six. Vacuuming a pile
		# spends its resets on weapons that were ready anyway -- the value is
		# entirely in the spacing, so only reach for gold while something cools.
		return base if _weapon_cooling(player) else 0.0
	return base


# Is any weapon deep enough into cooldown that resetting it actually buys a shot?
func _weapon_cooling(player) -> bool:
	if not ("current_weapons" in player):
		return true    # unknown loadout shape: fall back to plain greed
	for w in player.current_weapons:
		if is_instance_valid(w) and w._current_cooldown >= METER_COOLDOWN_MIN:
			return true
	return false


func _food_value(mode: String, fpos: Vector2, missing_hp: float, spawner) -> float:
	if mode == "none":
		# Golem cannot heal at all mid-wave and Vampire's consumable_heal is
		# -100: fruit is scenery, and detouring for it is pure risk.
		return 0.0
	if mode == "full_hp" and missing_hp <= 0.0:
		# Farmer (+1 harvesting) and Druid (a luck roll) are PAID for eating at
		# full health, which inverts the usual save-it-until-hurt logic.
		return FOOD_FULL_SEEK
	if mode == "bomb":
		# Chef ignites on pickup, Glutton detonates for 500% melee. The fruit is
		# a grenade with a fixed blast, so its worth is who is standing in it --
		# and eating it alone throws the whole charge away.
		var near = 0
		var r_sq = FOOD_BOMB_RADIUS * FOOD_BOMB_RADIUS
		for e in spawner.enemies:
			if is_instance_valid(e) and not e.dead and not e.is_loot \
					and e.position.distance_squared_to(fpos) < r_sq:
				near += 1
		if near == 0:
			return FOOD_BOMB_ALONE
		return min(FOOD_BOMB_MAX, FOOD_BOMB_PER * near)
	if mode == "bank" and missing_hp <= 0.0:
		# The ground is the safest inventory: fruit not yet eaten is healing that
		# cannot be wasted. Step on it once the healing is real, not before.
		return FOOD_BANK_FULL
	return min(FOOD_MAX, missing_hp)


func _caution(row: Dictionary) -> float:
	var c = float(row.get("caution", 1.0))
	if row.has("caution_phases"):
		c = _phase_value(row["caution_phases"], 1.0)
	if row.has("caution_per_wave"):
		# Captain hands every enemy +2 HP and +2 damage per wave, Romantic sheds
		# armour to curse on the same clock: the danger compounds, so caution has
		# to climb with it instead of sitting at whatever suited wave 1.
		c += float(row["caution_per_wave"]) * max(RunData.current_wave - 1, 0)
	return max(c, 0.1)


# Contact seeking -- the inverse of kiting. For characters paid in hits TAKEN
# (bull explodes when hit; vampire/lich/masochist scale off missing HP) or in
# one swing landing across a crowd (dwarf, ogre, artificer). Both gates matter:
# they switch the behaviour off exactly where it would otherwise kill the run.
func _engage(row: Dictionary, hp_ratio: float, pos: Vector2, spawner) -> float:
	var e = float(row.get("engage", 0.0))
	if e <= 0.0:
		return 0.0
	if row.has("engage_hp") and hp_ratio <= float(row["engage_hp"]):
		return 0.0    # below the band: break off and let the kit refill
	if not row.get("engage_boss", false):
		# Every guide for these characters draws the same line: walk into TRASH,
		# never into the elite. The mechanics that pay for contact -- an explosion
		# per hit taken, lifesteal, a swing across six bodies -- all scale with
		# enemy COUNT, and an elite is one body that hits back far harder than the
		# trash the behaviour was designed around. Knight is the documented
		# exception and opts back in with engage_boss.
		for b in spawner.bosses:
			if is_instance_valid(b) and not b.dead:
				return 0.0
	if row.has("engage_pack"):
		# A herder must not charge the first enemy it sees: the payoff needs a
		# CLUMP (dwarf wants 6 kills in one hit), and engaging early is exactly
		# what stops one forming.
		var near = 0
		var r_sq = ENGAGE_PACK_RADIUS * ENGAGE_PACK_RADIUS
		for en in spawner.enemies:
			if is_instance_valid(en) and not en.dead and not en.is_loot \
					and en.position.distance_squared_to(pos) < r_sq:
				near += 1
		if near < int(row["engage_pack"]):
			return 0.0
	return e


# Writes the anchor keys into `profile`. The modes differ only in where the
# point comes from and whether the cost is for straying OUT (a leash) or for
# closing IN (a keep-out ring); the arbiter needs nothing but radius and inner.
func _resolve_anchor(row: Dictionary, spawner) -> void:
	var mode = row.get("anchor", "")
	if mode == "":
		return
	if row.has("anchor_wave") and RunData.current_wave < int(row["anchor_wave"]):
		return
	if row.has("gold_end") and wave_time_left <= float(row.get("end_secs", 8.0)):
		return    # the end-of-wave sweep needs the leash off, or it only sweeps the pod

	var point = far_corner * 0.5
	var radius = float(row.get("anchor_radius", 0.0))
	var inner = float(row.get("anchor_inner", 0.0))

	if mode == "builder":
		if RunData.current_wave <= BUILDER_ECON_WAVES:
			return    # phase 1 roams to collect; a leash would cost every material
		var turret = _builder_turret(spawner)
		if turret == null:
			return
		point = turret.position
		# Leash to the turret's own firing circle: enemies chasing a player
		# inside it are enemies the turret gets to shoot.
		var turret_range = float(turret.stats.max_range) if turret.stats else BUILDER_ANCHOR_MAX
		radius = clamp(turret_range, BUILDER_ANCHOR_MIN, BUILDER_ANCHOR_MAX)
	elif mode == "structures" or mode == "away_structures":
		# The centroid, not the nearest: Engineer's turrets spawn as a POD and
		# the pod's middle is the spot the guides describe standing in. With one
		# structure the centroid is that structure, so Mage's keep-away works off
		# the same number.
		var c = _structure_centroid(spawner)
		if c.empty():
			return
		point = c[0]
	elif mode != "center" and mode != "perimeter":
		return
	# center and perimeter both anchor on the arena middle and differ only in
	# which side of it costs: a perimeter row sets inner and no radius, so the
	# cheapest floor is the rim and the bot laps it instead of parking on a wall.

	profile["anchor"] = point
	if radius > 0.0:
		profile["anchor_radius"] = radius
	if inner > 0.0:
		profile["anchor_inner"] = inner


func _structure_centroid(spawner) -> Array:
	if not ("structures" in spawner):
		return []
	var sum = Vector2.ZERO
	var n = 0
	for s in spawner.structures:
		if is_instance_valid(s):
			sum += s.position
			n += 1
	if n == 0:
		return []
	return [sum / n]


func _builder_turret(spawner):
	if not ("structures" in spawner):
		return null
	for s in spawner.structures:
		if is_instance_valid(s) and s is BuilderTurret:
			return s
	return null


func _builder_gold_value() -> float:
	var phase = 1
	var struct_range = 0
	if RunData.current_wave > BUILDER_ECON_WAVES:
		struct_range = int(RunData.get_player_effect(Keys.structure_range_hash, 0))
		phase = 2 if BuilderTurret.get_level(struct_range) < BUILDER_TURRET_MAX_LEVEL else 3
	if phase != _builder_phase:
		_builder_phase = phase
		print("BOTLOG BUILDER phase=%d wave=%d struct_range=%d" % [
				phase, RunData.current_wave, struct_range])
	if gold_value_override != null:
		return gold_value_override
	if phase == 1:
		return GOLD_VALUE            # economy first, collect everything
	if phase == 2:
		return BUILDER_GOLD_VALUE    # feed the turret to its final tier
	return BUILDER_GOLD_LATE         # maxed; take some, not all


func _add_unit(unit, pos: Vector2, range_sq: float, target_range_sq: float, pickup_sq: float) -> void:
	if unit.dead or unit._pending_die:
		return
	if unit.has_method("get_charmed_by_player_index") and unit.get_charmed_by_player_index() != -1:
		return    # allied, harmless

	var offset = unit.position - pos
	var dist_sq = offset.length_squared()

	if unit.is_loot:
		# Loot aliens flee and are worth chasing, not avoiding.
		if dist_sq < pickup_sq:
			rewards.push_back([unit.position, 4.0])
		return

	var radius = _body_radius(unit)
	var damage = DEFAULT_CONTACT_DAMAGE
	if unit.current_stats and unit.current_stats.damage > 0:
		damage = float(unit.current_stats.damage)

	# Targets reach further than threats: a weapon can outrange the distance at
	# which an enemy endangers us, and clipping targets to the threat radius
	# blinded the bot to things it could already be shooting.
	if dist_sq < target_range_sq:
		targets.push_back([unit.position, _kill_value(unit, damage)])

	if dist_sq >= range_sq:
		return    # too far to threaten us this horizon

	var corridor = _dash_corridor(unit)
	if not corridor.empty():
		threats.push_back(corridor)
		return    # a dashing body is described by its dash, not by its walk

	# Idle charger: not dashing yet, but its cooldown is a clock. Standing
	# inside its launch range when that clock runs out is a choice, and the
	# arbiter can only price it if it knows the range and the remaining time.
	var ab = unit._current_attack_behavior
	if ab is ChargingAttackBehavior:
		chargers.push_back([unit.position, float(ab.max_range), damage,
				max(ab._current_cd, 0.0) / 60.0])    # _current_cd counts frames

	# Model the walker as moving at its own speed toward wherever it is headed.
	# Most enemies chase the player directly, but fly-likes commit to a frozen
	# point near us — steering at the player would put them somewhere they were
	# never going. Over a sub-second horizon this is close enough, and it is
	# what makes contact cost fall out of geometry instead of a panic ramp.
	var chase = Vector2.ZERO
	var unit_speed = 0.0
	if unit.current_stats:
		# Speed boosts live OUTSIDE current_stats: a pursuer's boost_self()
		# accumulates in Unit.bonus_speed (+45 per second, up to +450, reset on
		# hit), so reading current_stats alone models a 600 px/s chaser at 150.
		# That error poisons both uses of this number -- the projected future
		# position (the pursuer "cannot reach us this horizon" while actually
		# crossing 480 px of it) and _contact_ticks' can-you-outrun test (150
		# says shed it at once; 600 says it never lets go). The observed failure
		# mode is exactly that: the bot stands while a boosted pursuer walks the
		# last 400 px into it. decaying_bonus_speed is the same channel with a
		# sign: knockback slows really do make a body less able to reach us.
		unit_speed = max(float(unit.current_stats.speed)
				+ bonus_speed_scan * (float(unit.bonus_speed)
				+ float(unit.decaying_bonus_speed)), 0.0)
		var goal = pos
		var mb = unit._current_movement_behavior
		if mb and ("_current_target" in mb) and mb._current_target != Vector2.ZERO:
			goal = mb._current_target
		var toward = goal - unit.position
		if toward.length_squared() > 1.0:
			chase = toward.normalized() * unit_speed
	# The optional 9th field is the body's killability (same falloff as
	# _kill_value): the arbiter's fire_still discount reads it to price
	# "standing here SHOOTS this thing before it arrives". Contact threats
	# only -- a bullet cannot be shot down and a dash connects regardless.
	var health = 20.0
	if unit.current_stats and unit.current_stats.health > 0:
		health = float(unit.current_stats.health)
	threats.push_back([unit.position, chase, radius, damage, KIND_CONTACT, 0.0,
			_contact_ticks(unit_speed), INF_TIME,
			_kill_ref / (_kill_ref + health)])


# Returns a dash threat tuple, or [] if this unit is not currently dashing or
# winding up a dash. Either way it is one moving body; a wind-up is the same
# body with its motion deferred until the telegraph animation finishes.
func _dash_corridor(unit) -> Array:
	var behavior = unit._current_attack_behavior
	if not (behavior is ChargingAttackBehavior):
		return []

	var in_flight = unit._move_locked
	var winding_up = (not unit._can_move) and (not in_flight)
	if not (winding_up or in_flight):
		return []
	if winding_up and behavior.target_calculation_timing != ChargingAttackBehavior.Timing.START_SHOOT:
		return []    # direction is not decided yet, so there is nothing to dodge

	var charge_dir = behavior._charge_direction
	if charge_dir.length_squared() < 1.0:
		return []

	var dir = charge_dir.normalized()
	# Same bonus_speed blindness as the walker fix above: a dash rides on the
	# unit's live base speed, boosts included.
	var dash_speed = max(float(unit.current_stats.speed)
			+ bonus_speed_scan * (float(unit.bonus_speed)
			+ float(unit.decaying_bonus_speed)), 0.0) + behavior.charge_speed
	var radius = _body_radius(unit)
	var damage = DEFAULT_CONTACT_DAMAGE
	if unit.current_stats and unit.current_stats.damage > 0:
		damage = float(unit.current_stats.damage)

	var launch_delay = 0.0
	if not in_flight:
		launch_delay = _windup_remaining(unit)
	# A dash connects once and then the charger is spent and recovering, so it
	# is not priced as sustained contact however fast the corridor moves.
	return [unit.position, dir * dash_speed, radius, damage, KIND_DASH, launch_delay,
			TICKS_ONCE, INF_TIME]


# Seconds until a winding-up charge actually launches. The telegraph animation
# is a fixed WINDUP_ANIM_LENGTH played at the behavior's playback speed, so the
# remaining time is readable rather than guessed. Falling back to zero treats
# the dash as already moving, which errs toward dodging early.
func _windup_remaining(unit) -> float:
	var anim = unit._animation_player
	if anim == null or not anim.is_playing():
		return 0.0
	var speed = max(anim.playback_speed, 0.01)
	return max(WINDUP_ANIM_LENGTH - anim.current_animation_position, 0.0) / speed


# Projectiles parented to a boss rather than to EnemyProjectiles. Currently that
# means Pivot-mounted orbiters; the Pivot carries the angular rate we need.
func _add_attached(unit, pos: Vector2, range_sq: float) -> void:
	if unit.dead or unit._pending_die:
		return
	for child in unit.get_children():
		if not (child is Pivot):
			continue
		# pivot.gd: rotation += direction * rotation_speed * accessibility * delta
		var omega = child.direction * child.rotation_speed \
				* RunData.current_run_accessibility_settings.speed
		for orb in child.get_children():
			if not (orb is Projectile):
				continue
			if not orb._hitbox or not orb._hitbox.active or orb._hitbox.is_disabled():
				continue
			_add_orbiter(orb, child, omega, pos, range_sq)


func _add_orbiter(p, pivot, omega: float, pos: Vector2, range_sq: float) -> void:
	# global_*, not position/rotation: these are nested two levels under the
	# boss, so the local transform is meaningless in world terms.
	var center = p.global_position
	if p._hitbox and p._hitbox._collision:
		center = p.global_position \
				+ (p._hitbox.position + p._hitbox._collision.position).rotated(p.global_rotation)
	if center.distance_squared_to(pos) > range_sq:
		return

	var radius = _projectile_radius(p)
	var damage = _projectile_damage(p)
	var arm = center - pivot.global_position
	var step = SIN_DRIFT_HORIZON / float(ORBIT_SAMPLES)
	# Widen by how far along the arc it travels inside one sample window.
	var drift = min(abs(omega) * arm.length() * step * 0.5, ORBIT_SMEAR_MAX)
	for i in range(ORBIT_SAMPLES):
		var t0 = float(i) * step
		var t1 = t0 + step
		var mid = (t0 + t1) * 0.5
		var at = pivot.global_position + arm.rotated(omega * mid)
		threats.push_back([at, Vector2.ZERO, radius + drift, damage, KIND_PROJ,
				t0, TICKS_ONCE, t1])


func _add_projectile(p, pos: Vector2, range_sq: float) -> void:
	# The danger is where the hitbox is, not where the node is: a slash carries
	# its blade at a rotated offset, so a node-centered threat misses by a body
	# width on exactly the attacks that hurt most.
	var center = p.position
	if p._hitbox and p._hitbox._collision:
		center = p.position + (p._hitbox.position + p._hitbox._collision.position).rotated(p.rotation)
	if center.distance_squared_to(pos) > range_sq:
		return

	var radius = _projectile_radius(p)
	var damage = _projectile_damage(p)

	if p.velocity.length_squared() < STATIONARY_SPEED_SQ:
		# Read the pillar's clock off its animation, exactly as _windup_remaining
		# does for a charge. Unknown animation state falls through as "live now,
		# never expires", which is the old behaviour -- so an AoE type that does
		# not animate like a pillar is still feared rather than silently ignored.
		var arm_in = 0.0
		var disarm_in = INF_TIME
		var profile = {"swept": false}
		var anim = p._animation_player
		if anim and anim.is_playing():
			profile = _aoe_profile(anim)
			if aoe_clock != 0.0:
				var anim_speed = max(anim.playback_speed, 0.01)
				var anim_pos = anim.current_animation_position
				if anim_pos >= profile["disarm"]:
					return    # already spent; stop fleeing dead telegraphs
				arm_in = max(profile["arm"] - anim_pos, 0.0) / anim_speed
				disarm_in = (profile["disarm"] - anim_pos) / anim_speed
		var dmg = _aoe_damage(p)
		for seg in _stationary_segments(p, profile):
			threats.push_back([seg[0], Vector2.ZERO, seg[1], dmg, KIND_AOE,
					arm_in, TICKS_ONCE, disarm_in])
		return

	# A MOVING telegraphed projectile -- a colossus pillar, fired at 150 or 300
	# rather than parked -- is armed for the same 0.14 s slice as a stationary
	# one, but it used to fall straight through to the always-live branch below.
	# So an 18-pillar ring spawned around the player at 400 px read as an
	# impassable wall, when in truth every pillar in it is inert for its first
	# 0.54 s: over half a second in which the bot can simply walk out between
	# them. That is the colossus encircling attack, and this is why it could not
	# be answered.
	#
	# Gated on `windowed`, so it applies ONLY where a genuine
	# enable_hitbox/disable_hitbox pair exists. Ordinary bullets have no method
	# track and are untouched.
	var m_anim = p._animation_player
	if aoe_clock != 0.0 and moving_clock != 0.0 and m_anim and m_anim.is_playing():
		var m_prof = _aoe_profile(m_anim)
		if m_prof["windowed"]:
			var m_speed = max(m_anim.playback_speed, 0.01)
			var m_pos = m_anim.current_animation_position
			if m_pos >= m_prof["disarm"]:
				return    # already spent; its hitbox will never come back
			var m_arm = max(m_prof["arm"] - m_pos, 0.0) / m_speed
			var m_off = (m_prof["disarm"] - m_pos) / m_speed
			# Carry the threat forward to where it will be when it goes live --
			# the scorer defers a threat's MOTION until T_START (that is what
			# makes a dash wind-up tractable), which is wrong for something
			# already in flight.
			var carry = p.velocity * m_arm

			# A FLYING blade is still a blade. mom throws slash_projectile_2 at
			# 650: geometrically identical to the butcher's -- sweeps -122..143,
			# peaks at 273x28, armed 0.48-0.60 -- but the decomposition lived
			# only in the stationary branch, so in flight it was priced as a
			# CIRCLE of radius max(extents) = 136 against a blade 14 px thin.
			# That is the same ~10x perpendicular over-estimate that made the
			# butcher undodgeable as a 320 px disc, and mom's slashes are the
			# single largest killer on w11-dwarf at 2.0 hits/run.
			#
			# Circles are deliberately left on the old single-radius path: a
			# moving pillar (colossus) is already validated at 29/30, and
			# routing it through _stationary_segments would apply the pillar
			# footprint inflation it does not currently get.
			var m_shape = null
			if p._hitbox and p._hitbox._collision:
				m_shape = p._hitbox._collision.shape
			if moving_blade != 0.0 and blade_split != 0.0 and m_shape is RectangleShape2D:
				for seg in _stationary_segments(p, m_prof):
					threats.push_back([seg[0] + carry, p.velocity, seg[1],
							damage, KIND_PROJ, m_arm, TICKS_ONCE, m_off])
			else:
				threats.push_back([center + carry, p.velocity, radius,
						damage, KIND_PROJ, m_arm, TICKS_ONCE, m_off])
			return

	# Weaving bullets: sample the sine rather than smearing it. See the
	# SIN_SAMPLES block above for why a fat radius fails on the +-600 variants.
	var amp = 0.0
	if "sinusoidal_motion" in p and p.sinusoidal_motion is Vector2:
		amp = p.sinusoidal_motion.length()
	if amp <= SIN_SIGNIFICANT or sine_sample == 0.0:
		# Gentle weave (or feature disabled): the old bound is cheap and tight.
		threats.push_back([center, p.velocity, radius + amp * 0.5 * SIN_DRIFT_HORIZON,
				damage, KIND_PROJ, 0.0, TICKS_ONCE, INF_TIME])
		return

	# Integrate position along the real path. Each sample becomes its own threat,
	# live only for the slice of time the bullet actually occupies it -- so a
	# bullet that will be somewhere in 0.6 s does not deny that ground now.
	var span = SIN_DRIFT_HORIZON
	var step = span / float(SIN_SAMPLES)
	var t_now = p.sinusoidal_time
	var rate = p.sinusoidal_motion_speed
	var amp_v = p.sinusoidal_motion * 0.5
	# NOT named `pos`: that is already a parameter of this function, and
	# redeclaring it is a GDScript parse error -- which fails world_view, fails
	# player_movement_behavior's preload of it, and drops the whole movement
	# extension with no error logged. Symptom is 7 extensions instead of 8 and a
	# bot that never steers.
	var sim_pos = center
	var sub = step / 4.0                     # integrate finer than we emit
	var elapsed = 0.0
	for _i in range(SIN_SAMPLES):
		var seg_start = elapsed
		for _s in range(4):
			t_now += Vector2(sub * rate.x, sub * rate.y)
			var off = Vector2(sin(t_now.x), sin(t_now.y)) * amp_v
			sim_pos += (p.velocity + off) * sub
			elapsed += sub
		# Radius covers the bullet plus how far it can stray between samples.
		var drift = min(amp * 0.5 * step, SIN_SMEAR_MAX)
		threats.push_back([sim_pos, Vector2.ZERO, radius + drift, damage, KIND_PROJ,
				seg_start, TICKS_ONCE, elapsed])


# Pillar damage is stamped on the hitbox at spawn like every other projectile's,
# so read it rather than assuming. The old hardcoded AOE_DAMAGE = 10 happened to
# sit right next to a wave-6 gargoyle pillar (10-11 observed in play) and drifts
# everywhere else: that attack carries damage_increase_each_wave = 1.15, so the
# constant is progressively too small as a run goes on -- under-fearing exactly
# the attack that gets deadliest.
func _aoe_damage(p) -> float:
	if p._hitbox and ("damage" in p._hitbox) and p._hitbox.damage > 0:
		return float(p._hitbox.damage)
	return AOE_DAMAGE


# One or more [world_center, radius] circles covering a stationary hitbox.
# A blob returns one circle (unchanged); a blade returns a line of them.
func _stationary_segments(p, profile: Dictionary) -> Array:
	var hb = p._hitbox
	if not hb or not hb._collision:
		return [[p.position, 8.0]]
	var base = hb.position + hb._collision.position
	var shape = hb._collision.shape

	if blade_split != 0.0 and shape is RectangleShape2D:
		# extents are HALF-extents; work in the rectangle's own frame, then
		# rotate each segment out by the projectile's rotation.
		var half_long = shape.extents.x
		var half_thin = shape.extents.y
		# Prefer the swept union: the live pose is only where the blade is at
		# this instant, and during the wind-up that is its starting stub.
		if sweep_union != 0.0 and profile.get("swept", false):
			base = hb.position + profile["centre"]
			half_long = profile["half"].x
			half_thin = profile["half"].y
		var along = Vector2(1.0, 0.0)
		if half_thin > half_long:
			var swap = half_long
			half_long = half_thin
			half_thin = swap
			along = Vector2(0.0, 1.0)
		# Only split what is actually elongated; a squarish box stays one circle.
		var n = int(clamp(ceil(half_long / max(half_thin, 1.0)), 1, BLADE_SEGMENTS_MAX))
		# Segment radius must still span the gaps left by capping n, so it is the
		# larger of the true thinness and the spacing it has to cover.
		var r = max(half_thin, half_long / float(n)) * BLADE_MARGIN
		var out = []
		for i in range(n):
			var t = -half_long + 2.0 * half_long * (float(i) + 0.5) / float(n)
			out.push_back([p.position + (base + along * t).rotated(p.rotation), r])
		return out

	# Circles (pillars) keep the old footprint inflation: their rest-pose
	# collision genuinely understates the telegraph they draw on the ground.
	var reach = _projectile_radius(p) + base.length()
	return [[p.position + base.rotated(p.rotation),
			min(reach * AOE_RADIUS_MULT, AOE_RADIUS_MAX)]]


func _projectile_radius(p) -> float:
	if not p._hitbox or not p._hitbox._collision:
		return 8.0
	var shape = p._hitbox._collision.shape
	if shape is CircleShape2D:
		return shape.radius
	if shape is RectangleShape2D:
		return max(shape.extents.x, shape.extents.y)
	return 8.0


# Hitbox.damage is where the real number lives: the shooter stamps it there at
# spawn, so it already accounts for wave scaling and danger level.
func _projectile_damage(p) -> float:
	if p._hitbox and ("damage" in p._hitbox) and p._hitbox.damage > 0:
		return float(p._hitbox.damage)
	if "damage" in p and p.damage > 0:
		return float(p.damage)
	return DEFAULT_PROJ_DAMAGE


# What killing this enemy is worth, in HP we would otherwise lose.
#
# Two factors. How much damage it does to us if it lives -- its contact damage
# over a few exchanges. And how likely we are to actually kill it soon: a 4 HP
# charger dies to a burst, an 880 HP boss does not, and rewarding the bot for
# hugging a boss it cannot kill is how a naive DPS term gets you killed.
#
# Eggs are the exception that drives the whole design. They barely damage you
# themselves, so a damage-based value scores them near zero -- but everything
# they hatch is future damage, compounding for the rest of the wave. Killing
# one early is worth far more than killing any single thing it spawns, which
# is why they carry a flat high value rather than a damage-derived one.
func _kill_value(unit, damage: float) -> float:
	var health = 20.0
	if unit.current_stats and unit.current_stats.health > 0:
		health = float(unit.current_stats.health)
	var killability = _kill_ref / (_kill_ref + health)

	var value = damage * EXPECTED_EXCHANGES
	if _is_egg(unit):
		value = max(value, EGG_VALUE)
	return value * killability


func _is_egg(unit) -> bool:
	if ("_attack_behavior" in unit) and unit._attack_behavior is SpawningAttackBehavior:
		return true
	return unit._current_attack_behavior is SpawningAttackBehavior


# Expected share of a nominal hit that actually reaches our HP. Dodge removes
# hits outright and armor scales them down, so a heavily armored build should
# genuinely be willing to walk through fire the fragile one must avoid.
func _mitigation(player) -> float:
	var m = 1.0
	var stats = player.current_stats
	if stats and ("dodge" in stats):
		m *= 1.0 - clamp(float(stats.dodge), 0.0, 0.9)
	if stats and ("armor" in stats):
		m *= clamp(RunData.get_armor_coef(stats.armor), 0.1, 1.0)
	return max(m, 0.05)


func _body_radius(unit) -> float:
	if unit._hurtbox and unit._hurtbox._collision:
		var shape = unit._hurtbox._collision.shape
		if shape is CircleShape2D:
			return shape.radius
	return BODY_RADIUS_FALLBACK


# Kite by ranged weapons only: one melee sidearm must not drag the whole build
# down to knife range.
func _weapon_range(player) -> float:
	var best = 1000.0
	var has_ranged = false
	for weapon in player.current_weapons:
		if weapon.current_stats is RangedWeaponStats:
			has_ranged = true
	for weapon in player.current_weapons:
		if has_ranged and not (weapon.current_stats is RangedWeaponStats):
			continue
		if weapon.current_stats.max_range < best:
			best = weapon.current_stats.max_range
	return best
