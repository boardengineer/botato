extends "res://entities/units/movement_behaviors/player_movement_behavior.gd"

# Two steering controllers live behind this one entry point so they can be
# A/B'd on identical seeds: the potential field below, and the candidate-action
# arbiter in steering/. AutobattlerOptions.use_arbiter selects between them.
const Arbiter = preload("res://mods-unpacked/Pasha-AutoBattler/steering/arbiter.gd")
const WorldView = preload("res://mods-unpacked/Pasha-AutoBattler/steering/world_view.gd")

# -- Tap-move tuning (fire_still characters; see the interleave in _arbiter_move) --
const TAP_MOVE = 2               # frames of travel per tap cycle (4 -> 2: half the
                                 # travel per volley -- the aggressive stutter; net
                                 # speed 50% instead of 67%, fire uptime up)
const TAP_STOP = 2               # frames of stand-and-volley per cycle (0 disables)
const TAP_SAFE_GAP = 35.0        # only tap while standing scores within this of the
                                 # chosen move; beyond it the move is a dodge.
                                 # 25 -> 35: keep stuttering under moderate threat
                                 # pressure; real dodge gaps run far past this
var _tap_phase = 0
var _hdg_run = 0                 # consecutive still frames (survives take_heading_stats)
var _hdg_ticks = 0               # full seconds stood since the last stats window
var _hdg_breaks = 0              # stands broken since the last stats window

var _arbiter = null
var _world = null
var arbiter_active = false               # read by ai_telemetry / ai_canvas

# Per-frame heading statistics, drained once a second by ai_telemetry.
# The player moves at constant speed along the chosen heading every physics
# frame, so over a window: path length = speed*dt*n and net displacement =
# speed*dt*|sum of headings|. Their ratio, |sum|/n, IS path efficiency --
# 1.0 for a straight line, 0 for perfect oscillation. That measures directly
# what a 1 Hz sample of the decision can only hint at.
var _hdg_sum = Vector2.ZERO
var _hdg_count = 0
var _hdg_turn_sum = 0.0
var _hdg_flips = 0
var _hdg_prev = Vector2.ZERO
var _hdg_still = 0

# -- Charge dodging --
const CHARGE_DODGE_STRENGTH = 0.01       # strong but must not erase swarm/bullet terms (~0.001)
const CHARGE_BOSS_DODGE_MULT = 3.0       # boss dashes one-shot; their dodge overrides bullet noise
const CHARGE_CORRIDOR_HALF_WIDTH = 100.0 # player half-size + margin; body radius added on top
const CHARGE_LOOKAHEAD_MARGIN = 150.0    # corridor extends past dash end / behind start
const CHARGE_DODGE_NEAR = 400.0          # full dodge strength within this distance, fades beyond
const CHARGE_RADIAL_BIAS = 0.4           # mix of away-from-charger into the sideways escape
const CHARGE_INFLIGHT_MULT = 1.5         # a dash already in flight: the lateral budget is all that's left
const CHARGER_PANIC_RADIUS = 250.0       # idle charger can launch a 1000 px/s dash any frame; 120 px is for walkers
const DODGE_WALL_ROOM_CAP = 400.0        # side scoring: wall room beyond this doesn't matter
const DODGE_ENEMY_ROOM_CAP = 300.0       # side scoring: enemy-free room beyond this doesn't matter
const CROSSFIRE_STRENGTH = 0.04          # exit push when 2+ dash corridors cross us at once
const CROSSFIRE_COMMIT_MS = 300          # hold the picked crossfire exit briefly
const CROSSFIRE_BOSS_MULT = 2.5          # a boss among the corridors: exit push must not be weaker than the single-boss dodge
const CROSSFIRE_ENEMY_RANGE_SQ = 360_000.0 # enemies within 600 px weigh into the exit choice
const CROSSFIRE_STICK_BONUS = 40.0       # 300 ms re-picks between near-tied exits must not flip-flop to a standstill
const CHARGE_ATTRACT_DAMP = 0.1          # loot isn't going anywhere during a 1 s dash; don't let it rotate the dodge
const CHAIN_DASH_COOLDOWN = 60.0         # frames; quicker charge behaviors re-aim constantly (croc 15/45, rhino 100)
const CHAIN_DASH_RANGE_MARGIN = 1.1      # stay outside a chain-dasher's launch range with a little slack
const BOSS_DASH_STANDOFF = 400.0         # slow-cycling dash elites (mantis 80f, rhino 100f) fall through the
                                         # chain-dash rule; a 231 px launch gap is a free kill at 800 px/s
const BOSS_FLEE_PROBE = 300.0            # look this far along the flee heading for wall room
const BOSS_FLEE_ROOM_MIN = 340.0         # less room than this ahead: orbit instead of backing into the corner
                                         # (260 fired ~1.5 s pre-death in the mantis corner; turn earlier)
const WINDUP_RADIAL_BIAS = 0.35          # boss windup: blend retreat into the sidestep (in-flight stays pure lateral)
# -- Elite & boss caution --
const BODY_RADIUS_FALLBACK = 40.0        # when hurtbox shape isn't a CircleShape2D
const ELITE_REPEL_MULT = 3.0             # repulsion inside kite range 3x attraction
const ELITE_DANGER_BASE = 120.0          # danger zone beyond body edge at full HP
const ELITE_DANGER_HP_BONUS = 180.0      # danger zone growth as HP fraction drops to 0
const DANGER_RAMP_MAX = 8.0              # cap on inside-danger-zone repulsion ramp (~1/d^4)
const DAMAGE_CAUTION_MAX = 4.0           # cap on contact-damage / current-HP scaling
# -- HP-aware kiting --
const KITE_HP_FACTOR = 0.4               # kite radius grows to weapon_range*1.4 at 0 HP
const KITE_REPEL_MULT = 3.0              # repulsion inside kite range out-votes swarm attraction (parity
                                         # with ELITE_REPEL_MULT; at x1 the equilibrium settled at nearE
                                         # 99-190 on ranged builds — user: "why so close with all ranged?")
const IN_RANGE_ATTRACT_DAMP = 0.35       # damp gold/food/distant-enemy pull while already in weapon range
const ENEMY_PANIC_RADIUS = 120.0         # inside this, contact repulsion ramps ~1/d^4
const ENEMY_PANIC_RAMP_MAX = 10.0        # cap on that ramp (was 6; close-range contact still
                                         # out-damaged everything — user asked for harder shove)
# -- Projectiles --
const PROJECTILE_RANGE_SQ = 250_000.0    # 500 px cutoff
const STATIONARY_SPEED_SQ = 100.0        # velocity < 10 px/s => ground AoE (pillar)
const AOE_HARMLESS_ANIM_POS = 0.7        # pillar hitbox is only armed 0.54-0.68s into its 1.05s anim
const AOE_AVOID_RADIUS_MULT = 4.0        # avoid live AoE within hitbox_radius*4 (visual > hitbox)
const AOE_AVOID_RADIUS_MAX = 320.0       # cap: slash arcs have big offsets and x4 would quarantine half the map
const AOE_PANIC_RAMP_MAX = 8.0           # inside the footprint, repulsion ramps ~1/d^4 up to this
const AOE_FLEE_MIN = 2                   # this many pillars within ENCIRCLE_AOE_RADIUS = on-player cluster
const AOE_FLEE_STRENGTH = 0.05           # a centered cluster cancels its own repulsion; commit and sprint
const AOE_FLEE_COMMIT_MS = 400           # hold the exit until (nearly) clear of the telegraph
const PROJ_CLOSE_ALWAYS_SQ = 10_000.0    # within 100 px repel regardless of heading
const PROJ_PANIC_RAMP_MAX = 8.0          # point-blank shots ramp like AoE/danger zones do
                                         # (was flat weight/d^2 — the only close threat without a ramp)
