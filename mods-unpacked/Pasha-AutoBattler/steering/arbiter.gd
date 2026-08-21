extends Reference

# Arbiter: picks ONE movement action per frame by scoring every candidate
# direction under a single cost function, in a single unit (expected HP).
#
# This replaces the potential-field controller's summed force terms. The two
# differ in kind, not degree:
#
#   A summed field asks "which way do all the pressures push me?" Opposing
#   pressures cancel, so a ring of enemies produces a near-zero vector and the
#   field goes blind exactly when it matters most. Every escape subsystem in
#   the old controller exists to detect a case where the sum lied.
#
#   An arbiter asks "of the moves available, which ends best?" Nothing cancels:
#   being surrounded means every candidate scores badly and the least-bad one
#   still wins. Threading two crossing bullet lanes needs no special case,
#   because a candidate that leaves lane A and enters lane B pays for lane B.
#
# Cost is expected HP lost over a short horizon, plus opportunity terms
# converted into HP. Because every term shares that unit, the weights are
# interpretable and tunable by search rather than by hand-balancing strengths.

# -- Horizon --
const HORIZON = 0.8              # s of lookahead; beyond this we re-decide anyway
const TIME_DISCOUNT = 0.45       # a threat landing at t=H is this much cheaper than
                                 # one landing now: later hits get more chances to be
                                 # dodged by a future frame's decision
const MIN_DISCOUNT = 0.15        # ...but never free. A fixed discount applied past the
                                 # horizon would go negative and turn a distant threat
                                 # into a REWARD, so it floors here instead.

# -- Slow-threat lookahead --
#
# A fixed time horizon buys wildly different warning DISTANCES depending on how
# fast the threat moves: 0.8 s is 480 px against a 600 px/s bullet and only
# 160 px against a 200 px/s environmental one. So the slowest projectiles get
# the least reaction distance -- and they hit hardest (measured 7.0 damage per
# hit against 3.6 for regular enemy fire).
#
# The consequence is measurable and specific: environmental bullets land while
# the bot is fleeing IN THEIR DIRECTION 45% of the time, against 17% for fast
# fire. A 470 px/s potato is being run down by a 200 px/s bullet, because a
# bullet 300 px behind arrives at t=1.5 s, sits outside the horizon, and
# therefore costs exactly zero -- so nothing stops the bot walking into where
# it will be hit.
#
# Fix: stretch the scan window for slow movers until it covers a fixed DISTANCE
# rather than a fixed time. This is the same thing the old field controller's
# F6 "slow-shot distance floor" bought, rebuilt as geometry instead of a
# special case.
const SCAN_DISTANCE = 420.0      # px of warning every projectile should get
const SCAN_MAX = 2.4             # s ceiling; past this our own straight-line path
                                 # assumption is worthless anyway

# -- Action space --
# 24 headings at 15 deg, then two bisection rounds around the winner: each
# round tests half a step either side, so the effective resolution is 15/4 =
# 3.75 deg for four extra evaluations rather than the 96 a flat sweep needs.
const DIRS = 24
const REFINE_ROUNDS = 2

# -- Collision --
const HIT_MARGIN = 1.6           # dmin beyond (radii * this) scores zero; between
                                 # hard contact and this the cost tapers smoothly, so
                                 # "barely clear" and "comfortably clear" differ
const BODY_RADIUS_FALLBACK = 20.0
# How many times a threat lands over the horizon is no longer a constant here:
# world_view computes it per threat (T_TICKS), because a body you cannot outrun
# keeps hitting for every horizon you stay attached while a bullet hits once.

# -- Lethality --
# Absolute HP is the wrong price for a hit. Losing 5 HP is a scratch at 78 max
# and nearly half your life at 12, but a flat cost of 5 sits on the same scale
# as the shaping terms below -- so on a fragile build the scorer will happily
# trade a hit for better positioning. That is what killed it on w2-fisherman
# (0/5, dying at t=8-19s on a 12 HP build) while the field controller went 4/5.
const LETHALITY = 4.0            # cost multiplier at the point where one hit would kill

