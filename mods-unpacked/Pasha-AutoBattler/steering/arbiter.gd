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
# -- Crowd runway --
# The room term above looks 0.8 s ahead. On the tracker Pacifist w9 bed the
# bot holds the annulus for ~20 s and is then walked from mid-arena to the
# wall in a few seconds by 100 chasers: every 0.8 s step is locally right and
# the sum of them is a corner (PHIST: anc 600 -> 1200, edge 12, then the hit
# chain). The wall runway prices the WALL 2.4 s out; nothing priced the crowd
# that far. This is the crowd's runway: the same crowding measure taken at
# FAR_T along the bearing, threats extrapolated the same way, so a heading
# that stays open beats one the pack will close. Moving candidates only:
# standing is priced by the threat terms already. --arb-roomfar sweeps it.
const FAR_T = 2.0
const W_ROOM_FAR = 3.0
const ROOM_FAR_CAP = 320.0
const WALL_CAP = 220.0           # wall room beyond this is irrelevant
const ENCLOSE_RADIUS = 340.0     # threats inside this ring shape the enclosure term
const ENCLOSE_MIN = 3            # fewer than this cannot meaningfully surround us
const PICKUP_FALLOFF = 320.0     # loot this far away barely steers us
const PICKUP_TAKEN = 1.0         # x value: bonus for a move that ENDS inside the
                                 # attract radius of a drop it started outside --
                                 # the pass-through pickup a kiting lap is made of.
                                 # --arb-taken sweeps it; 0 is the exact control.

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

# -- Character anchor --
# Some characters have a point on the map worth fighting near -- the Builder's
# turret is the first (world_view decides WHO anchors and WHERE; the scorer
# only prices distance). A LEASH, not a magnet: zero cost anywhere inside the
# radius so dodging stays free, linear pull beyond it so the pull GROWS the
# further the bot strays, capped so a spawn across the arena cannot flatten
# the compass. Linear matters: the differential between a candidate walking
# home and one walking away is constant (~w_anchor * 670/ANCHOR_NORM ~ 27)
# wherever the bot is below the cap, which is enough to win every tie and
# lose every argument with a live corridor.
const W_ANCHOR = 12.0            # sweep via --arb-anchor; 0 is the exact control arm
const ANCHOR_NORM = 300.0        # px beyond the leash that cost one w_anchor
const ANCHOR_CAP = 8.0           # ~2400 px out the ramp stops growing; differentials
                                 # between candidates survive until then
# The same term read from the other side is a KEEP-OUT ring: cost for being
# CLOSER than an inner radius. That one shape covers three behaviours the
# research asked for -- a leash (inner 0), a perimeter orbit (inner large,
# anchored on the arena middle, so the cheapest floor is the rim and the bot
# laps it rather than parking against one wall), and Mage's stay-away-from-your
# own-turret spacing -- without the scorer knowing which is which.

# -- Contact seeking --
# The inverse of kiting, for characters whose damage or healing is paid in hits
# TAKEN or in one swing landing across a crowd. Deliberately NOT a threat-weight
# change: dropping the threat terms would make the bot ignore corridors and
# dashes too, which kills these characters just as dead as it kills the others.
# Instead it is a separate pull toward the nearest thing worth touching, so a
# live dash still outscores it and the bot walks into BODIES, not into bullets.
const ENGAGE_NORM = 260.0        # distance to the nearest target that costs one
                                 # engage unit; ~a body length past contact
const ENGAGE_CAP = 2.2           # beyond ~570 px the pull stops growing, so a
                                 # far-off straggler cannot drag the bot across
                                 # the arena through everything in between
# Cluster engage (Bull): the explosion is 150 px around the potato and fires
# once per hit taken, so the value of a dive is not "how close is the nearest
# body" but "how many bodies will be inside the blast when the hit lands".
# The candidate's END position is scored by that count. The nearest-target
# pull stays on at reduced weight so the bot still closes on a lone straggler
# when no pile exists yet -- otherwise nothing would ever start one.
const ENGAGE_BLAST = 170.0       # explosion max_range 150 + ~body radius
const ENGAGE_CLUSTER_CAP = 8.0   # bodies in the blast at which the reward saturates
const ENGAGE_CLUSTER_NEAR = 0.4  # share of the nearest-target pull kept in cluster mode
# The cluster reward is PER BODY, not normalised: every body inside the blast
# at the end position dies to the first hit, so a six-body dive is worth six
# kills, not "one saturated dive". Normalised to a 14-point maximum it lost
# every vote to crowding + enclosure + the detonating hit + the bodies just
# outside the blast, and the live w4 log showed the Bull hovering at full HP
# while the crowd grew to 92. Crowding and enclosure at the end position are
# also discounted while the dive is armed: for a Bull, ending inside the
# crowd is the payoff, not the failure the terms were written to price.
const EXPLODE_CROWD = 0.35       # share of room + enclosure cost kept while diving

const NEVER_STILL_COST = 6.0     # Speedy loses 100 armour while stationary and
                                 # Hiker's income IS distance covered: standing
                                 # is a mechanical penalty, so price it as one
const FIRE_STILL_STAND = 2.0     # fire_still: standing collects the kit's +50%
                                 # dmg / +50% AS as a doubled kill payout
const FIRE_STILL_MOVE = 0.4      # ...moving keeps only the approach gradient;
                                 # weapons that fire while standing earn nothing
                                 # on the run, and the scorer must know it
const FIRE_STILL_FLOOR = 16.0    # minimum stand-and-shoot reward with a target
                                 # in true weapon range. 8 beat the room term's
                                 # wander pressure but measured 3 kills a wave:
                                 # at low HP the lethality multiplier prices a
                                 # 2-damage baby alien's approach at ~10, and a
                                 # swarm of them re-evicted the stand every
                                 # frame. 16 holds ground against light trash
                                 # pressure and still folds to anything whose
                                 # damage is actually worth fleeing