const PROJ_CORRIDOR_MARGIN = 60.0        # player half-size + margin for line-of-fire test
const PROJ_IMMINENT_TTI = 0.7            # seconds to impact that makes a shot "imminent"
const PROJ_DODGE_STRENGTH = 0.025        # beats swarm/attraction noise, stays under gap escape
const PROJ_DODGE_COMMIT_MS = 250         # hold the multi-shot exit briefly
# -- F3: volume bullet dodging (see tools/STEERING-FEATURES.md) --
const PROJ_VOLUME_MIN = 5                # this many airborne shots = volume fire; field exit even without 2 imminent corridors
const PROJ_LANE_REACH_T = 0.9            # s; a lane matters if its shot can sweep the probe point within this
const PROJ_LANE_MARGIN = 2.0             # lane influence width = hitbox half-width x this (near-misses steer too)
const PROJ_FIELD_WEIGHT = 90.0           # 16-dir exit scoring: penalty for one dead-center imminent lane
const PROJ_FIELD_WEIGHT_SIDE = 70.0      # single-shot sidestep must not step into ANOTHER lane
# -- F6: slow-bullet distance floor (danger-6 environmental fields) --
# Time-based gates make slow shots near-invisible: a 204 px/s event bullet
# got a 143 px corridor vs a spitter's 420 px, so the bot idled through
# bullet streams taking free drip damage. Distance also satisfies the gate
const PROJ_IMMINENT_MIN_DIST = 220.0     # a shot this close is imminent no matter how slow
const PROJ_LANE_MIN_REACH = 300.0        # a lane sweeps probe points this far out no matter how slow
# -- Rear-aligned fire (w8-gangster: spitters run the dodge down from behind) --
# Fleeing collinear with a faster aimed shot is a lost race (PHIT dots
# +0.8..0.98 at the moment of impact, with the dodge committed). Lateral
# probes cannot see this — the lane must be checked against the ESCAPE dir
const REAR_LANE_ALIGN = 0.7              # escape.dot(shot dir) above this = fleeing along the lane
const REAR_LANE_DEFLECT = 0.8            # tangential blend mixed into the committed escape (~39 deg)
const REAR_LANE_WEIGHT = 120.0           # 16-dir exits: penalty for candidates a rear shot chases down
# -- F4: burst-interrupt caution (archived f4-burst-caution; +7 solo on the bed) --
# w8-gangster deaths are bruiser-contact CHAINS: the 2nd and 3rd 13-dmg hits
# land while a committed behavior keeps driving through the same cluster
const BURST_HITS_TRIGGER = 2             # this many hits inside BURST_WINDOW_MS arms caution
const BURST_WINDOW_MS = 2000
const BURST_HP_FRACTION = 0.4            # or this share of max HP lost inside 3 s
const CAUTION_MS = 2500                  # how long the caution state holds
const CAUTION_REPEL_MULT = 1.5           # repel gain boost while cautious
const CAUTION_ATTRACT_DAMP = 0.1         # loot/gold pull while cautious
const CAUTION_PANIC_MULT = 1.5           # contact panic radius widening while cautious
const CAUTION_COMMIT_SCALE = 0.5         # commitment timers halve: escapes re-evaluate sooner
# -- Dash-cascade breaker --
# w8-gangster v4 deaths: 13+13 double hits ~1-2 s apart — after a dash lands
# the bruiser sits at knife range and its 1 s-cooldown re-dash from 40-90 px
# is unavoidable. Its cooldown window is FREE: sprint the gap open so the
# next launch comes from dodgeable range. Only while no dash is in flight
const CASCADE_FLEE_RADIUS_SQ = 90_000.0  # charger within 300 px while cautious = cascade risk
const CASCADE_FLEE_STRENGTH = 0.05       # dominates the field during the free window; corridors gate it off
const PROJ_SLIDE_BODY = 30.0             # lane slide: our body radius + bullet radius, roughly
const PROJ_SLIDE_INFLUENCE = 1.8         # lane slide influence = (bullet half + body) x this
# -- Loot / eggs --
const LOOT_CHASE_MULT = 50.0             # attraction multiplier for loot aliens
# -- Map edges --
const EDGE_GUARD_DISTANCE = 280.0        # inward push starts this close to a wall (pillar fields herd us outward)
const EDGE_GUARD_STRENGTH = 0.04         # strong enough to beat swarm/barrage pressure, not a charge dodge
const WALL_SLIDE_DISTANCE = 130.0        # this close to a wall, drop the into-wall movement component
# -- Encirclement escape (fly rings, pillar rings) --
const ENCIRCLE_RADIUS = 320.0            # threats inside this ring count toward encirclement
const ENCIRCLE_AOE_RADIUS = 160.0        # stationary AoE this close counts as a ring threat
const ENCIRCLE_MIN_THREATS = 5           # fewer than this can't meaningfully surround us
const ENCIRCLE_COVERAGE_DEG = 260.0      # occupied angular span that counts as "surrounded"
const ESCAPE_STRENGTH = 0.06             # dominates the cancelled-out ring field
const ESCAPE_COMMIT_MS = 500             # hold the chosen gap this long before re-picking
# -- Expanding-ring counter-steer (colossus/gargoyle pillar bursts) --
const WAVE_SPEED_SQ = 122_500.0          # shots slower than 350 px/s count as wave/ring shots
const WAVE_MIN_COUNT = 6                 # this many coherent slow shots = a wave, not stray fire
const WAVE_COHERENCE = 0.5               # mean unit-velocity length (0..1): shared drift direction
const WAVE_COUNTER_STRENGTH = 0.05       # upstream push; fleeing WITH a ring ends pinned at a wall

var _escape_dir = Vector2.ZERO
var _escape_until_ms = 0
var escaping = false                     # read by ai_telemetry / ai_canvas
var _counter_dir = Vector2.ZERO
var countering = false                   # read by ai_telemetry / ai_canvas
var _crossfire_dir = Vector2.ZERO
var _crossfire_until_ms = 0
var crossfiring = false                  # read by ai_telemetry / ai_canvas
var _aoe_flee_dir = Vector2.ZERO
var _aoe_flee_until_ms = 0
var aoe_fleeing = false                  # read by ai_telemetry / ai_canvas
var dodging = false                      # single-corridor sidestep active; read by ai_telemetry
var last_corridor_count = 0              # actual corridors this frame; read by ai_telemetry
var _proj_dodge_dir = Vector2.ZERO
var _proj_dodge_until_ms = 0
var proj_dodging = false                 # imminent-bullet dodge active; read by ai_telemetry
var last_move_dir = Vector2.ZERO         # final vector last frame; read by ai_telemetry
var last_arb_us = 0                      # microseconds spent in the last gather+choose
# -- Decision interval --
# Measured on the tracker Pacifist beds: gather+choose costs 0.2 ms on an
# empty field and 8-12 ms with 100+ threats (us= in the ARB line), against a
# 16.7 ms frame budget -- the steering IS the late-wave stutter. Above the
# budget the decision is taken every other physics tick and the heading held
# in between; a 33 ms re-decide is well inside the horizon (0.8 s) and the
# commitments the scorer already makes (pin escape 0.6 s, crossfire
# hysteresis) -- but not inside a chain-dasher's re-aim. Measured A/B, n=10:
# loud-w11 (croc + boosting pursuers) every-tick 6/10 vs adaptive 3/10;
# fisherman w2 9 vs 10; Soldier w5-d6 8 vs 7; tracker Pacifist w7/w8 7 vs 8.
# The 33 ms reaction gap is paid exactly where it is fatal, so the DEFAULT is
# every tick and the frame-rate trade is opt-in: --arb-every=0 is adaptive
# (skip alternate ticks while a decision costs more than ARB_BUDGET_US),
# --arb-every=N a fixed interval. Skipped ticks still run the tap-move
# interleave and heading stats below. The arbiter is told the interval
# (tick_step) so its pin-escape frame counters keep counting frames.
const ARB_BUDGET_US = 5000               # adaptive threshold: skip alternate ticks above this
var arb_every = 1                        # --arb-every; 1 = every tick (default), 0 = adaptive
var _arb_tick = 0
var _arb_decided = false
# Decision history for the telegraph post-mortem (ai_telemetry PHIST): the
# last HIST_LEN decisions as [msec, x, y, bearing deg (-999 = still),
# best cost, still cost, aoe count, hop]. Cheap: one small array per tick.
const HIST_LEN = 40
var decision_hist = []
var _dmg_events = []                     # [ms, amount], last 3 s of damage taken
var _hp_seen = - 1.0
var _caution_until_ms = 0
var cautious = false                     # F4 burst caution active; read by ai_telemetry