# -- Weights (HP units; tunable by search) --
const W_PROJ = 1.0               # projectile damage is already HP; this is the anchor
const W_CONTACT = 1.0
const W_DASH = 1.4               # a dash that connects also staggers; worse than its damage
const W_AOE = 1.2
const W_LATENT = 0.5             # an idle charger that COULD launch inside the horizon
const W_ROOM = 6.0               # crowding cost at the horizon's end
const W_WALL = 16.0              # wall proximity, counted per axis so corners cost double.
                                 # Raised from 8: at 8 the term peaked at 4 per axis
                                 # while threats cost 15-65 after lethality scaling, so
                                 # the bot accepted being pinned rather than cross one
const WALL_POWER = 2.0           # superlinear ramp: concentrate the cost in the last
                                 # stretch instead of pushing toward the centre always
const WALL_ENCLOSE_ARC = 0.8     # how strongly a near wall counts as blocked headings
const W_ENCLOSE = 5.0            # threats spread around us rather than massed on one side
const W_DPS = 14.0               # reward for holding killable, dangerous things in weapon range
const W_PICKUP = 1.0             # reward for closing on gold / food / loot
const W_HYST = 1.2               # reward for agreeing with last frame's choice
const W_REVERSE = 2.0            # extra cost for a full reversal

# -- Terminal-state shaping --
const ROOM_CAP = 260.0           # crowding beyond this distance is not crowding
const WALL_CAP = 220.0           # wall room beyond this is irrelevant
const ENCLOSE_RADIUS = 340.0     # threats inside this ring shape the enclosure term
const ENCLOSE_MIN = 3            # fewer than this cannot meaningfully surround us
const PICKUP_FALLOFF = 320.0     # loot this far away barely steers us

# -- Engagement --
# Killing something is worth the damage it would otherwise have done to us, so
# targets are weighted by threat-value (computed in world_view), not counted.
# A flat count saturated: on a busy wave every direction had five-plus enemies
# in range, so the term went constant across the whole compass and stopped
# discriminating exactly when the fight was thickest.
const KILL_SOFT = 40.0           # soft-saturation scale; value beyond this has
                                 # diminishing but never zero marginal return, so
                                 # the term keeps discriminating on dense waves
const ACQUIRE_BAND = 220.0       # targets this far OUTSIDE weapon range still pull,
                                 # which is the only thing making the bot close in

# -- Pin escape --
# Four attempts to solve pinning by WEIGHT failed: wall28 flat, peril regressed
# five snapshots, trap null on w7 (t=0.49 vs noise 1.65) and null on w11. They
# shared one defect -- each made a pin expensive INSIDE the same sum, so the way
# out still had to outvote every threat term, and in a corner every exit points
# through something. This is a MODE instead: once the bot is confirmed stuck it
# stops optimising the blend, discounts damage on purpose, and commits to
# leaving for a fixed spell.
const PIN_EDGE = 150.0           # closer than this to a wall to count as pinned
const PIN_CLEAR = 260.0          # far enough out to call the escape finished
const PIN_WINDOW = 24            # frames of position history (~0.4 s)
const PIN_TRAVEL_FRAC = 0.35     # stuck if net travel is under this share of what
                                 # our speed could have covered over the window
const PIN_CONFIRM = 8            # consecutive stuck frames before the mode fires
const PIN_TICKS = 36             # frames of COMMITTED escape (~0.6 s). Commitment is
                                 # the point: a pin is a local minimum, so leaving
                                 # MUST look worse for several frames. Re-deciding
                                 # every frame is what leaves the bot dithering.
const PIN_THREAT = 0.25          # damage discount while escaping -- the "through some
                                 # damage" knob. 0 ignores threats entirely, 1 is
                                 # normal caution and so is an exact no-op control.