# A standing Soldier does not passively receive an approaching body -- it
# SHOOTS it, at +50% damage and +50% attack speed, and trash dies on the way
# in. Pricing that approach at full contact damage is why the bot fled from
# things that would never have arrived: threat pricing assumes the enemy
# lives to touch, which stops being true the moment standing is what kills
# it. So the STANDING candidate's contact coefficients are discounted by the
# body's killability (same KILL_HP_REF falloff the target values use): a
# 6 HP baby alien costs ~40% of book price to stand against, a 300 HP elite
# costs face value -- which reproduces the guide's play exactly: hold ground
# and mow trash, still respect elites, still dodge every bullet (projectile
# and dash coefficients are untouched). Moving candidates always pay full
# price: fleeing does not shoot anything.
# -- The damage trade --
# Field report: once enemies get CLOSE, the bot starts running and never fights
# again. The arithmetic of that spiral: a close crowd prices the stand as the
# sum of every body's contact cost, fleeing prices near zero, so flight wins
# every frame -- but flight fires no shots, the crowd never thins, and the gap
# never closes. A human Soldier breaks the spiral by TRADING: a few hit points
# are the fee for the volley that deletes the crowd. So the standing
# candidate's contact costs from KILLABLE bodies are pooled and capped at a
# budget scaled by current HP: "this much of my bar buys uninterrupted fire."
# The pool only admits genuinely killable bodies (TRADE_KILLABLE_MIN) --
# elites, bullets, dashes and telegraphs stay full price outside the pool, so
# the trade never talks the bot into standing through what actually kills it.
# The budget also shrinks with the bar: a wounded Soldier stops trading.
const TRADE_HP_SHARE = 0.5       # budget in cost points = current HP x this
const TRADE_KILLABLE_MIN = 0.15  # only bodies at least this killable join the pool.
                                 # killability = ref/(ref+hp), so 0.15 admits anything
                                 # that dies inside ~6 s of standing fire. It was 0.35
                                 # (~2 s), which on w17-d6 excluded EVERYTHING: pursuers
                                 # at 394 HP against a 186 kill_ref sat at 0.32, the pool
                                 # stayed empty, every body billed the stand at full
                                 # price, and the bot fled for 15-22 s killing 5-17.
                                 # At 0.15 the same wave ran 54-60 s at 170-270 kills
                                 # and the sustain build healed to full while standing.
                                 # Sweep via --arb-tradekill.

# -- Where a stand is allowed --
# The w12 cornering deaths were not a camping pattern: the per-second edge
# series shows the bot HERDED from open floor to the wall over 20-30 s, then
# dead within two. Every stand perk made holding ground cheap, so the bot kept
# making its stand a little closer to the wall each time the crowd pushed,
# until there was nowhere left. A reactive escape fires too late for that.
# So the perks are gated on wall room: inside FIRE_STILL_WALL_MIN the Soldier
# is priced like any other potato, the wall term walks it back out to open
# floor, and only THERE does it stand again. Escape at the loss of firing,
# but triggered by geometry before the pin instead of by a timer after it.
const FIRE_STILL_WALL_MIN = 220.0
# -- Hop candidates --
# The croc's second form drops a 10-pillar ring 250 px around the bot that
# arms 0.54 s later; every full-speed candidate covers ~280 px over the
# horizon, so all of them END on or past the ring while it is armed, and the
# only in-ring option was standing still under the dash. A hop is the move a
# human makes there: a short lateral step inside the ring. It is scored at
# HOP_FRAC speed (executed by the movement behaviour as the tap duty cycle,
# 2 frames on / 2 off) on HOP_DIRS headings, and only offered while a ground
# telegraph or a dash is within HOP_RANGE -- it costs HOP_DIRS extra
# evaluations, which the quiet frames must not pay. --arb-hop=0 disables.
const HOP_FRAC = 0.5             # MUST match the tap duty cycle (TAP_MOVE / (TAP_MOVE + TAP_STOP))
const HOP_DIRS = 8
const HOP_RANGE = 420.0
const STUTTER_SPEED_FRAC = 0.5   # net travel speed of the tap cycle; MUST match
                                 # TAP_MOVE / (TAP_MOVE + TAP_STOP) in
                                 # player_movement_behavior.gd (2 / (2 + 2))

const FIRE_STILL_KILL = 0.9      # discount share at killability 1.0. 0.75 measured
                                 # 9-39% still-frames on w6-d5: trash there runs
                                 # 15-30 HP, killability ~0.4, so the discount only
                                 # shaved a third while room+enclosure kept paying
                                 # the bot to drift off its stand
const FIRE_STILL_CROWD = 0.5     # standing's share of the room and enclosure costs.
                                 # Both terms grade the END position, so every flee
                                 # candidate beats the stand on crowding by
                                 # construction -- a permanent eviction pressure.
                                 # But crowding measures how bad this spot is for a
                                 # potato that must ESCAPE it, and a firing Soldier
                                 # is thinning the crowd instead; half price, not
                                 # zero, because bullets do not stop a surround
                                 # from closing

# -- Predictive wall avoidance --
# The wall term prices proximity at the 0.8 s horizon -- ~336 px of
# lookahead -- but the herding that ends in a corner death runs 2-5 s while
# the bot is still mid-arena at full HP (mom analysis: 87% of her hits at
# edge < 150, median 1 s from first touch to death; +16 max HP falsified
# the hit-budget theory, so the corner is an ABSORBING state and the only
# lever is not entering it). This term prices each bearing's RUNWAY: how
# long it can be held before the arena ends it. Walls slide, so a bearing
# is dead only when EVERY moving axis has exhausted its room -- straight at
# a wall stops on contact, a diagonal dies at the corner, parallel to a
# wall runs forever. Per-candidate discriminating geometry, which is what
# the four failed wall-weight attempts were not.
const W_PREDICT = 0.0            # OFF until validated; sweep via --arb-predict
const PREDICT_SECS = 2.5         # bearings that dead-end sooner than this are costed

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
const PIN_DWELL = 40             # fire_still only: frames spent inside PIN_EDGE, moving
                                 # or not, before the mode fires (~1.25 s). The stuck
                                 # test above never arms on a tap-mover -- stutter
                                 # steps read as ordinary travel -- so on w12 the
                                 # Soldier died at edge 36 with pesc=0 twice. A
                                 # stand-and-shoot kit has no business holding a
                                 # wall for more than a second: the swarm closes
                                 # the exits while it fires, and that is the corner
                                 # Any other pin-enabled row arms the same trigger
                                 # with its own "pin_dwell" (frames): a perimeter
                                 # kit sliding along the wall under bullet hell is
                                 # never "stuck" -- lateral travel reads as travel --
                                 # so without a dwell the escape never fires (w7/w8
                                 # Pacifist deaths at edge 12-36 with pesc=0).
const PIN_TICKS = 36             # frames of COMMITTED escape (~0.6 s). Commitment is
                                 # the point: a pin is a local minimum, so leaving
                                 # MUST look worse for several frames. Re-deciding
                                 # every frame is what leaves the bot dithering.
const PIN_THREAT = 0.25          # damage discount while escaping -- the "through some
                                 # damage" knob. 0 ignores threats entirely, 1 is
                                 # normal caution and so is an exact no-op control.
const PIN_WALL_BOOST = 2.5       # pull much harder toward open floor while escaping
const W_TANGENT = 30.0           # while ESCAPING: reward motion ALONG the nearest
                                 # wall. The radial exit is where the herding swarm
                                 # stands; the lateral one is usually open, and no
                                 # other term knows the difference. Only active
                                 # during pin escape, so inert while pin is off.
                                 # Sweep via --arb-tangent.
const TANGENT_RADIUS = 200.0     # wall proximity ramp for the tangent reward