func get_movement()->Vector2:
	var options_node = $"/root/AutobattlerOptions"

	var enabled = options_node.enable_autobattler

	var item_weight = options_node.item_weight
	var projectile_weight = options_node.projectile_weight
	var tree_weight = options_node.tree_weight
	var boss_weight = options_node.boss_weight
	var bumper_weight = options_node.bumper_weight
	var egg_weight = options_node.egg_weight
	var bumper_distance = options_node.bumper_distance

	var player = get_parent()

	if not enabled and not CoopService.is_bot_by_index[player.player_index]:
		$"/root/Main/Camera".smoothing_enabled = false
		return .get_movement()

	arbiter_active = options_node.use_arbiter
	if arbiter_active:
		return _arbiter_move(player)

	var _entity_spawner = $"/root/Main/EntitySpawner"
	var _consumables_container = $"/root/Main/"._consumables
	var items_container = $"/root/Main/"._active_golds
	var projectiles_container = $"/root/Main/EnemyProjectiles"

	var char_name = RunData.get_player_character(0).name.to_lower()

	var is_soldier = char_name == "character_soldier"
	var is_bull = char_name == "character_bull"

	var weapon_range = 1_000
	var bumper_spacing = 50

	var max_health = float(player.max_stats.health)
	var current_health = float(player.current_stats.health)

	if is_bull:
		if current_health / max_health < .6:
			weapon_range = 1000
		else:
			weapon_range = 0

	# Kite by ranged weapons only — one melee weapon must not drop us to knife range
	var has_ranged = false
	for weapon in player.current_weapons:
		if weapon.current_stats is RangedWeaponStats:
			has_ranged = true
	for weapon in player.current_weapons:
		if has_ranged and not (weapon.current_stats is RangedWeaponStats):
			continue
		var max_range = weapon.current_stats.max_range

		if max_range < weapon_range:
			weapon_range = max_range
	var preferred_distance_squared = weapon_range * weapon_range

	# The lower our HP, the further out we kite and the harder we repel
	var hp_fraction = current_health / max_health
	var kite_distance = weapon_range * (1.0 + KITE_HP_FACTOR * (1.0 - hp_fraction))
	var kite_distance_squared = kite_distance * kite_distance
	var repel_caution = 1.0 + (1.0 - hp_fraction)

	# F4: burst-interrupt caution — two hits in 2 s (or 40% max HP in 3 s)
	# arms a short maximum-caution state: harder repel, wider panic, no loot
	# pull, half-length commitments so escapes re-evaluate immediately
	var now_ms = OS.get_ticks_msec()
	if _hp_seen > current_health:
		_dmg_events.push_back([now_ms, _hp_seen - current_health])
	_hp_seen = current_health
	while _dmg_events.size() and now_ms - _dmg_events[0][0] > 3000:
		_dmg_events.pop_front()
	var recent_hits = 0
	var recent_dmg = 0.0
	for ev in _dmg_events:
		recent_dmg += ev[1]
		if now_ms - ev[0] <= BURST_WINDOW_MS:
			recent_hits += 1
	if recent_hits >= BURST_HITS_TRIGGER or recent_dmg >= max_health * BURST_HP_FRACTION:
		_caution_until_ms = now_ms + CAUTION_MS
	# Low HP is a standing burst: at 3/30 any chip kills, but caution lapsed
	# between chips and full-length commits drove through crowds (v5 deaths
	# all ground at <35% HP for many seconds before a 7-dmg touch ended it)
	cautious = now_ms < _caution_until_ms or hp_fraction < 0.35
	if cautious:
		repel_caution *= CAUTION_REPEL_MULT
	var commit_scale = CAUTION_COMMIT_SCALE if cautious else 1.0

	var move_vector = Vector2.ZERO
	# Attraction terms are damped later when something is already in weapon range
	var attract_vec = Vector2.ZERO
	var far_corner = ZoneService.current_zone_max_position

	var consumable_weight = (1.0 - (current_health / max_health)) * 2

	# Eat consumables, weighted by missing hp
	for consumable in _consumables_container:
		var consumable_pos = consumable.position
		var consumable_to_player = consumable_pos - player.position
		var squared_distance_to_consumable = consumable_to_player.length_squared()

		var to_add = (consumable_to_player.normalized() / squared_distance_to_consumable) * 10 * consumable_weight
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			attract_vec = attract_vec + to_add

	# Go towards "items" (gold pickups)
	var item_weight_squared = item_weight * item_weight
	for item in items_container:
		var item_pos = item.position
		var item_to_player = item_pos - player.position
		var squared_distance_to_item = item_to_player.length_squared()

		var to_add = (item_to_player.normalized() / squared_distance_to_item) * item_weight_squared
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			attract_vec = attract_vec + to_add

	# Go towards "neutrals" (trees)
	var tree_weight_squared = tree_weight * tree_weight
	for neutral in _entity_spawner.neutrals:
		var neutral_pos = neutral.position
		var neutral_to_player = neutral_pos - player.position
		var squared_distance_to_neutral = neutral_to_player.length_squared()

		var to_add = (neutral_to_player.normalized() / squared_distance_to_neutral) * tree_weight_squared

		# Weigh down nearby trees to keep from getting stuck on them
		if squared_distance_to_neutral < (preferred_distance_squared / 2):
			to_add = to_add * -1
			if not is_nan(to_add.x) and not is_nan(to_add.y):
				move_vector = move_vector + to_add
		elif not is_nan(to_add.x) and not is_nan(to_add.y):
			attract_vec = attract_vec + to_add

	# Angles of nearby threats, for encirclement detection
	var threat_angles = []
	# Positions of live ground-AoE telegraphs right on top of us
	var aoe_close = []

	# Go away from projectiles
	var projectile_weight_squared = projectile_weight * projectile_weight
	var wave_vel_sum = Vector2.ZERO
	var wave_count = 0
	# Shots about to hit us: [origin, dir, half_width, lateral, urgency]
	var proj_corridors = []
	# F3: EVERY airborne shot in range, aimed at us or not: [origin, dir, half_width, speed]
	var proj_lanes = []
	for projectile in projectiles_container.get_children():
		if not (projectile is Projectile):
			continue # BulletHell wave containers live here too
		if not projectile._hitbox or not projectile._hitbox.active:
			continue
		var to_add = _get_projectile_term(projectile, player.position, projectile_weight_squared)
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add
		# The danger is where the HITBOX is, not the node: a mantis/slasher
		# slash carries its blade at a rotated ~(-112,15) offset, so lanes and
		# AoE entries centered on projectile.position miss by a body width
		var proj_center = projectile.position
		if projectile._hitbox and projectile._hitbox._collision:
			proj_center = projectile.position \
					+ (projectile._hitbox.position + projectile._hitbox._collision.position).rotated(projectile.rotation)
		var proj_off = proj_center - player.position
		var proj_speed_sq = projectile.velocity.length_squared()
		if proj_speed_sq >= STATIONARY_SPEED_SQ:
			# Line-of-fire + time-to-impact: only imminent shots earn a real dodge
			var p_speed = sqrt(proj_speed_sq)
			var p_dir = projectile.velocity / p_speed
			var p_along = (-proj_off).dot(p_dir)
			# F6: effective reach = time gate OR distance floor, so slow shots
			# get the same warning geometry as fast ones
			var p_reach = max(p_speed * PROJ_IMMINENT_TTI, PROJ_IMMINENT_MIN_DIST)
			if p_along > 0.0 and p_along < p_reach:
				var p_lateral = (-proj_off).dot(p_dir.tangent())
				var p_half = _proj_half_width(projectile)
				if abs(p_lateral) < p_half:
					proj_corridors.push_back([proj_center, p_dir, p_half, p_lateral,
							1.0 - p_along / p_reach])
			# F3: under volume fire (fisherman-w2: 15-46 shots airborne) the
			# corridor model collapses — dodging one lane steps into another.
			# Track every airborne shot in range as a lane for field scoring.
			# F6d: snake-motion bullets (danger-6 event generators) weave
			# around a straight-line lane — widen theirs by the sine amplitude
			if proj_off.length_squared() < PROJECTILE_RANGE_SQ:
				var lane_half = _proj_half_width(projectile)
				if "sinusoidal_motion" in projectile and projectile.sinusoidal_motion is Vector2:
					lane_half += projectile.sinusoidal_motion.length()
				proj_lanes.push_back([proj_center, p_dir, lane_half, p_speed])
		if proj_speed_sq < STATIONARY_SPEED_SQ:
			var spent = projectile._hitbox.is_disabled() and projectile._animation_player.is_playing() \
					and projectile._animation_player.current_animation_position > AOE_HARMLESS_ANIM_POS
			if not spent and proj_off.length_squared() < ENCIRCLE_AOE_RADIUS * ENCIRCLE_AOE_RADIUS:
				threat_angles.push_back(proj_off.angle())
				aoe_close.push_back(proj_center)
		elif proj_speed_sq < WAVE_SPEED_SQ and proj_off.length_squared() < PROJECTILE_RANGE_SQ \
				and (-proj_off).dot(projectile.velocity) > 0.0:
			# Slow shot drifting toward us: part of an expanding ring/barrage
			wave_vel_sum = wave_vel_sum + projectile.velocity.normalized()
			wave_count += 1

	var shooting_anyone = false
	var must_run_away = false
	var egg_weight_squared = egg_weight * egg_weight
	# Active dash corridors threatening us: [origin, dir, half_width, lateral, urgency, strength_mult, is_boss, length, in_flight]
	var charge_corridors = []
	var nearest_charger_sq = 1e12
	var nearest_charger_pos = Vector2.ZERO
	# Nearby enemy positions, for crossfire exit scoring
	var close_enemy_positions = []

	# Move towards distant enemies, away from nearby ones.  Determined by weapons range.
	for enemy in _entity_spawner.enemies:
		if enemy.dead or enemy._pending_die:
			continue
		if enemy.get_charmed_by_player_index() != - 1:
			continue # allied, harmless

		var corridor = _get_charge_corridor(enemy, player.position)
		if not corridor.empty():
			must_run_away = true
			charge_corridors.push_back(corridor)
			# fall through for threat angles / crossfire data, but the radial
			# term below is skipped: away-from-charger at point blank is nearly
			# DOWN the dash line and rotates the dodge into the corridor (the
			# same failure the boss continue fixed; five bruiser hits with the
			# dodge active proved it). The dodge's CHARGE_RADIAL_BIAS already
			# provides controlled retreat

		var enemy_to_player = enemy.position - player.position
		var squared_distance_to_enemy = (enemy_to_player).length_squared()

		if squared_distance_to_enemy < CROSSFIRE_ENEMY_RANGE_SQ and not enemy.is_loot:
			close_enemy_positions.push_back(enemy.position)

		if squared_distance_to_enemy < ENCIRCLE_RADIUS * ENCIRCLE_RADIUS:
			threat_angles.push_back(enemy_to_player.angle())
			# Fly-likes commit to a frozen point near us; count where they're GOING too
			var mb = enemy._current_movement_behavior
			if mb is TargetRandPosAroundPlayerMovementBehavior and mb._current_target != Vector2.ZERO:
				var dest_off = mb._current_target - player.position
				if dest_off.length_squared() < ENCIRCLE_RADIUS * ENCIRCLE_RADIUS:
					threat_angles.push_back(dest_off.angle())

		var to_add = enemy_to_player.normalized() / max(squared_distance_to_enemy, 1.0)

		if squared_distance_to_enemy < preferred_distance_squared:
			shooting_anyone = true

		if not corridor.empty():
			pass # dodge owns this enemy's vector for the frame (see above)
		elif squared_distance_to_enemy < kite_distance_squared:
			to_add = to_add * -1 * repel_caution * KITE_REPEL_MULT
			# Point-blank contact outranks loot attraction and swarm noise.
			# Idle chargers get a wider bubble: staying at knife range of a
			# bruiser feeds a dash cascade — one hit guts move speed and the
			# next 1 s-cooldown dash lands unavoidably
			var panic_radius = ENEMY_PANIC_RADIUS
			if enemy._current_attack_behavior is ChargingAttackBehavior:
				panic_radius = CHARGER_PANIC_RADIUS
				if squared_distance_to_enemy < nearest_charger_sq:
					nearest_charger_sq = squared_distance_to_enemy
					nearest_charger_pos = enemy.position
			if cautious:
				panic_radius *= CAUTION_PANIC_MULT
			if squared_distance_to_enemy < panic_radius * panic_radius:
				var panic = min((panic_radius * panic_radius) / max(squared_distance_to_enemy, 1.0), ENEMY_PANIC_RAMP_MAX)
				to_add = to_add * panic
			move_vector = move_vector + to_add
		else:
			# Attraction-only bonuses; never boost repulsion from harmless targets
			if enemy.is_loot:
				to_add = to_add * LOOT_CHASE_MULT
			elif enemy._attack_behavior is SpawningAttackBehavior:
				to_add = to_add * egg_weight_squared
			attract_vec = attract_vec + to_add

		if squared_distance_to_enemy < (preferred_distance_squared / 4):
			must_run_away = true

	# Elites and bosses: kite at range, never body-clip
	var boss_weight_squared = boss_weight * boss_weight
	for boss in _entity_spawner.bosses:
		if boss.dead or boss._pending_die:
			continue

		var boss_to_player = boss.position - player.position
		var squared_distance_to_boss = (boss_to_player).length_squared()
		if squared_distance_to_boss < ENCIRCLE_RADIUS * ENCIRCLE_RADIUS:
			threat_angles.push_back(boss_to_player.angle())

		var boss_corridor = _get_charge_corridor(boss, player.position)
		if not boss_corridor.empty():
			must_run_away = true
			charge_corridors.push_back(boss_corridor)
			# The dodge owns the vector while the dash is live — the radial
			# danger repulsion below would rotate our escape down the corridor
			continue

		var body_radius = _get_body_radius(boss)
		# Falloff measures the gap to the body, not to its center
		var gap_sq = max(squared_distance_to_boss - body_radius * body_radius, 1.0)

		# Wall+enemy-aware flee heading, shared by kite AND danger repulsion:
		# pure radial kiting once marched the bot into a corner over 9 s while
		# the elite was still comfortably outside its danger zone
		var flee_dir = boss_to_player.normalized() * -1
		if _wall_room(player.position + flee_dir * BOSS_FLEE_PROBE, far_corner) < BOSS_FLEE_ROOM_MIN:
			# Corner recovery: a walking elite sits at our kite equilibrium, so
			# radial retreat NEVER gains ground — and a ±45° deflection cannot
			# exit a true corner (mantis death at (127,1409): both 45° options
			# still pointed at walls). Widen the cone to pure tangent (±90°,
			# perimeter orbit) and take whichever heading has the most room
			var t_dir = flee_dir.tangent()
			var best_flee = flee_dir
			var best_flee_score = - 1e9
			# Every candidate keeps a radial-out share: pure tangents orbit at
			# CONSTANT radius, and a chasing elite closes the gap under them
			# (mantis held at 141-279 px for 5 s, then dashed from 181)
			for cand in [(flee_dir + t_dir).normalized(), (flee_dir - t_dir).normalized(),
					(flee_dir * 0.45 + t_dir).normalized(), (flee_dir * 0.45 - t_dir).normalized()]:
				var fc_probe = player.position + cand * BOSS_FLEE_PROBE
				var fc_score = min(_wall_room(fc_probe, far_corner), DODGE_WALL_ROOM_CAP) \
						+ _enemy_room(fc_probe, close_enemy_positions)
				if fc_score > best_flee_score:
					best_flee_score = fc_score
					best_flee = cand
			flee_dir = best_flee

		var to_add = (boss_to_player.normalized() / gap_sq) * boss_weight_squared

		# How scary is touching this thing right now
		var damage_caution = clamp(1.0 + 2.0 * boss.current_stats.damage / max(current_health, 1.0), 1.0, DAMAGE_CAUTION_MAX)

		if squared_distance_to_boss < preferred_distance_squared:
			shooting_anyone = true
		if squared_distance_to_boss < kite_distance_squared:
			to_add = flee_dir * (boss_weight_squared / gap_sq) * ELITE_REPEL_MULT * damage_caution

		var danger_radius = body_radius + ELITE_DANGER_BASE + ELITE_DANGER_HP_BONUS * (1.0 - hp_fraction)
		# Chain dashers (croc: 0.25 s cooldown) re-aim at our NEW position every
		# cycle — dodging in place just feeds the next dash. Outside their launch
		# range they never fire, so that IS the danger zone. Only reachable on
		# idle frames (the corridor continue above), which is exactly when
		# there's a window to retreat
		var ab = boss._current_attack_behavior
		if ab is ChargingAttackBehavior and ab.cooldown < CHAIN_DASH_COOLDOWN:
			danger_radius = max(danger_radius, ab.max_range * CHAIN_DASH_RANGE_MARGIN)
		elif ab is ChargingAttackBehavior:
			# Slow-cycling dashers can't be outranged (mantis launches from
			# 2000 px) — but the gap must buy the corridor dodge a window
			danger_radius = max(danger_radius, BOSS_DASH_STANDOFF)
		var danger_sq = danger_radius * danger_radius
		if squared_distance_to_boss < danger_sq:
			must_run_away = true
			var ramp = min(danger_sq / max(squared_distance_to_boss, 1.0), DANGER_RAMP_MAX)
			# Force repulsion even when attraction won above (melee / full-HP Bull case)
			to_add = flee_dir * (boss_weight_squared / gap_sq) * ELITE_REPEL_MULT * damage_caution * ramp

		if squared_distance_to_boss < kite_distance_squared or squared_distance_to_boss < danger_sq:
			move_vector = move_vector + to_add
		else:
			attract_vec = attract_vec + to_add

	# While a dash corridor is live, loot/food pull must not rotate the dodge —
	# the final vector is normalized, so a small rotation is how a corridor clips
	# us (wave-end loot vacuum + charging boss). Note a charging boss never sets
	# shooting_anyone (its loop continues before the range check), so this needs
	# its own corridor test. Otherwise: when something is already in weapon
	# range, stop chasing — attraction to gold/food/distant enemies must not
	# drag us through the nearby ones
	if not charge_corridors.empty():
		attract_vec = attract_vec * CHARGE_ATTRACT_DAMP
	elif shooting_anyone:
		attract_vec = attract_vec * IN_RANGE_ATTRACT_DAMP
	if now_ms < _caution_until_ms:
		# Burst-only: standing low-HP caution must NOT damp attraction —
		# that starves consumable (healing) pickup exactly when it matters
		# (v6: 2/10 with the damp tied to the low-HP flag, vs 6/10 without)
		attract_vec = attract_vec * CAUTION_ATTRACT_DAMP
	move_vector = move_vector + attract_vec


	var map_corners = [Vector2(0,0), Vector2(0, far_corner.y), Vector2(far_corner.x, 0), Vector2(far_corner.x, far_corner.y)]
	var corner_distance = 300
	var square_corner_distance = corner_distance * corner_distance

	for corner in map_corners:
		var corner_to_player = corner - player.position
		var squared_distance_to_corner = corner_to_player.length_squared()

		var to_add = (corner_to_player.normalized() / squared_distance_to_corner) * -2
		if squared_distance_to_corner > square_corner_distance:
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add

	var bumper_x = 0
	var square_bumper_distance = bumper_distance * bumper_distance

	while bumper_x < far_corner.x:
		var bumper_position = Vector2(bumper_x, 0)

		var squared_distance = (bumper_position - player.position).length_squared()

		var to_add = (Vector2(-1,1).normalized() / squared_distance) * bumper_weight
		if squared_distance > square_bumper_distance:
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add

		bumper_x = bumper_x + bumper_spacing

	bumper_x = 0
	while bumper_x < far_corner.x:
		var bumper_position = Vector2(bumper_x, far_corner.y)

		var squared_distance = (bumper_position - player.position).length_squared()

		var to_add = (Vector2(1,-1).normalized() / squared_distance) * bumper_weight
		if squared_distance > square_bumper_distance:
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add

		bumper_x = bumper_x + bumper_spacing

	var bumper_y = 0
	while bumper_y < far_corner.y:
		var bumper_position = Vector2(0, bumper_y)

		var squared_distance = (bumper_position - player.position).length_squared()

		var to_add = (Vector2(1,1).normalized() / squared_distance) * bumper_weight
		if squared_distance > square_bumper_distance:
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add

		bumper_y = bumper_y + bumper_spacing

	bumper_y = 0
	while bumper_y < far_corner.y:
		var bumper_position = Vector2(far_corner.x, bumper_y)

		var squared_distance = (bumper_position - player.position).length_squared()

		var to_add = (Vector2(-1,-1).normalized() / squared_distance) * bumper_weight
		if squared_distance > square_bumper_distance:
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add

		bumper_y = bumper_y + bumper_spacing

	# Hard edge guard: never let swarm pressure pin us against a wall
	var edge_push = Vector2.ZERO
	if player.position.x < EDGE_GUARD_DISTANCE:
		edge_push.x += 1.0 - player.position.x / EDGE_GUARD_DISTANCE
	if far_corner.x - player.position.x < EDGE_GUARD_DISTANCE:
		edge_push.x -= 1.0 - (far_corner.x - player.position.x) / EDGE_GUARD_DISTANCE
	if player.position.y < EDGE_GUARD_DISTANCE:
		edge_push.y += 1.0 - player.position.y / EDGE_GUARD_DISTANCE
	if far_corner.y - player.position.y < EDGE_GUARD_DISTANCE:
		edge_push.y -= 1.0 - (far_corner.y - player.position.y) / EDGE_GUARD_DISTANCE
	move_vector = move_vector + edge_push * EDGE_GUARD_STRENGTH

	# Dash-cascade breaker: freshly hit (cautious) with a charger at knife
	# range and no dash in flight — its cooldown window is free movement;
	# sprint the gap open so the re-launch comes from dodgeable range
	if cautious and charge_corridors.empty() and nearest_charger_sq < CASCADE_FLEE_RADIUS_SQ:
		move_vector = move_vector + (player.position - nearest_charger_pos).normalized() * CASCADE_FLEE_STRENGTH

	# Charge dodging: a single corridor gets the perpendicular sidestep; crossing
	# corridors get a max-min exit (dodging one dash must not step into another).
	# Both scale with repel_caution: at low HP any clip is lethal while loot pull
	# is at its strongest, so the dodge must own a bigger share of the vector
	crossfiring = false
	dodging = false
	last_corridor_count = charge_corridors.size()
	# A single NON-boss corridor with bullets airborne goes to the 16-dir
	# scored exit below: the two-lateral fast path cannot represent "both
	# sides are covered by spitter lanes" (w8-gangster: deflecting off one
	# rear lane aligned the escape with ANOTHER — dot=1.00 impacts persisted).
	# Boss corridors keep the tuned pure-lateral dodge (croc / loud-w11)
	if charge_corridors.size() == 1 and (charge_corridors[0][6] or proj_lanes.size() < 2):
		dodging = true
		var c = charge_corridors[0]
		var c_dir = c[1]
		var c_tangent = c_dir.tangent()
		var side = 1.0 if c[3] >= 0.0 else - 1.0
		# Side choice weighs enemies too: a wall-clear sidestep once carried the
		# bot from 456 px of open space straight into a blob at 36 px
		var here_pos = player.position + c_tangent * side * 300.0
		var there_pos = player.position - c_tangent * side * 300.0
		# Lane term: this side pick was bullet-blind while crossfire/sidestep
		# weren't — w8-gangster deaths were spitter shots (600 px/s) running
		# the bot down COLLINEAR with its own dodge escape (PHIT dot +0.90..0.98
		# with esc=16). The dodge must not flee along an aimed line of fire
		var score_here = min(_wall_room(here_pos, far_corner), DODGE_WALL_ROOM_CAP) \
				+ _enemy_room(here_pos, close_enemy_positions) \
				- PROJ_FIELD_WEIGHT_SIDE * _proj_lane_penalty(here_pos, proj_lanes)
		var score_there = min(_wall_room(there_pos, far_corner), DODGE_WALL_ROOM_CAP) \
				+ _enemy_room(there_pos, close_enemy_positions) \
				- PROJ_FIELD_WEIGHT_SIDE * _proj_lane_penalty(there_pos, proj_lanes)
		if score_there > score_here + 50.0:
			side = - side
		var escape
		if c[6]:
			if c[8]:
				# Boss dash in flight: pure lateral — the corridor is wide, the
				# dash is fast, and every pixel of the sideways budget counts
				escape = c_tangent * side
			else:
				# Windup: mostly lateral (~94% tangent share) but also retreat —
				# distance is the only defense against a chain-dasher's re-aim
				var boss_away = (player.position - c[0]).normalized()
				escape = (c_tangent * side + boss_away * WINDUP_RADIAL_BIAS).normalized()
		else:
			var away = (player.position - c[0]).normalized()
			escape = (c_tangent * side + away * CHARGE_RADIAL_BIAS).normalized()
		# Rear-aligned fire: don't flee down a chasing shot's lane — deflect
		# the committed escape laterally off it (away from the lane center)
		for rl in proj_lanes:
			if rl[3] <= player.get_move_speed():
				continue # we outrun this shot
			if (rl[0] - player.position).dot(escape) > 0.0:
				continue # shot is ahead of us, not chasing
			if escape.dot(rl[1]) > REAR_LANE_ALIGN:
				var rl_tangent = rl[1].tangent()
				var rl_sign = 1.0 if (player.position - rl[0]).dot(rl_tangent) >= 0.0 else - 1.0
				escape = (escape + rl_tangent * rl_sign * REAR_LANE_DEFLECT).normalized()
				break
		move_vector = move_vector + escape * CHARGE_DODGE_STRENGTH * (0.5 + c[4]) * c[5] * repel_caution
	elif charge_corridors.size() >= 1:
		crossfiring = true
		var cf_now = OS.get_ticks_msec()
		if cf_now >= _crossfire_until_ms:
			var best_dir = Vector2.ZERO
			var best_clear = - 1e9
			for k in range(16):
				var cand = Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0))
				var future = player.position + cand * 200.0
				# Corridor clearance is life-or-death; cap it so a fully clear
				# direction still lets the swarm/wall terms break the tie
				var min_clear = 400.0
				for c in charge_corridors:
					var rel = future - c[0]
					var f_along = rel.dot(c[1])
					if f_along < - CHARGE_LOOKAHEAD_MARGIN or f_along > c[7]:
						continue # dash never reaches this point; corridor is a segment, not a line
					var clear = abs(rel.dot(c[1].tangent())) - c[2]
					if clear < min_clear:
						min_clear = clear
				# Don't exit a dash straight into the swarm (28 HP lost that way once)
				var enemy_room = 300.0
				for e_pos in close_enemy_positions:
					var e_d = future.distance_to(e_pos)
					if e_d < enemy_room:
						enemy_room = e_d
				# Rear-aligned fire: a candidate that flees along a faster
				# chasing shot's lane is a lost race the lateral probes miss
				var rear_pen = 0.0
				for rl in proj_lanes:
					if rl[3] > player.get_move_speed() and (rl[0] - player.position).dot(cand) < 0.0 \
							and cand.dot(rl[1]) > REAR_LANE_ALIGN:
						rear_pen = max(rear_pen, cand.dot(rl[1]))
				var score = min_clear + enemy_room / 3.0 + _wall_room(future, far_corner) / 6.0 \
						- 100.0 * _proj_lane_penalty(future, proj_lanes) \
						- REAR_LANE_WEIGHT * rear_pen
				# Hysteresis: near-tied exits must not flip-flop every re-pick
				# (two winding bosses once netted 33 px/s of actual movement)
				if cand.dot(_crossfire_dir) > 0.95:
					score += CROSSFIRE_STICK_BONUS
				if score > best_clear:
					best_clear = score
					best_dir = cand
			_crossfire_dir = best_dir
			_crossfire_until_ms = cf_now + int(CROSSFIRE_COMMIT_MS * commit_scale)
		# A boss corridor in the mix: the exit push must not come out WEAKER
		# than the single-boss dodge peak it replaces
		var cf_strength = CROSSFIRE_STRENGTH
		for c in charge_corridors:
			if c[6]:
				cf_strength = CROSSFIRE_STRENGTH * CROSSFIRE_BOSS_MULT
				break
		move_vector = move_vector + _crossfire_dir * cf_strength * repel_caution

	# Incoming-bullet dodge: the per-projectile field terms are 1/d^2 noise that
	# any committed behavior drowns, and straddling shots pick opposite sidestep
	# signs and cancel. Imminent shots get one decisive move instead. Skipped
	# while a dash corridor is live — that dodge is more lethal and must not
	# fight a second committed sidestep
	proj_dodging = false
	if charge_corridors.empty() and proj_corridors.size() == 1 and proj_lanes.size() < PROJ_VOLUME_MIN:
		proj_dodging = true
		var pc = proj_corridors[0]
		var p_tangent = pc[1].tangent()
		var p_side = 1.0 if pc[3] >= 0.0 else - 1.0
		var p_here = player.position + p_tangent * p_side * 200.0
		var p_there = player.position - p_tangent * p_side * 200.0
		# F3: the sidestep must not step out of this lane into another one
		var p_score_here = min(_wall_room(p_here, far_corner), DODGE_WALL_ROOM_CAP) \
				+ _enemy_room(p_here, close_enemy_positions) \
				- PROJ_FIELD_WEIGHT_SIDE * _proj_lane_penalty(p_here, proj_lanes)
		var p_score_there = min(_wall_room(p_there, far_corner), DODGE_WALL_ROOM_CAP) \
				+ _enemy_room(p_there, close_enemy_positions) \
				- PROJ_FIELD_WEIGHT_SIDE * _proj_lane_penalty(p_there, proj_lanes)
		if p_score_there > p_score_here + 50.0:
			p_side = - p_side
		move_vector = move_vector + p_tangent * p_side * PROJ_DODGE_STRENGTH * (0.5 + pc[4]) * repel_caution
	elif charge_corridors.empty() and (proj_corridors.size() >= 2 or proj_lanes.size() >= PROJ_VOLUME_MIN):
		# F3 volume mode: flow through the lowest-density gap in the whole
		# bullet field instead of reacting to aimed shots one at a time
		proj_dodging = true
		var pd_now = OS.get_ticks_msec()
		if pd_now >= _proj_dodge_until_ms:
			var pd_best_dir = Vector2.ZERO
			var pd_best_score = - 1e9
			for k in range(16):
				var cand = Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0))
				var future = player.position + cand * 150.0
				# Imminent corridors stay life-or-death (capped so other terms
				# can break ties); the lane field grades everything else
				var min_clear = 250.0
				for pc in proj_corridors:
					var rel = future - pc[0]
					if rel.dot(pc[1]) < 0.0:
						continue # behind the shot; it flies away from there
					var clear = abs(rel.dot(pc[1].tangent())) - pc[2]
					if clear < min_clear:
						min_clear = clear
				var enemy_room = 300.0
				for e_pos in close_enemy_positions:
					var e_d = future.distance_to(e_pos)
					if e_d < enemy_room:
						enemy_room = e_d
				# NOTE the weak /3 + /6 room weights are load-bearing: raising them
				# to /2 + /3 (to stop pocket-marches like the helmet-alien death,
				# edge 513->206 over 4 s) dropped w4 3/8 -> 1/8 — the exits start
				# fighting the lane field and eat drip hits instead. The pocket
				# failure mode needs the arbiter's unified score, not this knob
				# Collinear motion maximizes exposure in BOTH directions: fleeing
				# along a faster chasing shot is a lost race, and running INTO an
				# oncoming lane closes at bullet+player speed (w4-d6: 9 of 12
				# impact PHITs at |dot| >= 0.74 with THIS exit committed — the
				# static lane penalty loses to room-term deltas at these stakes)
				var col_pen = 0.0
				for rl in proj_lanes:
					var rl_a = cand.dot(rl[1])
					if abs(rl_a) < REAR_LANE_ALIGN:
						continue
					var rl_rel = rl[0] - player.position
					if rl_a > 0.0 and rl_rel.dot(cand) < 0.0 and rl[3] > player.get_move_speed():
						col_pen = max(col_pen, rl_a)   # chased from behind, can't outrun
					elif rl_a < 0.0 and rl_rel.dot(cand) > 0.0:
						col_pen = max(col_pen, - rl_a) # charging head-on into the shot
				var score = min_clear + enemy_room / 3.0 + _wall_room(future, far_corner) / 6.0 \
						- PROJ_FIELD_WEIGHT * _proj_lane_penalty(future, proj_lanes) \
						- REAR_LANE_WEIGHT * col_pen
				if score > pd_best_score:
					pd_best_score = score
					pd_best_dir = cand
			_proj_dodge_dir = pd_best_dir
			_proj_dodge_until_ms = pd_now + int(PROJ_DODGE_COMMIT_MS * commit_scale)
		move_vector = move_vector + _proj_dodge_dir * PROJ_DODGE_STRENGTH * 1.5 * repel_caution

	# Cluster of pillars dropped ON us (mom/butcher): their repulsions cancel at
	# the center — commit to the exit that maximizes distance from all of them
	aoe_fleeing = false
	if aoe_close.size() >= AOE_FLEE_MIN:
		aoe_fleeing = true
		must_run_away = true
		var af_now = OS.get_ticks_msec()
		if af_now >= _aoe_flee_until_ms:
			var af_best_dir = Vector2.ZERO
			var af_best_score = - 1e9
			for k in range(8):
				var cand = Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0))
				var future = player.position + cand * 150.0
				var min_d = 1e9
				for p_pos in aoe_close:
					var d = future.distance_to(p_pos)
					if d < min_d:
						min_d = d
				var score = min_d + _wall_room(future, far_corner) / 6.0
				if score > af_best_score:
					af_best_score = score
					af_best_dir = cand
			_aoe_flee_dir = af_best_dir
			_aoe_flee_until_ms = af_now + int(AOE_FLEE_COMMIT_MS * commit_scale)
		move_vector = move_vector + _aoe_flee_dir * AOE_FLEE_STRENGTH

	# Counter-steer expanding projectile rings: fleeing WITH the wave ends
	# pinned at a wall; crossing upstream ends in the already-swept interior
	countering = false
	if wave_count >= WAVE_MIN_COUNT and wave_vel_sum.length() / wave_count >= WAVE_COHERENCE:
		countering = true
		must_run_away = true
		_counter_dir = - wave_vel_sum.normalized()
		move_vector = move_vector + _counter_dir * WAVE_COUNTER_STRENGTH

	# Gap-seeking escape: when threats close a ring around us their repulsion
	# vectors cancel and the field goes blind — find the widest angular gap
	# (wall-aware) and commit through it
	escaping = false
	var real_threats = threat_angles.size()
	if real_threats >= 3:
		# Walls occupy angular coverage too: a half-ring against a wall is a full trap
		if player.position.x < ENCIRCLE_RADIUS:
			_push_wall_angles(threat_angles, PI)
		if far_corner.x - player.position.x < ENCIRCLE_RADIUS:
			_push_wall_angles(threat_angles, 0.0)
		if player.position.y < ENCIRCLE_RADIUS:
			_push_wall_angles(threat_angles, - PI * 0.5)
		if far_corner.y - player.position.y < ENCIRCLE_RADIUS:
			_push_wall_angles(threat_angles, PI * 0.5)
	if real_threats >= 3 and threat_angles.size() >= ENCIRCLE_MIN_THREATS:
		# Prefer escaping opposite the threat mass (virtual wall angles excluded)
		var threat_dir_sum = Vector2.ZERO
		for i in range(real_threats):
			threat_dir_sum = threat_dir_sum + Vector2(cos(threat_angles[i]), sin(threat_angles[i]))
		var away = Vector2.ZERO
		if threat_dir_sum.length() > 0.1:
			away = - threat_dir_sum.normalized()
		threat_angles.sort()
		var n = threat_angles.size()
		var largest_gap = 0.0
		var best_score = - 1e9
		var best_angle = 0.0
		for i in range(n):
			var a1 = threat_angles[i]
			var a2 = threat_angles[(i + 1) % n]
			if i == n - 1:
				a2 += TAU
			var gap = a2 - a1
			if gap > largest_gap:
				largest_gap = gap
			var mid = a1 + gap * 0.5
			var mid_dir = Vector2(cos(mid), sin(mid))
			var probe = player.position + mid_dir * 300.0
			var score = rad2deg(gap) + _wall_room(probe, far_corner) / 4.0 + 45.0 * mid_dir.dot(away) \
					- 40.0 * _proj_lane_penalty(probe, proj_lanes)
			if score > best_score:
				best_score = score
				best_angle = mid
		if rad2deg(largest_gap) <= 360.0 - ENCIRCLE_COVERAGE_DEG:
			escaping = true
			must_run_away = true
			var now = OS.get_ticks_msec()
			if now >= _escape_until_ms:
				_escape_dir = Vector2(cos(best_angle), sin(best_angle))
				_escape_until_ms = now + int(ESCAPE_COMMIT_MS * commit_scale)
			move_vector = move_vector + _escape_dir * ESCAPE_STRENGTH

	# Never press INTO a nearby wall — keep only the along-wall component, so
	# boss/swarm repulsion turns into orbiting along the wall instead of pinning
	if player.position.x < WALL_SLIDE_DISTANCE and move_vector.x < 0.0:
		move_vector.x = 0.0
	if far_corner.x - player.position.x < WALL_SLIDE_DISTANCE and move_vector.x > 0.0:
		move_vector.x = 0.0
	if player.position.y < WALL_SLIDE_DISTANCE and move_vector.y < 0.0:
		move_vector.y = 0.0
	if far_corner.y - player.position.y < WALL_SLIDE_DISTANCE and move_vector.y > 0.0:
		move_vector.y = 0.0

	# F6b lane slide: bullets are not transparent — after all forces resolve,
	# shed any movement component that CLOSES the lateral gap to a tracked
	# shot's swept lane (the wall-slide idea applied to bullets: the dodge
	# scorers suggest, this vetoes). Guards learned from the A/B campaign:
	# never active while a charge dodge owns the vector, and keep a squeeze
	# vector when lanes fence us in completely
	if charge_corridors.empty():
		var pre_lane = move_vector
		var worst_exit = Vector2.ZERO
		var worst_closeness = 0.0
		for lane in proj_lanes:
			var l_rel = player.position - lane[0]
			var l_along = l_rel.dot(lane[1])
			var l_reach = max(lane[3] * PROJ_IMMINENT_TTI, PROJ_IMMINENT_MIN_DIST)
			if l_along < - 20.0 or l_along > l_reach:
				continue # already passed us, or too far upstream to arrive in time
			var t_dir = lane[1].tangent()
			var l_lat = l_rel.dot(t_dir)
			var influence = (lane[2] + PROJ_SLIDE_BODY) * PROJ_SLIDE_INFLUENCE
			if abs(l_lat) > influence or abs(l_lat) < 8.0:
				continue # clear of the lane, or dead-center (the dodges own the exit)
			var closeness = 1.0 - abs(l_lat) / influence
			if closeness > worst_closeness:
				worst_closeness = closeness
				worst_exit = t_dir * sign(l_lat) # away from this lane's center
			var to_center = t_dir * - sign(l_lat)
			var closing = move_vector.dot(to_center)
			if closing <= 0.0:
				continue
			move_vector = move_vector - to_center * closing * closeness
		if move_vector.length() < pre_lane.length() * 0.3 and worst_exit != Vector2.ZERO:
			# A near-perpendicular approach sheds almost everything — that is
			# NOT "fenced in", it is one lane in the way. Exit sideways at
			# full speed instead of restoring the plow-through vector.
			# Wall-aware: the pure lane-geometry sign can point INTO a wall
			# (bot pinned at edge=120 while dodging under swarm pressure) —
			# take the opposite tangent when it has clearly more room, even
			# though that means crossing the worst lane once
			# Crossing the worst lane is only worth it when the lane-preferred
			# side is genuinely wall-starved — an open-field flip trades a
			# known-clear exit for a lane crossing and buys nothing (w4 0/5)
			var exit_room = _wall_room(player.position + worst_exit * 200.0, far_corner)
			var flip_room = _wall_room(player.position - worst_exit * 200.0, far_corner)
			if exit_room < 200.0 and flip_room > exit_room + 80.0:
				worst_exit = - worst_exit
			move_vector = worst_exit * pre_lane.length()

	if (shooting_anyone and not must_run_away) and is_soldier:
		last_move_dir = Vector2.ZERO
		return Vector2.ZERO

	last_move_dir = move_vector.normalized()
	return last_move_dir