const PIN_WALL_BOOST = 2.5       # pull much harder toward open floor while escaping

# -- Threat kinds --
const KIND_PROJ = 0
const KIND_CONTACT = 1
const KIND_DASH = 2              # a charge, in flight or still winding up
const KIND_AOE = 3               # stationary ground telegraph

# -- Threat tuple layout (as built by world_view) --
const T_POS = 0
const T_VEL = 1
const T_RADIUS = 2
const T_DAMAGE = 3
const T_KIND = 4
const T_START = 5                # seconds until this threat starts moving (dash wind-up)
const T_TICKS = 6                # expected damage applications over the horizon:
                                 # 1 for anything spent on impact, more for a body
                                 # that stays attached (see world_view)
const T_END = 7                  # seconds until this threat stops being dangerous.
                                 # Only a pillar uses it (armed 0.14 s, then inert);
                                 # everything else passes INF_TIME. Without it an
                                 # armed-at-0.54 s pillar would be feared for the
                                 # whole horizon, which is most of the ground it
                                 # wrongly denies us.

# -- Target tuple layout --
const TG_POS = 0
const TG_VALUE = 1               # expected HP this enemy costs us if left alive

# -- Charger tuple layout --
const C_POS = 0
const C_RANGE = 1                # launch range: outside it the dash cannot trigger
const C_DAMAGE = 2
const C_READY = 3                # seconds until its cooldown expires

# Tunable weights, seeded from the constants above. They are instance vars
# rather than consts so a benchmark can sweep them from the command line
# (--arb-dps=9 etc.) without a code edit between runs, which is what both
# ablation and any search-based tuning need.
var w_proj = W_PROJ
var w_contact = W_CONTACT
var w_dash = W_DASH
var w_aoe = W_AOE
var w_latent = W_LATENT
var w_room = W_ROOM
var w_wall = W_WALL
var w_enclose = W_ENCLOSE
var w_dps = W_DPS
var w_pickup = W_PICKUP
var w_hyst = W_HYST
var lethality = LETHALITY
var horizon = HORIZON
# Separated from w_room on purpose: the weight sets how hard crowding is
# punished, this sets how far out it is felt at all. A bot that keeps a 136 px
# standoff where the field controller keeps 231 needs the reach changed, not
# the strength -- at ROOM_CAP the term is already flat, so no weight can push
# the standoff past it.
var room_cap = ROOM_CAP
# Sweepable: --arb-scandist=0 collapses the clamp to the horizon for every
# threat, reproducing the old fixed-window behaviour exactly, so it is a free
# exact control arm rather than an approximation of one.
var scan_distance = SCAN_DISTANCE

var pin_enable = 0.0             # --arb-pin=1 turns the escape mode on; default OFF
var pin_threat = PIN_THREAT      # --arb-pinthreat

var last_dir = Vector2.ZERO      # read for hysteresis and by telemetry
var last_scores = []             # per-candidate cost, for the debug overlay
var last_dirs = []               # candidate directions matching last_scores
var last_best_index = -1
var last_escaping = false        # did the escape mode fire this frame (telemetry)
var pin_fires = 0                # escape activations this run, for the sweep
var _pin_hist = []               # recent positions, newest last
var _pin_frames = 0              # consecutive confirmed-stuck frames
var _pin_ticks = 0               # frames of escape left to run

# Per-frame prepared threat data. Everything here is candidate-independent, so
# it is computed once instead of once per candidate -- with 29 candidates that
# is the difference between affording the wider action space and not.
var _p_pos = []                  # threat position
var _p_vel = []                  # threat velocity
var _p_rad = []                  # combined hit radius (threat + player body)
var _p_soft = []                 # squared radius past which a miss scores zero
var _p_coef = []                 # full damage coefficient: damage x kind x lethality x mitigation
var _p_start = []                # wind-up delay
var _p_end = []                  # when it stops being dangerous, clamped to horizon
var _p_future = []               # where it will be at the horizon