# -- Threat kinds --
const KIND_PROJ = 0
const KIND_CONTACT = 1
const KIND_DASH = 2              # a charge, in flight or still winding up
const KIND_AOE = 3               # stationary ground telegraph
const KIND_MARK = 4              # a spawn marker keep-out: priced on CONTACT only. It
                                 # must not feed crowding or enclosure -- a ring of
                                 # red X's is not a surround, and on Danger 6 there are
                                 # enough of them at once to read as one

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
const T_KILL = 8                 # OPTIONAL 9th field, contact threats only: how
                                 # killable the body is (KILL_HP_REF falloff, 0-1).
                                 # Feeds the fire_still standing discount below.
                                 # Only a pillar uses it (armed 0.14 s, then inert);
                                 # everything else passes INF_TIME. Without it an
                                 # armed-at-0.54 s pillar would be feared for the
                                 # whole horizon, which is most of the ground it
                                 # wrongly denies us.

# -- Target tuple layout --
const TG_POS = 0
const TG_VALUE = 1               # expected HP this enemy costs us if left alive
const TG_BOSS = 2                # OPTIONAL: true for bosses/elites; cluster engage skips them

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
var pickup_taken = PICKUP_TAKEN  # --arb-taken
var hop_enable = 1.0             # --arb-hop
var stand_mult = 1.0             # --arb-stand: multiplier on the row's standing income (0 = off)
# A break costs more than the partial second: the NEXT full second has to be
# stood from zero too, so leaving a stand throws away progress + one whole
# tick. stand x3 on the tracker w10 bed changed nothing (156-184 materials
# either way) because the breaks are one-frame flickers priced at a fraction
# of a tick; this is what makes them dear. --arb-standcommit sweeps it.
const STAND_COMMIT = 1.0
var stand_commit = STAND_COMMIT  # --arb-standcommit
var _stand_income = 0.0          # profile stand_income: points per second a stand earns
var _stand_progress = 0.0        # profile stand_progress: share of the current tick done
var last_stand = 0.0             # telemetry mirror of _stand_income
var last_hop = false             # the chosen candidate is a half-speed hop (telemetry + execution)
var _hop_wanted = false          # set by _prepare: a telegraph or dash is close enough
var last_aoe_n = 0               # KIND_AOE threats priced this decision (telemetry)
var _pickup_radius = 0.0         # profile pickup_radius: the attract area's rim
var w_hyst = W_HYST
var lethality = LETHALITY
var lethality_override = -1.0    # --arb-lethality wins over the row's lethality key
var horizon = HORIZON
# Separated from w_room on purpose: the weight sets how hard crowding is
# punished, this sets how far out it is felt at all. A bot that keeps a 136 px
# standoff where the field controller keeps 231 needs the reach changed, not
# the strength -- at ROOM_CAP the term is already flat, so no weight can push
# the standoff past it.
var room_cap = ROOM_CAP
var w_room_far = W_ROOM_FAR      # --arb-roomfar
# Sweepable: --arb-scandist=0 collapses the clamp to the horizon for every
# threat, reproducing the old fixed-window behaviour exactly, so it is a free
# exact control arm rather than an approximation of one.
var scan_distance = SCAN_DISTANCE

var pin_enable = 0.0             # --arb-pin=1 turns the escape mode on; default OFF
var pin_threat = PIN_THREAT      # --arb-pinthreat
var w_predict = W_PREDICT        # --arb-predict
var predict_secs = PREDICT_SECS  # --arb-predsecs
var w_tangent = W_TANGENT        # --arb-tangent
var wall_swerve = 1.0            # --arb-swerve=0 reverts the dodge sim to raw v
var w_anchor = W_ANCHOR          # --arb-anchor
var trade_share = TRADE_HP_SHARE # --arb-trade: the damage-trade budget as a share of HP
var fire_floor = FIRE_STILL_FLOOR # --arb-floor: the stand-and-shoot floor
var trade_killable_min = TRADE_KILLABLE_MIN # --arb-tradekill: pool admission threshold
var engage_mult = 1.0            # --arb-engage: multiplier on the profile's engage weight
var never_still_scan = 1.0       # --arb-neverstill=0 ignores rows' still:"never" (control arm)
var aimed_full = 1.0             # --arb-aimedfull=0 restores the time discount for the
                                 # standing candidate (the pre-2026-08-25 pricing) as an
                                 # exact control arm
var cluster_near = ENGAGE_CLUSTER_NEAR # --arb-cnear: nearest-body pull share in cluster mode
var _escaping = false            # set by choose() each frame; read by _cost
# Per-frame character-profile state, resolved by world_view and unpacked once
# in choose() rather than dictionary-looked-up inside the 16+ candidate loop.
var _anchor_on = false
var _anchor = Vector2.ZERO
var _anchor_radius = 0.0
var _anchor_inner = 0.0
var _anchor_w = W_ANCHOR         # w_anchor x the row's anchor_w multiplier
# Orbit: a perimeter kit is herded from mid-arena into a corner in seconds
# (tracker Pacifist w7/w8: anc 790 -> 1150, edge 30, then contact hits) and
# the anchor term cannot stop it -- it prices END positions, so between two
# candidates it differs by ~13, the cost of one bullet. This term prices the
# DIRECTION at the current position once the bot is outside the outer radius:
# the outward radial component costs, the inward one pays, and the tangential
# component (kiting around the middle, which is how the character is played)
# earns half credit, all ramped by how far out we are. Row key "orbit" sets
# the weight; --arb-orbit=W overrides it for every row (0 = off, the control).
var _orbit_w = 0.0
var orbit_override = -1.0        # --arb-orbit
var _orbit_from = 0.0            # radius the orbit ramp starts at (row "orbit_from";
                                 # default the outer anchor_radius)
var orbit_from_override = -1.0   # --arb-orbitfrom
var last_anchor_dist = -1.0      # distance to the anchor this frame, for telemetry
var _engage = 0.0
var _never_still = false
var _fire_still = false
var _engage_cluster = false      # engage prices bodies-in-blast instead of nearest distance
# The explosion trade (Bull). Bull is priced like every other potato: each
# body in the pile is a separate contact hit, so three bodies in the blast
# cost ~48 to stand against while the dive reward tops out at 14, and the
# dive never happens. But Bull's FIRST hit detonates a 150 px explosion that
# kills everything killable in the blast -- the second and third hits from
# those bodies never arrive. So while the dive is armed (engage > 0, i.e.
# the HP band allows it) the contact costs of killable bodies that will be
# inside the blast at the END position pool and cap at ONE hit: the largest
# single coefficient among them, because that is the one that lands before
# the explosion resolves. Bodies outside the blast, unkillable ones, bullets
# and dashes all pay full price, so the dive is still vetoed by anything the
# explosion would not answer.
var _explode_trade = false
# -- The damage dive --
# The explosion trade only relieves KILLABLE bodies; anything that survives the
# blast (a 250 HP pursuer against a 156 blast) pays full contact price and a
# pile of them vetoes the dive outright. But a blast that does not kill still
# DEALS 156 to every body in it, and a Bull with a full bar can afford the
# exchange. So while the dive is armed, surviving bodies inside the blast pool
# too, and their cost is capped at DAMAGE_DIVE_HITS hits -- the one that
# detonates and the follow-up before the bot steps out -- provided (a) the bar
# is above DAMAGE_DIVE_HP, so two hits are survivable with margin, and (b) the
# blast's total damage across everything in it reaches DAMAGE_DIVE_MIN, so the
# exchange is worth having. Fail either and they pay full price as before.
# Bullets, dashes and elites are never in either pool.
var _damage_dive = false         # profile key damage_dive
var _hp_ratio = 1.0              # profile key hp_ratio (world_view computes it)
var _blast = 0.0                 # profile key blast: damage the explosion deals per body
const DAMAGE_DIVE_HP = 0.5       # bar needed to trade hits with bodies that live
const DAMAGE_DIVE_MIN = 350.0    # blast x bodies-in-blast that makes the trade worth it
const DAMAGE_DIVE_HITS = 2.0     # hits the surviving pile may bill: detonate + one more