func _arbiter_move(player)->Vector2:
	if _arbiter == null:
		_arbiter = Arbiter.new()
		_world = WorldView.new()
		# Both halves read the same --arb-* dict; each picks out the keys it
		# owns and ignores the rest, so a sweep passes one flag set regardless
		# of which side the knob lives on.
		var overrides = $"/root/AutobattlerOptions".arb_overrides
		_arbiter.apply_overrides(overrides)
		_world.apply_overrides(overrides)
		arb_every = int(overrides.get("every", 1))
	_arb_tick += 1
	var every = arb_every
	if every <= 0:
		every = 2 if last_arb_us > ARB_BUDGET_US else 1
	if not _arb_decided or _arb_tick % every == 0:
		_arbiter.tick_step = every
		var t0 = OS.get_ticks_usec()
		_world.gather($"/root/Main", player)
		last_move_dir = _arbiter.choose(player.position, player.get_move_speed(),
				_world.body_radius, _world.far_corner,
				_world.threats, _world.rewards, _world.targets, _world.chargers,
				_world.weapon_range, _world.prefers_still, _world.current_hp,
				_world.mitigation, _world.profile)
		last_arb_us = OS.get_ticks_usec() - t0
		_arb_decided = true
		var still_cost = -1.0
		if _arbiter.last_scores.size() > 24:
			still_cost = _arbiter.last_scores[24]
		var bearing = -999
		if last_move_dir != Vector2.ZERO:
			bearing = int(rad2deg(last_move_dir.angle()))
		decision_hist.push_back([OS.get_ticks_msec(), int(player.position.x), int(player.position.y),
				bearing, int(_arbiter.last_scores[_arbiter.last_best_index]), int(still_cost),
				_arbiter.last_aoe_n, 1 if _arbiter.last_hop else 0])
		if decision_hist.size() > HIST_LEN:
			decision_hist.pop_front()

	# -- Tap-move interleave (fire_still characters) --
	# The game fires every cooldown-ready weapon on the FIRST frame movement
	# input is exactly zero (weapon.gd should_shoot: _current_movement ==
	# Vector2.ZERO), and the +50%/+50% standing stats apply that same frame
	# (player.gd check_not_moving_stats has no delay -- only Streamer's
	# material tick uses the timer). Movement is instant-velocity, so a stop
	# costs nothing but the frames spent stopped. That makes "attack while
	# moving" nearly real: move TAP_MOVE frames, stop TAP_STOP frames, and the
	# potato travels at ~2/3 speed while volleying at full standing bonuses.
	# Gated on the arbiter's STUTTER gap -- the chosen heading re-scored at the
	# tap cycle's net speed, minus its full-speed score. That is the true
	# price of firing while running, and it is small far more often than the
	# old stand-gap admitted: fleeing a swarm 300 px out costs almost nothing
	# to stutter through, so the bot fires the whole way; a pursuer about to
	# connect prices the slowdown as lethal, so that stretch runs at full
	# speed. Pin escape stays full speed unconditionally: a corner exit is
	# the one flight where every frame of travel is the point.
	# The same duty cycle executes the arbiter's HOP candidates (half-speed
	# steps inside a telegraph ring, see arbiter HOP_FRAC) for every row.
	if TAP_STOP > 0 and last_move_dir != Vector2.ZERO \
			and not _arbiter.last_escaping \
			and (_arbiter.last_hop \
				or (_world.profile.get("fire_still", false) \
					and _arbiter.last_stutter_gap < TAP_SAFE_GAP)):
		_tap_phase = (_tap_phase + 1) % (TAP_MOVE + TAP_STOP)
		if _tap_phase < TAP_STOP:
			return Vector2.ZERO    # let the volley off; heading stats keep the tap
	else:
		_tap_phase = TAP_STOP    # re-enter cycles on the moving side

	if last_move_dir == Vector2.ZERO:
		_hdg_still += 1
		_hdg_run += 1
		if _hdg_run == 60:
			_hdg_ticks += 1          # a full unbroken second stood (Streamer tick)
		elif _hdg_run > 60 and _hdg_run % 60 == 0:
			_hdg_ticks += 1
	else:
		if _hdg_run > 0:
			_hdg_breaks += 1         # a stand was broken
		_hdg_run = 0
		_hdg_sum = _hdg_sum + last_move_dir
		_hdg_count += 1
		if _hdg_prev != Vector2.ZERO:
			_hdg_turn_sum += rad2deg(acos(clamp(last_move_dir.dot(_hdg_prev), -1.0, 1.0)))
			if last_move_dir.dot(_hdg_prev) < 0.0:
				_hdg_flips += 1
		_hdg_prev = last_move_dir

	return last_move_dir