# Apply command-line weight overrides, e.g. {"dps": 9.0, "enclose": 0.0}.
# Unknown keys are ignored so a sweep script can pass a superset.
func apply_overrides(d: Dictionary) -> void:
	if d.has("proj"): w_proj = float(d["proj"])
	if d.has("contact"): w_contact = float(d["contact"])
	if d.has("dash"): w_dash = float(d["dash"])
	if d.has("aoe"): w_aoe = float(d["aoe"])
	if d.has("latent"): w_latent = float(d["latent"])
	if d.has("room"): w_room = float(d["room"])
	if d.has("wall"): w_wall = float(d["wall"])
	if d.has("enclose"): w_enclose = float(d["enclose"])
	if d.has("dps"): w_dps = float(d["dps"])
	if d.has("pickup"): w_pickup = float(d["pickup"])
	if d.has("hyst"): w_hyst = float(d["hyst"])
	if d.has("lethality"): lethality = float(d["lethality"])
	if d.has("horizon"): horizon = float(d["horizon"])
	if d.has("roomcap"): room_cap = float(d["roomcap"])
	if d.has("scandist"): scan_distance = max(float(d["scandist"]), 0.0)
	if d.has("pin"): pin_enable = float(d["pin"])
	if d.has("pinthreat"): pin_threat = float(d["pinthreat"])
	if not d.empty():
		print("ARBITER weights: proj=%.2f contact=%.2f dash=%.2f aoe=%.2f latent=%.2f room=%.2f roomcap=%.0f wall=%.2f enclose=%.2f dps=%.2f pickup=%.2f hyst=%.2f lethality=%.2f horizon=%.2f pin=%.2f pinthreat=%.2f" % [
			w_proj, w_contact, w_dash, w_aoe, w_latent, w_room, room_cap, w_wall,
			w_enclose, w_dps, w_pickup, w_hyst, lethality, horizon, pin_enable, pin_threat])


# Returns the chosen unit direction, or ZERO to stand still.
#   threats:    array of threat tuples (see layout above)
#   rewards:    array of [pos, value_hp] pickup targets
#   targets:    array of enemy positions worth shooting
#   chargers:   array of idle-charger tuples (latent dash risk)
#   mitigation: expected share of incoming damage that actually lands (dodge, armor)
func choose(p0: Vector2, speed: float, body_radius: float, far: Vector2,
		threats: Array, rewards: Array, targets: Array, chargers: Array,
		weapon_range: float, prefers_still: bool, current_hp: float,
		mitigation: float) -> Vector2:

	var edge = min(min(p0.x, far.x - p0.x), min(p0.y, far.y - p0.y))
	var escaping = false
	if pin_enable != 0.0:
		escaping = _update_pin(p0, speed, edge)
	last_escaping = escaping

	# Scaled BEFORE _prepare, deliberately: the per-kind weight is baked into
	# _p_coef in there (see the kw assignment), so discounting these afterwards
	# would compile cleanly, change nothing, and hand back a convincing null.
	var saved = []
	if escaping:
		saved = [w_proj, w_contact, w_dash, w_aoe, w_latent, w_dps, w_room, w_wall]
		w_proj *= pin_threat
		w_contact *= pin_threat
		w_dash *= pin_threat
		w_aoe *= pin_threat
		w_latent *= pin_threat
		w_dps = 0.0        # the kill reward must not anchor us in the corner
		w_room = 0.0       # crowding is WHY we are here; it cannot also be the exit test
		w_wall *= PIN_WALL_BOOST
		# w_enclose is left alone on purpose: "which headings are blocked" is
		# exactly the right question to be asking while escaping.

	_prepare(p0, speed, body_radius, threats, current_hp, mitigation)

	var cands = []
	for k in range(DIRS):
		var a = k * TAU / DIRS
		cands.push_back(Vector2(cos(a), sin(a)))
	cands.push_back(Vector2.ZERO)   # standing still is a real option, not a fallback

	var scores = []
	var best_i = 0
	var best_cost = 1e18
	for i in range(cands.size()):
		var c = _cost(cands[i], p0, speed, body_radius, far, rewards, targets,
				chargers, weapon_range, prefers_still, current_hp)
		scores.push_back(c)
		if c < best_cost:
			best_cost = c
			best_i = i

	# Bisection refinement. A flat 24-way sweep cannot thread a bullet gap
	# narrower than 15 deg; halving twice around the winner reaches 3.75 deg
	# without paying for 96 candidates every frame.
	var best_dir = cands[best_i]
	if best_dir != Vector2.ZERO:
		var step = TAU / DIRS * 0.5
		for _r in range(REFINE_ROUNDS):
			var improved = best_dir
			for s in [step, -step]:
				var rc = best_dir.rotated(s)
				var c = _cost(rc, p0, speed, body_radius, far, rewards, targets,
						chargers, weapon_range, prefers_still, current_hp)
				cands.push_back(rc)
				scores.push_back(c)
				if c < best_cost:
					best_cost = c
					improved = rc
					best_i = cands.size() - 1
			best_dir = improved
			step *= 0.5

	last_scores = scores
	last_dirs = cands
	last_best_index = best_i
	last_dir = best_dir

	if escaping:
		w_proj = saved[0]
		w_contact = saved[1]
		w_dash = saved[2]
		w_aoe = saved[3]
		w_latent = saved[4]
		w_dps = saved[5]
		w_room = saved[6]
		w_wall = saved[7]
	return best_dir


