extends "res://entities/units/movement_behaviors/player_movement_behavior.gd"

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
const BOSS_FLEE_PROBE = 300.0            # look this far along the flee heading for wall room
const BOSS_FLEE_ROOM_MIN = 260.0         # less room than this ahead: orbit instead of backing into the corner
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
const IN_RANGE_ATTRACT_DAMP = 0.35       # damp gold/food/distant-enemy pull while already in weapon range
const ENEMY_PANIC_RADIUS = 120.0         # inside this, contact repulsion ramps ~1/d^4
const ENEMY_PANIC_RAMP_MAX = 6.0         # cap on that ramp
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
const PROJ_CORRIDOR_MARGIN = 60.0        # player half-size + margin for line-of-fire test
const PROJ_IMMINENT_TTI = 0.7            # seconds to impact that makes a shot "imminent"
const PROJ_DODGE_STRENGTH = 0.025        # beats swarm/attraction noise, stays under gap escape
const PROJ_DODGE_COMMIT_MS = 250         # hold the multi-shot exit briefly
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
	for projectile in projectiles_container.get_children():
		if not (projectile is Projectile):
			continue # BulletHell wave containers live here too
		if not projectile._hitbox or not projectile._hitbox.active:
			continue
		var to_add = _get_projectile_term(projectile, player.position, projectile_weight_squared)
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add
		var proj_off = projectile.position - player.position
		var proj_speed_sq = projectile.velocity.length_squared()
		if proj_speed_sq >= STATIONARY_SPEED_SQ:
			# Line-of-fire + time-to-impact: only imminent shots earn a real dodge
			var p_speed = sqrt(proj_speed_sq)
			var p_dir = projectile.velocity / p_speed
			var p_along = (-proj_off).dot(p_dir)
			if p_along > 0.0 and p_along / p_speed < PROJ_IMMINENT_TTI:
				var p_lateral = (-proj_off).dot(p_dir.tangent())
				var p_half = _proj_half_width(projectile)
				if abs(p_lateral) < p_half:
					proj_corridors.push_back([projectile.position, p_dir, p_half, p_lateral,
							1.0 - (p_along / p_speed) / PROJ_IMMINENT_TTI])
		if proj_speed_sq < STATIONARY_SPEED_SQ:
			var spent = projectile._hitbox.is_disabled() and projectile._animation_player.is_playing() \
					and projectile._animation_player.current_animation_position > AOE_HARMLESS_ANIM_POS
			if not spent and proj_off.length_squared() < ENCIRCLE_AOE_RADIUS * ENCIRCLE_AOE_RADIUS:
				threat_angles.push_back(proj_off.angle())
				aoe_close.push_back(projectile.position)
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
			to_add = to_add * -1 * repel_caution
			# Point-blank contact outranks loot attraction and swarm noise.
			# Idle chargers get a wider bubble: staying at knife range of a
			# bruiser feeds a dash cascade — one hit guts move speed and the
			# next 1 s-cooldown dash lands unavoidably
			var panic_radius = ENEMY_PANIC_RADIUS
			if enemy._current_attack_behavior is ChargingAttackBehavior:
				panic_radius = CHARGER_PANIC_RADIUS
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
			var t_dir = flee_dir.tangent()
			var left_probe = player.position + (flee_dir + t_dir).normalized() * BOSS_FLEE_PROBE
			var right_probe = player.position + (flee_dir - t_dir).normalized() * BOSS_FLEE_PROBE
			var left_score = min(_wall_room(left_probe, far_corner), DODGE_WALL_ROOM_CAP) \
					+ _enemy_room(left_probe, close_enemy_positions)
			var right_score = min(_wall_room(right_probe, far_corner), DODGE_WALL_ROOM_CAP) \
					+ _enemy_room(right_probe, close_enemy_positions)
			if left_score > right_score:
				flee_dir = (flee_dir + t_dir).normalized()
			else:
				flee_dir = (flee_dir - t_dir).normalized()

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

	# Charge dodging: a single corridor gets the perpendicular sidestep; crossing
	# corridors get a max-min exit (dodging one dash must not step into another).
	# Both scale with repel_caution: at low HP any clip is lethal while loot pull
	# is at its strongest, so the dodge must own a bigger share of the vector
	crossfiring = false
	dodging = false
	last_corridor_count = charge_corridors.size()
	if charge_corridors.size() == 1:
		dodging = true
		var c = charge_corridors[0]
		var c_dir = c[1]
		var c_tangent = c_dir.tangent()
		var side = 1.0 if c[3] >= 0.0 else - 1.0
		# Side choice weighs enemies too: a wall-clear sidestep once carried the
		# bot from 456 px of open space straight into a blob at 36 px
		var here_pos = player.position + c_tangent * side * 300.0
		var there_pos = player.position - c_tangent * side * 300.0
		var score_here = min(_wall_room(here_pos, far_corner), DODGE_WALL_ROOM_CAP) \
				+ _enemy_room(here_pos, close_enemy_positions)
		var score_there = min(_wall_room(there_pos, far_corner), DODGE_WALL_ROOM_CAP) \
				+ _enemy_room(there_pos, close_enemy_positions)
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
		move_vector = move_vector + escape * CHARGE_DODGE_STRENGTH * (0.5 + c[4]) * c[5] * repel_caution
	elif charge_corridors.size() >= 2:
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
				var score = min_clear + enemy_room / 3.0 + _wall_room(future, far_corner) / 6.0 \
						- 100.0 * _proj_blocked_count(future, proj_corridors)
				# Hysteresis: near-tied exits must not flip-flop every re-pick
				# (two winding bosses once netted 33 px/s of actual movement)
				if cand.dot(_crossfire_dir) > 0.95:
					score += CROSSFIRE_STICK_BONUS
				if score > best_clear:
					best_clear = score
					best_dir = cand
			_crossfire_dir = best_dir
			_crossfire_until_ms = cf_now + CROSSFIRE_COMMIT_MS
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
	if charge_corridors.empty() and proj_corridors.size() == 1:
		proj_dodging = true
		var pc = proj_corridors[0]
		var p_tangent = pc[1].tangent()
		var p_side = 1.0 if pc[3] >= 0.0 else - 1.0
		var p_here = player.position + p_tangent * p_side * 200.0
		var p_there = player.position - p_tangent * p_side * 200.0
		var p_score_here = min(_wall_room(p_here, far_corner), DODGE_WALL_ROOM_CAP) \
				+ _enemy_room(p_here, close_enemy_positions)
		var p_score_there = min(_wall_room(p_there, far_corner), DODGE_WALL_ROOM_CAP) \
				+ _enemy_room(p_there, close_enemy_positions)
		if p_score_there > p_score_here + 50.0:
			p_side = - p_side
		move_vector = move_vector + p_tangent * p_side * PROJ_DODGE_STRENGTH * (0.5 + pc[4]) * repel_caution
	elif charge_corridors.empty() and proj_corridors.size() >= 2:
		proj_dodging = true
		var pd_now = OS.get_ticks_msec()
		if pd_now >= _proj_dodge_until_ms:
			var pd_best_dir = Vector2.ZERO
			var pd_best_score = - 1e9
			for k in range(16):
				var cand = Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0))
				var future = player.position + cand * 150.0
				# Corridor clearance capped so swarm/wall terms break ties
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
				var score = min_clear + enemy_room / 3.0 + _wall_room(future, far_corner) / 6.0
				if score > pd_best_score:
					pd_best_score = score
					pd_best_dir = cand
			_proj_dodge_dir = pd_best_dir
			_proj_dodge_until_ms = pd_now + PROJ_DODGE_COMMIT_MS
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
			_aoe_flee_until_ms = af_now + AOE_FLEE_COMMIT_MS
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
					- 40.0 * _proj_blocked_count(probe, proj_corridors)
			if score > best_score:
				best_score = score
				best_angle = mid
		if rad2deg(largest_gap) <= 360.0 - ENCIRCLE_COVERAGE_DEG:
			escaping = true
			must_run_away = true
			var now = OS.get_ticks_msec()
			if now >= _escape_until_ms:
				_escape_dir = Vector2(cos(best_angle), sin(best_angle))
				_escape_until_ms = now + ESCAPE_COMMIT_MS
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

	if (shooting_anyone and not must_run_away) and is_soldier:
		return Vector2.ZERO

	return move_vector.normalized()


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

	return to_player.normalized() * weight / gap_sq # point-blank: radial panic