# Returns [path_efficiency, mean_turn_deg, reversals, moving_frames, still_frames]
# and resets the window.
func take_heading_stats()->Array:
	var coh = 0.0
	var turn = 0.0
	if _hdg_count > 0:
		coh = _hdg_sum.length() / _hdg_count
		turn = _hdg_turn_sum / max(_hdg_count - 1, 1)
	var out = [coh, turn, _hdg_flips, _hdg_count, _hdg_still, _hdg_ticks, _hdg_breaks]
	_hdg_ticks = 0
	_hdg_breaks = 0
	_hdg_sum = Vector2.ZERO
	_hdg_count = 0
	_hdg_turn_sum = 0.0
	_hdg_flips = 0
	_hdg_still = 0
	_hdg_prev = Vector2.ZERO
	return out


func _wall_room(pos:Vector2, far:Vector2)->float:
	return min(min(pos.x, far.x - pos.x), min(pos.y, far.y - pos.y))


func _enemy_room(point:Vector2, enemy_positions:Array)->float:
	var best = DODGE_ENEMY_ROOM_CAP
	for e_pos in enemy_positions:
		var d = point.distance_to(e_pos)
		if d < best:
			best = d
	return best


func _proj_half_width(projectile)->float:
	var shape = projectile._hitbox._collision.shape
	var extra = 0.0
	if shape is CircleShape2D:
		extra = shape.radius
	elif shape is RectangleShape2D:
		extra = max(shape.extents.x, shape.extents.y)
	return extra + PROJ_CORRIDOR_MARGIN


