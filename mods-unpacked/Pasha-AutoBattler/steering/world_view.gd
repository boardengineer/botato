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
const KILL_HP_REF = 20.0         # typical trash HP; sets the killability falloff
const EXPECTED_EXCHANGES = 2.0   # contacts an unkilled enemy gets before it dies anyway
const EGG_VALUE = 60.0           # a spawner is worth far more dead than its own damage
                                 # suggests: everything it hatches is future damage too

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

	weapon_range = _weapon_range(player)
	prefers_still = RunData.get_player_character(0).name.to_lower() == "character_soldier"

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

	current_hp = float(player.current_stats.health)
	var missing_hp = float(player.max_stats.health) - current_hp
	for c in main._consumables:
		if c.position.distance_squared_to(pos) < pickup_sq:
			rewards.push_back([c.position, min(12.0, missing_hp)])
	for g in main._active_golds:
		if g.position.distance_squared_to(pos) < pickup_sq:
			rewards.push_back([g.position, 0.8])


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
		unit_speed = float(unit.current_stats.speed)
		var goal = pos
		var mb = unit._current_movement_behavior
		if mb and ("_current_target" in mb) and mb._current_target != Vector2.ZERO:
			goal = mb._current_target
		var toward = goal - unit.position
		if toward.length_squared() > 1.0:
			chase = toward.normalized() * unit_speed
	threats.push_back([unit.position, chase, radius, damage, KIND_CONTACT, 0.0,
			_contact_ticks(unit_speed), INF_TIME])


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
	var dash_speed = float(unit.current_stats.speed) + behavior.charge_speed
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
			threats.push_back([center + p.velocity * m_arm, p.velocity, radius,
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
	var killability = KILL_HP_REF / (KILL_HP_REF + health)

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