# Is the bot actually STUCK, as opposed to merely near a wall? Skimming an edge at
# full speed is ordinary play and must not trigger this. What matters is failing to
# convert speed into DISPLACEMENT while cornered, so the test is net travel across a
# window. That also catches oscillation -- a bot flipping between two headings moves
# every frame but goes nowhere, which any per-frame speed check reads as healthy.
# Not being able to see that state is likely why four weight-based attempts could
# not move it: they could only see wall distance.
func _update_pin(p0: Vector2, speed: float, edge: float) -> bool:
	_pin_hist.push_back(p0)
	if _pin_hist.size() > PIN_WINDOW:
		_pin_hist.pop_front()

	if _pin_ticks > 0:
		_pin_ticks -= 1
		# End early once genuinely clear, so we spend no more of the damage
		# budget than getting out actually cost.
		if edge >= PIN_CLEAR:
			_pin_ticks = 0
			_pin_frames = 0
			return false
		return true

	var stuck = false
	if edge < PIN_EDGE and _pin_hist.size() >= PIN_WINDOW:
		var travelled = p0.distance_to(_pin_hist[0])
		var could = speed * float(PIN_WINDOW) / 60.0
		stuck = travelled < could * PIN_TRAVEL_FRAC
	if stuck:
		_pin_frames += 1
	else:
		_pin_frames = 0

	if _pin_frames >= PIN_CONFIRM:
		_pin_frames = 0
		_pin_ticks = PIN_TICKS
		pin_fires += 1
		return true
	return false