# How many imminent shot corridors cover this point — committed escapes must
# not route through a line of fire
func _proj_blocked_count(point:Vector2, proj_corridors:Array)->int:
	var n = 0
	for pc in proj_corridors:
		var rel = point - pc[0]
		if rel.dot(pc[1]) < 0.0:
			continue
		if abs(rel.dot(pc[1].tangent())) < pc[2]:
			n += 1
	return n


# F3: continuous, TTI-weighted replacement for _proj_blocked_count — every
# airborne shot contributes by how squarely and how soon it sweeps the point.
# ~1.0 for one dead-center imminent lane; near-misses and later arrivals
# contribute fractions, so candidate scoring grades the whole bullet field
func _proj_lane_penalty(point:Vector2, proj_lanes:Array)->float:
	var total = 0.0
	for lane in proj_lanes:
		var rel = point - lane[0]
		var along = rel.dot(lane[1])
		if along < 0.0:
			continue # behind the shot; it flies away from there
		# F6: effective reach floors at PROJ_LANE_MIN_REACH so slow streams
		# still grade the field instead of decaying to noise
		var reach = max(lane[3] * PROJ_LANE_REACH_T, PROJ_LANE_MIN_REACH)
		if along > reach:
			continue
		var reach_t = along / reach * PROJ_LANE_REACH_T
		var margin = lane[2] * PROJ_LANE_MARGIN
		var lat = abs(rel.dot(lane[1].tangent()))
		if lat < margin:
			total += (1.0 - lat / margin) * (1.0 - reach_t / PROJ_LANE_REACH_T)
	return total