const EXPLODE_KILLABLE_MIN = 0.5 # explode_trade admission: killability >= 0.5 means
                                 # hp <= kill_ref, i.e. the body DIES to one blast. The
                                 # general pool's 0.15 ("dies within ~6 s of fire") is
                                 # wrong here -- a body that survives the explosion keeps
                                 # hitting, and pricing it at "one hit" is what let 250 HP
                                 # pursuers bill the w11 horde dive as cheap
var _fight_room = 0.0            # px of wall room a candidate must END with to earn any
                                 # engage or kill reward. The One-Armed w10 timelines: at
                                 # full HP the brawler CHASED rim spawns into the wall band
                                 # (engage 8 + dps 14 outbid the wall term's ~13), sat there
                                 # unhurt for seconds, then took 33 -> 3 in eight. Rewards
                                 # that pull toward a wall are what cornered it; costs
                                 # stay untouched, so it still leaves
var _stand_ok = false            # fire_still AND not escaping AND wall room; gates every perk
var last_stand_ok = false        # read by the tap-mover: no taps while relocating off a wall
var last_engage = 0.0            # resolved contact-seeking weight this frame, for telemetry

var last_dir = Vector2.ZERO      # read for hysteresis and by telemetry
var last_still_gap = 0.0         # cost(stand) - cost(best); overlay only now
var last_stutter_gap = 0.0       # cost(best at stutter speed) - cost(best); the tap gate
var last_scores = []             # per-candidate cost, for the debug overlay
var last_dirs = []               # candidate directions matching last_scores
var last_best_index = -1
var last_escaping = false        # did the escape mode fire this frame (telemetry)
var pin_fires = 0                # escape activations this run, for the sweep
var _pin_hist = []               # recent positions, newest last
var _pin_frames = 0              # consecutive confirmed-stuck frames
var _pin_dwell = 0               # consecutive frames inside PIN_EDGE (dwell trigger)
var _pin_dwell_limit = 0         # frames of wall dwell that fire the escape; 0 = off
var tick_step = 1                # physics ticks this choose() call stands for (the
                                 # movement behaviour's decision interval); every pin
                                 # counter advances by it so the frame constants keep
                                 # meaning frames when decisions are skipped
var pin_dwell_override = 0       # --arb-pindwell: force the dwell limit for any pin row
var pin_leak = 0.0               # --arb-pinleak: wall-dwell decay when off the wall. Default
                                 # 0 = hard reset (dwell needs continuous wall time). Leaky
                                 # (1) lets a bot dodging in/out of the wall band accumulate
                                 # net dwell -- intuitive for bullet-hell corner deaths, but
                                 # A/B measured a WASH (Pacifist w8 6/6, w9 6/8, Soldier w12
                                 # 6/4, w4 7/?): kept as a knob only, not the default.
var _pin_ticks = 0               # frames of escape left to run

# Per-frame prepared threat data. Everything here is candidate-independent, so
# it is computed once instead of once per candidate -- with 29 candidates that
# is the difference between affording the wider action space and not.
var _p_pos = []                  # threat position
var _p_vel = []                  # threat velocity
var _p_rad = []                  # combined hit radius (threat + player body)
var _p_soft = []                 # squared radius past which a miss scores zero
var _p_coef = []                 # full damage coefficient: damage x kind x lethality x mitigation
var _p_still = []                # the same coefficient for the STANDING candidate;
                                 # differs only under fire_still, where standing
                                 # kills killable contact threats on their approach
var _p_kill = []                 # killability per threat (0 for non-contact); feeds
                                 # the damage-trade pool
var _p_mark = []                 # true for KIND_MARK: skipped by crowding/enclosure
var _p_aimed = []                # true for KIND_PROJ / KIND_DASH: a thing that flies at
                                 # us. The time discount below assumes a later frame
                                 # can still dodge it -- false for the STANDING
                                 # candidate, so it gets none (see the loop)
var _p_start = []                # wind-up delay
var _p_end = []                  # when it stops being dangerous, clamped to horizon
var _p_future = []               # where it will be at the horizon
var _p_far = []                  # where it will be at FAR_T (crowd runway)


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
	if d.has("taken"): pickup_taken = float(d["taken"])
	if d.has("hop"): hop_enable = float(d["hop"])
	if d.has("stand"): stand_mult = float(d["stand"])
	if d.has("standcommit"): stand_commit = float(d["standcommit"])
	if d.has("hyst"): w_hyst = float(d["hyst"])
	if d.has("lethality"): lethality_override = float(d["lethality"])
	if d.has("horizon"): horizon = float(d["horizon"])
	if d.has("roomcap"): room_cap = float(d["roomcap"])
	if d.has("roomfar"): w_room_far = float(d["roomfar"])
	if d.has("scandist"): scan_distance = max(float(d["scandist"]), 0.0)
	if d.has("pin"): pin_enable = float(d["pin"])
	if d.has("pindwell"): pin_dwell_override = int(d["pindwell"])
	if d.has("pinleak"): pin_leak = float(d["pinleak"])
	if d.has("orbit"): orbit_override = float(d["orbit"])
	if d.has("orbitfrom"): orbit_from_override = float(d["orbitfrom"])
	if d.has("pinthreat"): pin_threat = float(d["pinthreat"])
	if d.has("predict"): w_predict = float(d["predict"])
	if d.has("predsecs"): predict_secs = max(float(d["predsecs"]), 0.1)
	if d.has("tangent"): w_tangent = float(d["tangent"])
	if d.has("swerve"): wall_swerve = float(d["swerve"])
	if d.has("anchor"): w_anchor = float(d["anchor"])
	if d.has("trade"): trade_share = float(d["trade"])
	if d.has("floor"): fire_floor = float(d["floor"])
	if d.has("tradekill"): trade_killable_min = float(d["tradekill"])
	if d.has("engage"): engage_mult = float(d["engage"])
	if d.has("aimedfull"): aimed_full = float(d["aimedfull"])
	if d.has("neverstill"): never_still_scan = float(d["neverstill"])
	if d.has("cnear"): cluster_near = float(d["cnear"])
	if not d.empty():
		print("ARBITER weights: proj=%.2f contact=%.2f dash=%.2f aoe=%.2f latent=%.2f room=%.2f roomcap=%.0f wall=%.2f enclose=%.2f dps=%.2f pickup=%.2f hyst=%.2f lethality=%.2f horizon=%.2f pin=%.2f pinthreat=%.2f predict=%.2f predsecs=%.2f tangent=%.2f swerve=%.2f anchor=%.2f" % [
			w_proj, w_contact, w_dash, w_aoe, w_latent, w_room, room_cap, w_wall,
			w_enclose, w_dps, w_pickup, w_hyst, lethality, horizon, pin_enable, pin_threat,
			w_predict, predict_secs, w_tangent, wall_swerve, w_anchor])