# Hoist every candidate-independent quantity out of the scoring loop.
func _prepare(p0: Vector2, speed: float, body_radius: float, threats: Array,
		current_hp: float, mitigation: float) -> void:
	_p_pos = []
	_p_vel = []
	_p_rad = []
	_p_soft = []
	_p_coef = []
	_p_start = []
	_p_end = []
	_p_future = []

	var inv_hp = 1.0 / max(current_hp, 1.0)
	var reach = speed * horizon          # everything we could possibly walk to

	for t in threats:
		var radius = t[T_RADIUS] + body_radius
		var soft = radius * HIT_MARGIN
		var pos = t[T_POS]
		var vel = t[T_VEL]
		var kind = t[T_KIND]
		var speed_of = vel.length()

		# How far ahead this particular threat is worth scanning. Bodies and
		# dashes keep the plain horizon -- they are already fast relative to us
		# and a longer look would just compound the straight-line assumption.
		# Only projectiles, whose speed varies 3x across the game, get stretched.
		var scan = horizon
		if kind == KIND_PROJ and speed_of > 1.0:
			scan = clamp(scan_distance / speed_of, horizon, SCAN_MAX)
		var t_end = min(scan, t[T_END])

		# Crowding still measures where things are at the HORIZON, not at the
		# end of the scan: "how boxed in am I when I get there" is a question
		# about the move being scored, and stretching it for slow bullets would
		# quietly redefine the terminal state for everything else.
		var span = max(horizon - t[T_START], 0.0)
		var scan_span = max(t_end - t[T_START], 0.0)

		# Cull: if the threat cannot close on any reachable point, and ends the
		# horizon far outside the crowding ring, it cannot affect any candidate.
		var travel = speed_of * scan_span
		var gap = pos.distance_to(p0)
		if gap - travel > reach + max(soft, max(ENCLOSE_RADIUS, room_cap) + radius):
			continue

		# Price this hit by the share of remaining life it takes, so the same
		# 5 damage is a scratch at full HP and near-lethal on a 12 HP build.
		# Lethality stays keyed to a SINGLE hit, not to dmg * ticks. Scaling it
		# by the whole expected encounter would compound persistence twice --
		# once in the coefficient and again here -- and a sticky body would end
		# up quadratically feared. One hit landing is what the multiplier was
		# defined against; how many land is already priced by T_TICKS.
		var dmg = t[T_DAMAGE]
		var lethal = 1.0 + lethality * min(dmg * inv_hp, 1.0)
		var kw = w_proj
		if kind == KIND_CONTACT:
			kw = w_contact
		elif kind == KIND_DASH:
			kw = w_dash
		elif kind == KIND_AOE:
			kw = w_aoe

		_p_pos.push_back(pos)
		_p_vel.push_back(vel)
		_p_rad.push_back(radius)
		_p_soft.push_back(soft * soft)
		_p_coef.push_back(dmg * kw * t[T_TICKS] * lethal * mitigation)
		_p_start.push_back(t[T_START])
		_p_end.push_back(t_end)
		_p_future.push_back(pos + vel * span)