func _push_wall_angles(angles:Array, wall_angle:float)->void :
	angles.push_back(wall_angle)
	angles.push_back(wall_angle + 0.7)
	angles.push_back(wall_angle - 0.7)


func _get_body_radius(unit)->float:
	if unit._hurtbox and unit._hurtbox._collision:
		var shape = unit._hurtbox._collision.shape
		if shape is CircleShape2D:
			return shape.radius
	return BODY_RADIUS_FALLBACK


# Detects an active charge corridor threatening the player, during both the
# wind-up telegraph and the dash itself. Returns [] when safe, else
# [origin, dir, half_width, lateral, urgency, strength_mult, is_boss, length, in_flight].
# Callers must skip dead units first (death also clears _can_move).
func _get_charge_corridor(enemy, player_position:Vector2)->Array:
	var behavior = enemy._current_attack_behavior
	if not (behavior is ChargingAttackBehavior):
		return []

	var in_flight = enemy._move_locked
	var winding_up = (not enemy._can_move) and (not in_flight)
	if not (winding_up or in_flight):
		return []
	# During wind-up the direction is only known if computed at START_SHOOT
	if winding_up and behavior.target_calculation_timing != ChargingAttackBehavior.Timing.START_SHOOT:
		return []

	var charge_dir = behavior._charge_direction
	if charge_dir.length_squared() < 1.0:
		return []

	var dir = charge_dir.normalized()
	var to_player = player_position - enemy.position
	var along = to_player.dot(dir)

	# _charge_direction is a target offset; the dash actually travels speed * duration
	var dash_reach = (enemy.current_stats.speed + behavior.charge_speed) * behavior.charge_duration
	var corridor_length = max(charge_dir.length(), dash_reach) + CHARGE_LOOKAHEAD_MARGIN
	if along < - CHARGE_LOOKAHEAD_MARGIN or along > corridor_length:
		return []

	var lateral = to_player.dot(dir.tangent())
	var half_width = CHARGE_CORRIDOR_HALF_WIDTH + _get_body_radius(enemy)
	if abs(lateral) > half_width:
		return []

	var urgency = 1.0 - abs(lateral) / half_width
	var proximity = clamp(CHARGE_DODGE_NEAR / max(along, 100.0), 0.5, 2.0)
	var strength_mult = proximity
	var is_boss = enemy is Boss
	if is_boss:
		strength_mult *= CHARGE_BOSS_DODGE_MULT
	elif in_flight:
		strength_mult *= CHARGE_INFLIGHT_MULT
	return [enemy.position, dir, half_width, lateral, urgency, strength_mult, is_boss, corridor_length, in_flight]