# Returns the chosen unit direction, or ZERO to stand still.
#   threats:    array of threat tuples (see layout above)
#   rewards:    array of [pos, value_hp] pickup targets
#   targets:    array of enemy positions worth shooting
#   chargers:   array of idle-charger tuples (latent dash risk)
#   mitigation: expected share of incoming damage that actually lands (dodge, armor)
func choose(p0: Vector2, speed: float, body_radius: float, far: Vector2,
		threats: Array, rewards: Array, targets: Array, chargers: Array,
		weapon_range: float, prefers_still: bool, current_hp: float,
		mitigation: float, profile: Dictionary = {}) -> Vector2:

	var edge = min(min(p0.x, far.x - p0.x), min(p0.y, far.y - p0.y))
	var escaping = false
	_fire_still = profile.get("fire_still", false)    # read by _update_pin's dwell trigger
	# Pin escape arms globally via --arb-pin, or per character via the profile:
	# a stand-and-shoot kit gets cornered by its own best behaviour (the stand
	# holds while the crowd closes the exits), so for those characters the
	# escape mode is part of the profile, not an experiment flag.
	if pin_enable != 0.0 or profile.get("pin", false):
		_pin_dwell_limit = int(profile.get("pin_dwell", PIN_DWELL if _fire_still else 0))
		if pin_dwell_override > 0:
			_pin_dwell_limit = pin_dwell_override
		escaping = _update_pin(p0, speed, edge)
	last_escaping = escaping
	_escaping = escaping         # read by _cost for the tangent reward
	# One flag for every stand perk: fire_still, not escaping, and enough wall
	# room that the stand cannot become the corner (see FIRE_STILL_WALL_MIN).
	_stand_ok = _fire_still and not escaping and edge >= FIRE_STILL_WALL_MIN
	last_stand_ok = _stand_ok

	_anchor_on = profile.has("anchor") and w_anchor > 0.0
	_anchor = profile.get("anchor", Vector2.ZERO)
	_anchor_radius = float(profile.get("anchor_radius", 0.0))
	_anchor_inner = float(profile.get("anchor_inner", 0.0))
	_anchor_w = w_anchor * float(profile.get("anchor_w", 1.0))
	_pickup_radius = float(profile.get("pickup_radius", 0.0))
	lethality = float(profile.get("lethality", LETHALITY))
	if lethality_override >= 0.0:
		lethality = lethality_override
	_stand_income = float(profile.get("stand_income", 0.0)) * stand_mult
	_stand_progress = float(profile.get("stand_progress", 0.0))
	last_stand = _stand_income
	_orbit_w = float(profile.get("orbit", 0.0))
	if orbit_override >= 0.0:
		_orbit_w = orbit_override
	_orbit_from = float(profile.get("orbit_from", _anchor_radius))
	if orbit_from_override >= 0.0:
		_orbit_from = orbit_from_override
	last_anchor_dist = p0.distance_to(_anchor) if _anchor_on else -1.0
	_engage = float(profile.get("engage", 0.0)) * engage_mult
	last_engage = _engage        # public mirror for telemetry (get() on _engage returns null)
	_engage_cluster = profile.get("engage_cluster", false)
	_fight_room = float(profile.get("fight_room", 0.0))
	_explode_trade = profile.get("explode_trade", false)
	_damage_dive = profile.get("damage_dive", false)
	_hp_ratio = float(profile.get("hp_ratio", 1.0))
	_blast = float(profile.get("blast", 0.0))
	_never_still = profile.get("never_still", false) and never_still_scan != 0.0
	_fire_still = profile.get("fire_still", false)

	# Scaled BEFORE _prepare, deliberately: the per-kind weight is baked into
	# _p_coef in there (see the kw assignment), so discounting these afterwards
	# would compile cleanly, change nothing, and hand back a convincing null.
	#
	# Caution and pin escape both live here and COMPOSE. Caution is a standing
	# character trait -- how much room this potato needs -- while the pin
	# discount is a momentary "accept damage to get out of this corner". One
	# save covers both, so a restore cannot miss a weight the other touched.
	# Note caution multiplies only the THREAT weights: scaling room/wall too
	# would turn a cautious character into a centre-hugging one, which is a
	# different (and mostly wrong) behaviour.
	var caution = float(profile.get("caution", 1.0))
	var dps_scale = float(profile.get("dps", 1.0))
	var scaled = escaping or caution != 1.0 or dps_scale != 1.0
	var saved = []
	if scaled:
		saved = [w_proj, w_contact, w_dash, w_aoe, w_latent, w_dps, w_room, w_wall]
	if caution != 1.0:
		w_proj *= caution
		w_contact *= caution
		w_dash *= caution
		w_aoe *= caution
		w_latent *= caution
	if dps_scale != 1.0:
		# Weaponless kits (Bull) and kits that cannot kill (Pacifist): the kill
		# reward would only drag them toward things they have no way to shoot.
		w_dps *= dps_scale
	if escaping:
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

	# Hops (see HOP_FRAC): half-speed headings, offered only near a telegraph
	# or a dash and never while escaping a pin (that flight wants every frame).
	var hop_first = cands.size()
	if hop_enable != 0.0 and _hop_wanted and not escaping:
		for k in range(HOP_DIRS):
			var a = k * TAU / HOP_DIRS + TAU / (2 * HOP_DIRS)   # offset from the full set
			var hd = Vector2(cos(a), sin(a))
			var c = _cost(hd, p0, speed * HOP_FRAC, body_radius, far, rewards, targets,
					chargers, weapon_range, prefers_still, current_hp)
			cands.push_back(hd)
			scores.push_back(c)
			if c < best_cost:
				best_cost = c
				best_i = cands.size() - 1
	last_hop = best_i >= hop_first
	var best_speed = speed * HOP_FRAC if last_hop else speed

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
				var c = _cost(rc, p0, best_speed, body_radius, far, rewards, targets,
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
	# How much worse STANDING scored than the chosen move. Kept for the
	# overlay; the tap-mover no longer gates on it, because a stutter is not
	# a stand: it is the chosen move at reduced speed, and pricing it as a
	# full-horizon stop made every flight look uninterruptible when the real
	# cost of a two-frame volley is ~12 px of separation. The ZERO candidate
	# always sits at index DIRS in the initial sweep.
	last_still_gap = scores[DIRS] - best_cost
	# The stutter's TRUE cost: the winning heading scored again at the net
	# speed the tap cycle actually delivers, minus the full-speed score. Same
	# scorer, same threats, same dodge simulation -- only the distance covered
	# changes -- so a pursuer about to connect prices the slowdown as lethal
	# and a swarm still 300 px out prices it as nearly free. Standing needs
	# no stutter (it already fires), so the gap is zero there.
	last_stutter_gap = 0.0
	if _fire_still and best_dir != Vector2.ZERO:
		last_stutter_gap = _cost(best_dir, p0, speed * STUTTER_SPEED_FRAC, body_radius,
				far, rewards, targets, chargers, weapon_range, prefers_still,
				current_hp) - best_cost

	if scaled:
		w_proj = saved[0]
		w_contact = saved[1]
		w_dash = saved[2]
		w_aoe = saved[3]
		w_latent = saved[4]
		w_dps = saved[5]
		w_room = saved[6]
		w_wall = saved[7]
	return best_dir


# How long can this velocity be held before the arena stops producing
# displacement? Walls SLIDE (the engine cancels only the crossing component),
# so motion dies when EVERY moving axis has exhausted its room: straight at a
# wall stops on contact (no slide component), a diagonal dies at the corner
# (max of the two axis times), parallel to a wall runs forever. An axis with
# no velocity contributes nothing -- it neither runs out nor rescues.
func _runway(p0: Vector2, vel: Vector2, body_radius: float, far: Vector2) -> float:
	var t = 0.0
	if vel.x > 0.0:
		t = max(t, (far.x - body_radius - p0.x) / vel.x)
	elif vel.x < 0.0:
		t = max(t, (p0.x - body_radius) / -vel.x)
	if vel.y > 0.0:
		t = max(t, (far.y - body_radius - p0.y) / vel.y)
	elif vel.y < 0.0:
		t = max(t, (p0.y - body_radius) / -vel.y)
	return t


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
		_pin_ticks -= tick_step
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
		var could = speed * float(PIN_WINDOW * tick_step) / 60.0
		stuck = travelled < could * PIN_TRAVEL_FRAC
	if stuck:
		_pin_frames += tick_step
	else:
		_pin_frames = 0

	# Wall dwell: the tap-mover's trigger (see PIN_DWELL), and any row's that
	# sets pin_dwell (see the note above PIN_TICKS).
	if _pin_dwell_limit > 0 and edge < PIN_EDGE:
		_pin_dwell += tick_step
	elif _pin_dwell_limit > 0:
		# Leaky, not a hard reset: a bot dodging in and out of the wall band
		# still accumulates net dwell (see pin_leak).
		_pin_dwell = max(_pin_dwell - int(ceil(pin_leak * tick_step)), 0)

	if _pin_frames >= PIN_CONFIRM or (_pin_dwell_limit > 0 and _pin_dwell >= _pin_dwell_limit):
		_pin_frames = 0
		_pin_dwell = 0
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
	_p_still = []
	_p_kill = []
	_p_mark = []
	_p_aimed = []
	_p_start = []
	_p_end = []
	_p_future = []
	_p_far = []

	var inv_hp = 1.0 / max(current_hp, 1.0)
	var reach = speed * horizon          # everything we could possibly walk to
	_hop_wanted = false
	last_aoe_n = 0
	var hop_sq = HOP_RANGE * HOP_RANGE

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
		elif kind == KIND_AOE or kind == KIND_MARK:
			kw = w_aoe
		_p_mark.push_back(kind == KIND_MARK)
		_p_aimed.push_back(kind == KIND_PROJ or kind == KIND_DASH)
		if (kind == KIND_AOE or kind == KIND_DASH) and pos.distance_squared_to(p0) < hop_sq:
			_hop_wanted = true
		if kind == KIND_AOE:
			last_aoe_n += 1

		_p_pos.push_back(pos)
		_p_vel.push_back(vel)
		_p_rad.push_back(radius)
		_p_soft.push_back(soft * soft)
		var coef = dmg * kw * t[T_TICKS] * lethal * mitigation
		_p_coef.push_back(coef)
		var still_coef = coef
		var kill = 0.0
		# not _escaping: while pinned, every stand-to-shoot perk yields -- the
		# override the cornering deaths asked for is "escape at the loss of
		# firing", so an escaping Soldier prices threats like anyone else.
		if (_stand_ok or _explode_trade) and t.size() > T_KILL:
			kill = float(t[T_KILL])
			if _stand_ok:
				still_coef = coef * (1.0 - FIRE_STILL_KILL * kill)
		_p_still.push_back(still_coef)
		_p_kill.push_back(kill)
		_p_start.push_back(t[T_START])
		_p_end.push_back(t_end)
		_p_future.push_back(pos + vel * span)
		_p_far.push_back(pos + vel * max(FAR_T - t[T_START], 0.0))


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
	# THE DODGE SIMULATION MUST USE THE VELOCITY THE WALL PERMITS. p_end is
	# clamped, but the threat pass used to integrate with the raw v -- so a
	# candidate aimed INTO a wall was priced as if it dodged at full speed for
	# the whole horizon, when it actually stops on contact. The bot walked
	# into walls believing it was dodging, and mom collected (87% of her hits
	# at edge < 150, on a bot that thought it was moving). With the effective
	# velocity, into-wall headings lose their phantom dodge value and lateral
	# ones keep full speed, so the swerve along the wall wins the vote by
	# itself. Away from walls v_eff == v exactly; --arb-swerve=0 reverts.
	var v_eff = v
	if wall_swerve != 0.0:
		v_eff = (p_end - p0) / horizon
	var total = 0.0

	var room = room_cap
	var enc_sum = Vector2.ZERO
	var enc_w = 0.0
	var enclose_sq = ENCLOSE_RADIUS * ENCLOSE_RADIUS
	# Crowd runway (see FAR_T): our position FAR_T out along this bearing,
	# wall-clamped like p_end, against the threats extrapolated as far.
	var far_room = ROOM_FAR_CAP
	var far_sq = ROOM_FAR_CAP * ROOM_FAR_CAP
	var p_far = p0 + v_eff * FAR_T
	p_far.x = clamp(p_far.x, body_radius, far.x - body_radius)
	p_far.y = clamp(p_far.y, body_radius, far.y - body_radius)
	var want_far = w_room_far > 0.0 and d != Vector2.ZERO
	# Crowding may be felt further out than enclosure is; scan to whichever
	# reaches further so raising room_cap past ENCLOSE_RADIUS is not a no-op.
	var scan_sq = max(enclose_sq, room_cap * room_cap)

	var trade_sum = 0.0          # standing's pooled cost from killable bodies
	var blast_sum = 0.0          # explode_trade: pooled cost of killable bodies in the blast
	var blast_max = 0.0          # ...and the single largest of them (the hit that detonates)
	var blast_n = 0              # bodies the blast kills
	var hurt_sum = 0.0           # damage dive: pooled cost of bodies the blast only HURTS
	var hurt_max = 0.0
	var hurt_n = 0
	var blast_sq = ENGAGE_BLAST * ENGAGE_BLAST

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
			var w = _p_pos[i] - (p0 + v_eff * t_start)
			var rel = _p_vel[i] - v_eff
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
					if d == Vector2.ZERO and _p_aimed[i] and aimed_full != 0.0:
						# STANDING against something aimed at us: the discount's
						# premise -- "a later frame can still dodge this" -- is
						# exactly what the stand refuses to do, so the hit is
						# certain and prices at full. Without this a 200 px/s
						# Abyss bullet 300 px out cost a Soldier's stand ~4 against
						# a 16-point floor; both w5 deaths were bullets taken at
						# mv=(0,0) with two seconds of warning.
						discount = 1.0
					# The standing candidate prices killable contact bodies at
					# a discount (see FIRE_STILL_KILL): a stand that SHOOTS the
					# approacher is not the same stand that receives it. Their
					# costs also POOL into the damage-trade budget below rather
					# than summing unbounded -- a whole crowd of killable trash
					# can only bill the stand up to the budget, because most of
					# that crowd will be dead before it collects.
					var cost_i = (_p_still[i] if d == Vector2.ZERO else _p_coef[i]) * hit * discount
					if d == Vector2.ZERO and _fire_still and _p_kill[i] > trade_killable_min:
						trade_sum += cost_i
					elif _explode_trade and _engage > 0.0 and _p_kill[i] >= EXPLODE_KILLABLE_MIN \
							and _p_future[i].distance_squared_to(p_end) < blast_sq:
						blast_sum += cost_i
						blast_n += 1
						if cost_i > blast_max:
							blast_max = cost_i
					elif _damage_dive and _engage > 0.0 and _p_kill[i] > 0.0 \
							and _p_future[i].distance_squared_to(p_end) < blast_sq:
						# a contact body (_p_kill > 0) the blast will not kill
						hurt_sum += cost_i
						hurt_n += 1
						if cost_i > hurt_max:
							hurt_max = cost_i
					else:
						total += cost_i

		# --- Where this leaves us ---
		# One pass serves both terminal terms: the offset to the threat's future
		# position gives crowding, and its direction gives enclosure.
		if _p_mark[i]:
			continue    # a spawn marker takes up no room and blocks no heading
		if want_far:
			var offf = _p_far[i] - p_far
			var dff = offf.length_squared()
			if dff < far_sq:
				var edge_far = sqrt(dff) - _p_rad[i]
				if edge_far < far_room:
					far_room = edge_far
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
		var room_cost = w_room * (1.0 - max(room, 0.0) / room_cap)
		if _stand_ok and d == Vector2.ZERO:
			room_cost *= FIRE_STILL_CROWD    # the stand thins the crowd it sits in
		elif _explode_trade and _engage > 0.0:
			room_cost *= EXPLODE_CROWD       # the dive WANTS the crowd it ends in
		total += room_cost
	if want_far and far_room < ROOM_FAR_CAP:
		total += w_room_far * (1.0 - max(far_room, 0.0) / ROOM_FAR_CAP)

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

	# Predictive wall avoidance: price the bearing's RUNWAY (see const block).
	# Quadratic ramp so a bearing with 2.4 s of room is a whisper and one with
	# 0.5 s shouts; standing still has no bearing and pays nothing here --
	# refusing to move is already priced by the threat terms.
	if w_predict > 0.0 and d != Vector2.ZERO:
		var run_t = _runway(p0, v, body_radius, far)
		if run_t < predict_secs:
			var short = 1.0 - run_t / predict_secs
			total += w_predict * short * short

	# Escape ALONG the wall, not off it. Only while the pin-escape mode is
	# active: the radial exit is where the herding swarm stands, the lateral
	# one is usually open, and no other term can tell them apart. Rewards the
	# candidate's component parallel to the NEAREST wall, ramped by proximity
	# measured at the CURRENT position -- the pin is where we are, not where
	# the candidate ends. The wrong tangent sense (into a corner's second
	# wall) is not special-cased: that bearing dead-ends and points into
	# threats, so the surviving terms veto it; this reward just breaks the
	# radial-vs-nothing tie toward lateral motion.
	if _escaping and w_tangent > 0.0 and d != Vector2.ZERO:
		var near_v = min(p0.x, far.x - p0.x)     # nearest vertical wall
		var near_h = min(p0.y, far.y - p0.y)     # nearest horizontal wall
		var near_w = min(near_v, near_h)
		if near_w < TANGENT_RADIUS:
			var along = abs(d.y) if near_v <= near_h else abs(d.x)
			total -= w_tangent * (1.0 - near_w / TANGENT_RADIUS) * along

	if trade_sum > 0.0:
		# The damage trade: killable-crowd contact bills the stand at most this
		# much. Uncapped, ten 90%-killable bodies still summed past any reward
		# and the bot fled forever; capped, the stand pays a bounded fee and the
		# volley thins the crowd that was charging it. Shrinks with the bar.
		total += min(trade_sum, current_hp * trade_share)
	if blast_sum > 0.0:
		# The explosion trade: the pile in the blast costs ONE hit, not N.
		total += min(blast_sum, blast_max)
	if hurt_sum > 0.0:
		# The damage dive: bodies that survive the blast bill at most two hits
		# -- but only when the bar can take them and the blast is worth it.
		var worth = _blast * float(blast_n + hurt_n)
		if _hp_ratio >= DAMAGE_DIVE_HP and worth >= DAMAGE_DIVE_MIN:
			total += min(hurt_sum, hurt_max * DAMAGE_DIVE_HITS)
		else:
			total += hurt_sum

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
		var enc_cost = w_enclose * (1.0 - enc_sum.length() / enc_w)
		if _stand_ok and d == Vector2.ZERO:
			# same reasoning as the room share above; ungated this would halve
			# the very term the escape uses to find the open side
			enc_cost *= FIRE_STILL_CROWD
		elif _explode_trade and _engage > 0.0:
			enc_cost *= EXPLODE_CROWD
		total += enc_cost

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
	# Fight-room gate (see _fight_room): a candidate ending inside the wall
	# band earns neither the kill reward nor the engage pull.
	var fight_ok = true
	if _fight_room > 0.0:
		var end_edge = min(min(p_end.x, far.x - p_end.x), min(p_end.y, far.y - p_end.y))
		fight_ok = end_edge >= _fight_room

	var kill_gain = 0.0
	for t in targets:
		if not fight_ok:
			break
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
		var dps_pay = w_dps * (1.0 - exp(-kill_gain / KILL_SOFT))
		if _fire_still:
			# Soldier's weapons DO NOT FIRE while moving, and pricing a moving
			# candidate as if they did is what made the bot kite itself to
			# death: fleeing "in range" earned the same reward as standing, the
			# scorer saw kiting as free DPS, nothing died, and the wave ground
			# it down. So the payout follows the mechanic -- standing collects
			# double (the kit's +50% damage and +50% attack speed while still),
			# a moving candidate keeps only a sliver, which is not a firing
			# reward at all but the approach gradient: without it, nothing
			# would ever pull the bot into range to take its stand.
			var pay = dps_pay * (FIRE_STILL_STAND if d == Vector2.ZERO else FIRE_STILL_MOVE)
			if d == Vector2.ZERO and _stand_ok and pay < fire_floor:
				# The scaled payout alone measured as no stillness at all
				# (~8-12% still-frames, same as the control): trash waves carry
				# tiny kill_gain, so doubling it yields ~3 -- less than the
				# room term's standing wander pressure, and the bot strolled
				# while its guns were silent. Standing with ANYTHING actually
				# shootable from here (true weapon range, not the acquire
				# band) is worth a flat floor that beats wander and still
				# loses to every live threat.
				var wr_sq = weapon_range * weapon_range
				for t in targets:
					if p_end.distance_squared_to(t[TG_POS]) <= wr_sq:
						pay = fire_floor
						break
			total -= pay
		else:
			total -= dps_pay
			if prefers_still and d == Vector2.ZERO:
				# Structure characters that PREFER standing but whose damage
				# does not stop when they walk: standing is just where their
				# damage term pays out twice.
				total -= dps_pay

	# Standing income (Streamer, see world_view stand_income): the stand earns
	# the tick for the whole horizon; any move forfeits the part of the current
	# second already stood -- the "every twitch resets the tick" rule.
	if _stand_income > 0.0:
		if d == Vector2.ZERO:
			total -= _stand_income * horizon
		elif last_dir == Vector2.ZERO:
			total += _stand_income * (_stand_progress + stand_commit)   # breaking a stand
		else:
			total += _stand_income * _stand_progress

	for r in rewards:
		# Attracted rewards (drops, food) are taken at the attract rim, so the
		# distance that matters is to the rim; a felled reward (tree, r[2]
		# false) still has to be reached. A HELD reward (r[3] = its own rim,
		# e.g. a dead scapegoat's revive zone) pays its value to every move
		# that ENDS inside the rim, so standing in it keeps earning and
		# stepping out costs the same -- that is what makes the bot stay the
		# three seconds a revive takes.
		var held = r.size() > 3 and float(r[3]) > 0.0
		var rim = float(r[3]) if held else (_pickup_radius if (r.size() < 3 or r[2]) else 0.0)
		var d0 = max(p0.distance_to(r[0]) - rim, 0.0)
		var d1 = max(p_end.distance_to(r[0]) - rim, 0.0)
		var closed = (d0 - d1) / max(speed * horizon, 1.0)   # -1..1, share of the move spent approaching
		var gain = w_pickup * r[1] * closed / (1.0 + d0 / PICKUP_FALLOFF)
		if held:
			if d1 == 0.0:
				gain += w_pickup * r[1]                      # inside the zone: keep earning
		elif d1 == 0.0 and d0 > 0.0:
			gain += w_pickup * r[1] * pickup_taken           # this move collects it
		total -= gain

	# --- Character anchor ---
	# Priced at the candidate's END position. Between the two radii every
	# candidate scores the same zero and the anchor exerts no force at all,
	# which is what keeps dodging free inside the band; outside it, the
	# candidate that ends nearer the band is linearly cheaper.
	if _anchor_on:
		var from_anchor = p_end.distance_to(_anchor)
		if _anchor_radius > 0.0:
			var strayed = from_anchor - _anchor_radius
			if strayed > 0.0:
				total += _anchor_w * min(strayed / ANCHOR_NORM, ANCHOR_CAP)
		if _anchor_inner > 0.0:
			var intruded = _anchor_inner - from_anchor
			if intruded > 0.0:
				total += _anchor_w * min(intruded / ANCHOR_NORM, ANCHOR_CAP)
		# Orbit (see _orbit_w): direction pricing while outside the band
		if _orbit_w > 0.0 and _orbit_from > 0.0 and d != Vector2.ZERO:
			var radial = p0 - _anchor
			var dist = radial.length()
			var out_frac = clamp((dist - _orbit_from) / ANCHOR_NORM, 0.0, 1.0)
			if out_frac > 0.0 and dist > 1.0:
				var ru = radial / dist
				var outward = d.dot(ru)                      # +1 straight away from home
				var along = abs(d.dot(Vector2(-ru.y, ru.x)))  # kiting around it
				total += _orbit_w * out_frac * (outward - 0.5 * along)

	# --- Contact seeking ---
	# Cost for ENDING far from the nearest thing worth touching, which makes
	# closing the distance the cheaper candidate. Capped, so one straggler
	# across the arena cannot drag the bot through everything in between.
	if _engage > 0.0 and fight_ok and not targets.empty():
		var near_sq = 1e18
		var in_blast = 0    # blast_sq is declared at the top of the threat loop
		for t in targets:
			if _engage_cluster and t.size() > TG_BOSS and t[TG_BOSS]:
				continue    # a boss is never part of the pile worth diving into
			var dsq = p_end.distance_squared_to(t[TG_POS])
			if dsq < near_sq:
				near_sq = dsq
			if dsq < blast_sq:
				in_blast += 1
		if _engage_cluster:
			# Reward PER BODY inside the blast at the END position (see
			# ENGAGE_CLUSTER_CAP), plus a reduced pull toward the nearest body
			# so a pile can get started.
			total -= _engage * min(float(in_blast), ENGAGE_CLUSTER_CAP)
			if near_sq < 1e17:
				total += _engage * cluster_near * min(sqrt(near_sq) / ENGAGE_NORM, ENGAGE_CAP)
		else:
			total += _engage * min(sqrt(near_sq) / ENGAGE_NORM, ENGAGE_CAP)

	# --- Standing still as a mechanical penalty ---
	if _never_still and d == Vector2.ZERO:
		total += NEVER_STILL_COST

	# --- Continuity ---
	# One hysteresis term in the arbiter does the job that five separate commit
	# timers did in the field controller, and it cannot deadlock: a threat that
	# actually appears outscores the bonus immediately.
	if last_dir != Vector2.ZERO and d != Vector2.ZERO:
		var agree = d.dot(last_dir)
		total -= w_hyst * agree
		if agree < -0.5:
			total += W_REVERSE * (-agree)
	elif last_dir == Vector2.ZERO and d == Vector2.ZERO:
		# Stillness is a HEADING and gets the same stickiness as any other, or it
		# is the one choice the bot can flicker out of for free. That flicker is
		# not cosmetic: Streamer's income needs a full unbroken second standing
		# and every twitch resets the tick, while Soldier and Engineer lose a
		# firing window to a step they had no reason to take.
		total -= w_hyst
	elif prefers_still and last_dir != Vector2.ZERO and d == Vector2.ZERO:
		# The other half of tap-moving. Mid-dodge, the hysteresis reward above
		# hands every keep-going candidate ~w_hyst that STOPPING does not get, so
		# a stand-still character pays a tax on the very move its kit is built
		# around -- the dodge stretches a body-length past where the threat
		# cleared, and Soldier spends that distance not firing. Pricing the stop
		# level with continuing lets the tap end the instant the threat term no
		# longer demands motion; while one does, 15-65 beats 1.2 regardless.
		total -= w_hyst

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