func _cost(d: Vector2, p0: Vector2, speed: float, body_radius: float, far: Vector2,
		rewards: Array, targets: Array, chargers: Array,
		weapon_range: float, prefers_still: bool, current_hp: float) -> float:

	var v = d * speed
	# Walls do not reject a move, they cancel the component that would cross
	# them -- the engine resolves a blocked step by sliding. Clamping models
	# that exactly, and it matters most when cornered: a bot that is merely
	# penalized for facing a wall will not slide along one to escape.
	var p_end = p0 + v * horizon
	p_end.x = clamp(p_end.x, body_radius, far.x - body_radius)
	p_end.y = clamp(p_end.y, body_radius, far.y - body_radius)
	var total = 0.0

	var room = room_cap
	var enc_sum = Vector2.ZERO
	var enc_w = 0.0
	var enclose_sq = ENCLOSE_RADIUS * ENCLOSE_RADIUS
	# Crowding may be felt further out than enclosure is; scan to whichever
	# reaches further so raising room_cap past ENCLOSE_RADIUS is not a no-op.
	var scan_sq = max(enclose_sq, room_cap * room_cap)

	for i in range(_p_pos.size()):
		# --- Expected damage: analytic closest approach over the whole path ---
		# t_start defers the threat's motion, which is what makes a charge's
		# wind-up tractable: the dasher is frozen for a known 0.4 s, so the far
		# end of its lane is genuinely safe and we need not give up that ground.
		# The danger window is [t_start, t_end], not [t_start, horizon]. For a
		# pillar those differ by most of its width: it is armed for 0.14 s and
		# the horizon is 0.8 s, so scanning to the horizon charges us for
		# walking over ground that has already gone cold.
		var t_start = _p_start[i]
		var span = _p_end[i] - t_start
		if span > 0.0:
			var w = _p_pos[i] - (p0 + v * t_start)
			var rel = _p_vel[i] - v
			var t = 0.0
			var denom = rel.length_squared()
			if denom > 0.000001:
				t = clamp(-w.dot(rel) / denom, 0.0, span)
			var miss = w + rel * t
			var d2 = miss.length_squared()
			# Squared-distance reject first: most threats are clearly clear, and
			# skipping their sqrt is what pays for the wider action space.
			if d2 < _p_soft[i]:
				var hit = _taper(sqrt(d2), _p_rad[i])
				if hit > 0.0:
					# Floored, not just discounted: a slow bullet can now be scanned
					# out to SCAN_MAX, where the plain linear form would go
					# negative and pay us to stand in front of it. The floor is
					# also what makes this a distance floor rather than a hard
					# cutoff -- a far-off shot stays cheap but never free.
					var when = t_start + t
					var discount = max(1.0 - TIME_DISCOUNT * when / horizon, MIN_DISCOUNT)
					total += _p_coef[i] * hit * discount

		# --- Where this leaves us ---
		# One pass serves both terminal terms: the offset to the threat's future
		# position gives crowding, and its direction gives enclosure.
		var off = _p_future[i] - p_end
		var off_sq = off.length_squared()
		if off_sq < scan_sq:
			var dist = sqrt(off_sq)
			var edge = dist - _p_rad[i]
			if edge < room:
				room = edge
			if off_sq < enclose_sq and dist > 1.0:
				enc_sum += off / dist    # unit vector without a second sqrt
				enc_w += 1.0

	# Crowding: how much room is there at the end of the move. This one term
	# replaces gap-seeking and the pocket heuristics -- a direction that ends
	# boxed in is expensive whether or not anything is currently aimed at us.
	if room < room_cap:
		total += w_room * (1.0 - max(room, 0.0) / room_cap)

	# Enclosure: threats massed on one side leave an escape, threats spread
	# evenly around us do not. The mean unit direction is long when they are
	# all one way and near zero when they surround us -- which is exactly the
	# blindness that made the old field controller need a separate
	# encirclement detector.
	# Walls, per axis. The cost ramps with WALL_POWER rather than linearly: the
	# problem is not being in the outer third of the arena, it is being pinned
	# with nowhere left to give, so the last stretch must cost far more than
	# the approach. Counting both axes makes a corner roughly double a wall.
	var wx = min(p_end.x, far.x - p_end.x)
	var wy = min(p_end.y, far.y - p_end.y)
	if wx < WALL_CAP:
		total += w_wall * 0.5 * pow(1.0 - wx / WALL_CAP, WALL_POWER)
	if wy < WALL_CAP:
		total += w_wall * 0.5 * pow(1.0 - wy / WALL_CAP, WALL_POWER)

	# A wall is an enclosure the same way a body is: it deletes escape headings.
	# Threats alone cannot express "backed against a wall with the swarm on the
	# open side" -- their directions all point one way, which reads as SAFE by
	# the coherence measure. Feeding the blocked headings in as pseudo-threats
	# is what makes being pinned score as being surrounded, and it is the same
	# trick the old field controller used to stop its gap-seeker being fooled.
	if wx < ENCLOSE_RADIUS or wy < ENCLOSE_RADIUS:
		var walls = [
			[Vector2(-1.0, 0.0), p_end.x], [Vector2(1.0, 0.0), far.x - p_end.x],
			[Vector2(0.0, -1.0), p_end.y], [Vector2(0.0, 1.0), far.y - p_end.y]]
		for wl in walls:
			var wd = wl[1]
			if wd >= ENCLOSE_RADIUS:
				continue
			# A near wall blocks a whole arc, not a single bearing.
			var weight = (1.0 - wd / ENCLOSE_RADIUS) * WALL_ENCLOSE_ARC
			var n = wl[0]
			enc_sum += n * weight + n.rotated(0.7) * weight + n.rotated(-0.7) * weight
			enc_w += 3.0 * weight

	if enc_w >= float(ENCLOSE_MIN):
		total += w_enclose * (1.0 - enc_sum.length() / enc_w)

	# Latent dashes: a charger sitting on a nearly-expired cooldown is a threat
	# that has not been declared yet. It cannot launch at all from outside its
	# range, so the cheapest answer is usually to leave the launch window --
	# which is what the old controller spent three standoff constants encoding.
	if not chargers.empty():
		var inv_hp = 1.0 / max(current_hp, 1.0)
		for c in chargers:
			var ready = c[C_READY]
			if ready >= horizon:
				continue
			var rng = c[C_RANGE]
			if p_end.distance_squared_to(c[C_POS]) > rng * rng:
				continue    # outside its launch range: it never fires at us
			var dmg = c[C_DAMAGE]
			var lethal = 1.0 + lethality * min(dmg * inv_hp, 1.0)
			total += dmg * w_latent * lethal * (1.0 - ready / horizon)

	# --- Opportunity: damage prevented by killing things ---
	# Weapons fire on their own, so the only lever movement has is WHICH things
	# are in range. Each target carries the damage it is expected to do to us if
	# left alive, discounted by how killable it actually is -- so a 4 HP charger
	# outranks an 880 HP boss we will not kill this second, and an egg outranks
	# both because everything it hatches is future damage too.
	var kill_gain = 0.0
	for t in targets:
		var dist = p_end.distance_to(t[TG_POS])
		if dist > weapon_range + ACQUIRE_BAND:
			continue
		# Full credit in range, tapering outside it. Without this taper there is
		# no gradient at all toward a fight the bot is not already in.
		var reach = 1.0
		if dist > weapon_range:
			reach = 1.0 - (dist - weapon_range) / ACQUIRE_BAND
		kill_gain += t[TG_VALUE] * reach
	if kill_gain > 0.0:
		# Soft saturation: diminishing returns, but never a flat line, so the
		# term still separates candidates when the screen is full.
		total -= w_dps * (1.0 - exp(-kill_gain / KILL_SOFT))
	if prefers_still and d == Vector2.ZERO and kill_gain > 0.0:
		# Characters that only fire while stationary are not a special case;
		# standing still is just where their damage term pays out.
		total -= w_dps * (1.0 - exp(-kill_gain / KILL_SOFT))

	for r in rewards:
		var d0 = p0.distance_to(r[0])
		var d1 = p_end.distance_to(r[0])
		var closed = (d0 - d1) / max(speed * horizon, 1.0)   # -1..1, share of the move spent approaching
		total -= w_pickup * r[1] * closed / (1.0 + d0 / PICKUP_FALLOFF)

	# --- Continuity ---
	# One hysteresis term in the arbiter does the job that five separate commit
	# timers did in the field controller, and it cannot deadlock: a threat that
	# actually appears outscores the bonus immediately.
	if last_dir != Vector2.ZERO and d != Vector2.ZERO:
		var agree = d.dot(last_dir)
		total -= w_hyst * agree
		if agree < -0.5:
			total += W_REVERSE * (-agree)

	return total


# 1.0 inside contact, tapering smoothly to 0 at radii * HIT_MARGIN. The taper
# is what gives the argmax a gradient: without it every clear direction ties
# and the choice is decided by noise.
func _taper(dist: float, radii: float) -> float:
	if dist <= radii:
		return 1.0
	var soft = radii * HIT_MARGIN
	if dist >= soft:
		return 0.0
	var x = 1.0 - (dist - radii) / (soft - radii)
	return x * x * (3.0 - 2.0 * x)
