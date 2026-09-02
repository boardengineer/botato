extends "res://entities/units/movement_behaviors/player_movement_behavior.gd"

# The bot is steered by the candidate-action arbiter in steering/ (Arbiter +
# WorldView). get_movement() hands every bot-controlled slot to _arbiter_move();
# human slots fall through to the base movement.
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
	var player = get_parent()

	if not enabled and not CoopService.is_bot_by_index[player.player_index]:
		$"/root/Main/Camera".smoothing_enabled = false
		return .get_movement()

	# The old field controller was removed; the arbiter always steers the bot now.
	arbiter_active = true
	return _arbiter_move(player)


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