func _get_projectile_term(projectile, player_position:Vector2, weight:float)->Vector2:
	var to_player = player_position - projectile.position
	var d_sq = to_player.length_squared()
	if d_sq > PROJECTILE_RANGE_SQ:
		return Vector2.ZERO

	var shape = projectile._hitbox._collision.shape
	var extra_range = 0.0
	if shape is CircleShape2D:
		extra_range = shape.radius
	elif shape is RectangleShape2D:
		extra_range = max(shape.extents.x, shape.extents.y)
	var gap_sq = max(d_sq - extra_range * extra_range, .001)

	if projectile.velocity.length_squared() < STATIONARY_SPEED_SQ:
		# Ground AoE (pillar): only dangerous during telegraph + armed window
		var anim = projectile._animation_player
		if projectile._hitbox.is_disabled() and anim.is_playing() and anim.current_animation_position > AOE_HARMLESS_ANIM_POS:
			return Vector2.ZERO # already detonated; stop fleeing spent pillars
		# Slash arcs (slasher/butcher) park a tiny 16x9 collision 112 px OFF the
		# projectile origin and sweep it when armed — the reachable footprint is
		# offset + extents, not the rest-pose rect. Pillars are centered (+0)
		var reach = extra_range + projectile._hitbox._collision.position.length()
		var avoid_radius = min(reach * AOE_AVOID_RADIUS_MULT + PROJ_CORRIDOR_MARGIN, AOE_AVOID_RADIUS_MAX)
		if d_sq > avoid_radius * avoid_radius:
			return Vector2.ZERO
		# A pillar footprint is a hard no-go zone: must outrank kite/boss pressure
		var aoe_ramp = min((avoid_radius * avoid_radius) / gap_sq, AOE_PANIC_RAMP_MAX)
		return to_player.normalized() * weight * aoe_ramp / gap_sq

	if d_sq > PROJ_CLOSE_ALWAYS_SQ:
		var dir = projectile.velocity.normalized()
		if to_player.dot(dir) < 0.0:
			return Vector2.ZERO # moving away; cannot hit us
		var lateral = to_player.dot(dir.tangent())
		if abs(lateral) > extra_range + PROJ_CORRIDOR_MARGIN:
			# Passes to the side: weak radial pressure away from the barrage zone
			return to_player.normalized() * weight * 0.3 / gap_sq
		# Sidestep out of the line of fire instead of outrunning it
		var side = 1.0 if lateral >= 0.0 else - 1.0
		return dir.tangent() * side * weight / gap_sq

	# Point-blank: radial panic, ramped like every other close threat
	var close_ramp = min(PROJ_CLOSE_ALWAYS_SQ / gap_sq, PROJ_PANIC_RAMP_MAX)
	return to_player.normalized() * weight * close_ramp / gap_sq
