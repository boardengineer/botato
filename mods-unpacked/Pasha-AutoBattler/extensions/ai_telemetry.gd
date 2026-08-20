extends Node

# Temporary debug telemetry for tuning the AutoBattler bot.
# Prints compact BOTLOG lines to stdout (visible in the console / captured
# log file) while a wave is running and the bot is enabled.
# Debug builds only; safe to delete this file and its add_child in main.gd.

const INTERVAL = 1.0

var _accum = INTERVAL
var _hooked_player = null
var _death_logged = false
var _damage_taken_this_wave = 0.0
var _last_wave = - 1
var _last_threats = ""
var _boss_state_cache = {}


func _process(delta):
	if not OS.is_debug_build():
		return
	# Boss dash cycles (croc: ~1 s windup+dash+cooldown) fit entirely between
	# 1 Hz ticks — log state transitions every frame instead
	_track_boss_dashes()
	_accum += delta
	if _accum < INTERVAL:
		return
	_accum = 0.0
	_tick()


func _track_boss_dashes():
	if not _bot_active():
		return
	var main = get_parent()
	if main._players.empty():
		return
	var player = main._players[0]
	if not is_instance_valid(player) or player.dead:
		return
	for boss in main._entity_spawner.bosses:
		if not is_instance_valid(boss) or boss.dead or boss._pending_die:
			continue
		var state = "idle"
		if boss._move_locked:
			state = "dashing"
		elif not boss._can_move:
			state = "windup"
		var key = boss.get_instance_id()
		if _boss_state_cache.get(key, "") != state:
			_boss_state_cache[key] = state
			print("BOTLOG DASH boss=%s state=%s d=%d pos=%s" % [
				boss.enemy_id, state, int(boss.position.distance_to(player.position)),
				_fmt_pos(player.position)])


# Largest weave amplitude among a bullet hell's generators. That is the number
# that drives threat geometry: 50 is a wobble, 600 is a bullet that crosses the
# arena sideways while travelling.
func _bh_amplitude(bh) -> float:
	var best = 0.0
	for gen in bh.get_children():
		if not ("sinusoidal_motion" in gen):
			continue
		var a = gen.sinusoidal_motion.length()
		if a > best:
			best = a
	return best


func _bot_active() -> bool:
	var options = get_node_or_null("/root/AutobattlerOptions")
	if options == null:
		return false
	return options.enable_autobattler


func _tick():
	var main = get_parent()
	if not _bot_active():
		return
	if main._players.empty():
		return
	var player = main._players[0]
	if not is_instance_valid(player):
		return

	_hook_player(player)

	if RunData.current_wave != _last_wave:
		_last_wave = RunData.current_wave
		_damage_taken_this_wave = 0.0
		_death_logged = false
		_boss_state_cache.clear()
		# Which bullet-hell variant this wave rolled. main.gd picks it with
		# pick_random(), so it is not recorded in the snapshot -- but the
		# variants differ 12x in weave amplitude (50 to +-600), which changes
		# the threat geometry enormously. Without this line a sweep cannot say
		# whether it actually covered the violent variants or only the mild ones.
		var projectiles = main.get_node_or_null("EnemyProjectiles")
		if projectiles:
			for child in projectiles.get_children():
				if child is BulletHell:
					print("BOTLOG BULLETHELL wave=%d variant=%s amp=%.0f speed=%.0f" % [
						RunData.current_wave, child.name, _bh_amplitude(child),
						child.projectile_speed])
					break

	if player.dead:
		if not _death_logged:
			_death_logged = true
			var threats = _nearby_threats(main, player, 3)
			if threats == "":
				threats = "last-seen: " + _last_threats
			print("BOTLOG DEATH wave=%d pos=%s dmg_this_wave=%d threats=[%s]" % [
				RunData.current_wave, _fmt_pos(player.position),
				int(_damage_taken_this_wave), threats])
		return

	if main._cleaning_up or main._wave_timer.time_left <= 0.05:
		return

	var spawner = main._entity_spawner
	var far = ZoneService.current_zone_max_position
	var edge = min(min(player.position.x, far.x - player.position.x),
			min(player.position.y, far.y - player.position.y))

	var near_enemy = _nearest_distance(spawner.enemies, player.position)
	var charging = _count_charging(spawner.enemies, player.position) \
			+ _count_charging(spawner.bosses, player.position)

	var proj_count = 0
	var projectiles = main.get_node_or_null("EnemyProjectiles")
	if projectiles:
		for p in projectiles.get_children():
			if p is Projectile and p._hitbox and p._hitbox.active:
				proj_count += 1

	var boss_txt = ""
	for boss in spawner.bosses:
		if boss.dead or boss._pending_die:
			continue
		var d = int(boss.position.distance_to(player.position))
		var state = "idle"
		if boss._move_locked:
			state = "dashing"
		elif not boss._can_move:
			state = "windup"
		boss_txt += "%s(d=%d,hp=%d,st=%d,%s) " % [
			boss.enemy_id, d, int(boss.current_stats.health), boss._current_state, state]

	# esc bitmask: +1 gap escape, +2 wave counter-steer, +4 crossfire exit,
	# +8 AoE-cluster flee, +16 single-corridor charge dodge, +32 bullet dodge,
	# +64 pillar-field navigation
	var move_behavior = player._movement_behavior
	var esc = _esc_bits(move_behavior)
	# corr = corridors actually threatening us last frame (charging= counts
	# map-wide chargers and routinely overstates)
	var corr = 0
	if move_behavior and "last_corridor_count" in move_behavior:
		corr = move_behavior.last_corridor_count

	_last_threats = _nearby_threats(main, player, 3)

	# Arbiter runs: esc bits are meaningless (it has no subsystems), so report
	# the decision itself — chosen heading and how much better it scored than
	# the runner-up. A margin near zero every tick means the action space is
	# too coarse or the weights are not separating candidates.
	if move_behavior and ("arbiter_active" in move_behavior) and move_behavior.arbiter_active:
		var arb = move_behavior._arbiter
		var margin = 0.0
		var chosen = Vector2.ZERO
		if arb:
			chosen = arb.last_dir
			# Margin against the best CLEARLY DIFFERENT heading (>45 deg away).
			# Comparing to the overall runner-up says nothing: the refinement
			# candidates sit 11 deg off the winner and are near-ties by
			# construction. What matters is how strongly one region of the
			# compass is preferred over another.
			var best = 1e18
			for s in arb.last_scores:
				if s < best:
					best = s
			var rival = 1e18
			for i in range(arb.last_scores.size()):
				var d = arb.last_dirs[i]
				if d == Vector2.ZERO or chosen == Vector2.ZERO or d.dot(chosen) > 0.7:
					continue
				if arb.last_scores[i] < rival:
					rival = arb.last_scores[i]
			if rival < 1e17:
				margin = rival - best
		# eff is path efficiency over the last second: 1.0 = held a heading,
		# low = the decision oscillated and most of the movement cancelled out.
		var hs = [0.0, 0.0, 0, 0, 0]
		if move_behavior.has_method("take_heading_stats"):
			hs = move_behavior.take_heading_stats()
		print("BOTLOG ARB wave=%d hp=%d/%d pos=%s mv=(%.2f,%.2f) margin=%.2f threats=%d nearE=%d proj=%d edge=%d dmgW=%d eff=%.2f turn=%.1f flips=%d frames=%d still=%d" % [
			RunData.current_wave, int(player.current_stats.health), int(player.max_stats.health),
			_fmt_pos(player.position), chosen.x, chosen.y, margin,
			spawner.enemies.size(), int(near_enemy), proj_count, int(edge),
			int(_damage_taken_this_wave), hs[0], hs[1], hs[2], hs[3], hs[4]])
		return

	print("BOTLOG t=%d wave=%d hp=%d/%d pos=%s enemies=%d nearE=%d proj=%d charging=%d corr=%d edge=%d dmgW=%d esc=%d %s" % [
		int(main._wave_timer.wait_time - main._wave_timer.time_left),
		RunData.current_wave,
		int(player.current_stats.health), int(player.max_stats.health),
		_fmt_pos(player.position),
		spawner.enemies.size(), int(near_enemy), proj_count, charging, corr,
		int(edge), int(_damage_taken_this_wave), esc, boss_txt])


func _esc_bits(move_behavior) -> int:
	var esc = 0
	if move_behavior:
		if ("escaping" in move_behavior) and move_behavior.escaping:
			esc += 1
		if ("countering" in move_behavior) and move_behavior.countering:
			esc += 2
		if ("crossfiring" in move_behavior) and move_behavior.crossfiring:
			esc += 4
		if ("aoe_fleeing" in move_behavior) and move_behavior.aoe_fleeing:
			esc += 8
		if ("dodging" in move_behavior) and move_behavior.dodging:
			esc += 16
		if ("proj_dodging" in move_behavior) and move_behavior.proj_dodging:
			esc += 32
		if ("pillar_navigating" in move_behavior) and move_behavior.pillar_navigating:
			esc += 64
		if ("cautious" in move_behavior) and move_behavior.cautious:
			esc += 128
		if ("wall_lapping" in move_behavior) and move_behavior.wall_lapping:
			esc += 256
	return esc


func _hook_player(player):
	if _hooked_player == player:
		return
	_hooked_player = player
	var _err = player.connect("took_damage", self, "_on_player_took_damage")


func _on_player_took_damage(_unit, value, _kb, _is_crit, is_dodge, is_protected, _armor, args, _hit_type, _one_shot):
	if not _bot_active():
		return
	if is_dodge or is_protected:
		return
	_damage_taken_this_wave += value
	# Classify the source NOW — the TakeDamageArgs instance is reused by the
	# engine, so it is only valid synchronously inside this handler. hit_type
	# is useless here (always NORMAL for the player); the hitbox owner isn't.
	var src = "?"
	if args and args.hitbox:
		var hb_parent = args.hitbox.get_parent()
		if hb_parent is Projectile:
			# A Pivot-mounted orbiter never sets `velocity`, so it logs as
			# proj(v=0) -- indistinguishable from an invoker pillar, which makes
			# the two impossible to separate in a sweep. Label it by its parent.
			if hb_parent.get_parent() is Pivot:
				src = "orbiter"
			# v~0 = pillar/AoE; a just-stopped bullet may also read 0, so print
			# the number instead of guessing a label
			else:
				src = "proj(v=%d)" % int(hb_parent.velocity.length())
			# Frame-accurate impact geometry: the 1 Hz tick misses sub-second
			# dodge commits, so record what the bot was DOING at this instant
			if _hooked_player and is_instance_valid(_hooked_player) and not _hooked_player.dead:
				var mb = _hooked_player._movement_behavior
				var mv = Vector2.ZERO
				if mb and ("last_move_dir" in mb):
					mv = mb.last_move_dir
				var bv = hb_parent.velocity
				print("BOTLOG PHIT ppos=%s bv=(%d,%d) esc=%d mv=(%.2f,%.2f)" % [
					_fmt_pos(_hooked_player.position), int(bv.x), int(bv.y),
					_esc_bits(mb), mv.x, mv.y])
		elif args.from != null and ("enemy_id" in args.from):
			src = args.from.enemy_id
		elif hb_parent != null and ("enemy_id" in hb_parent):
			src = hb_parent.enemy_id
	print("BOTLOG HIT wave=%d dmg=%d src=%s total_this_wave=%d" % [
		RunData.current_wave, int(value), src, int(_damage_taken_this_wave)])


func _nearest_distance(units, pos) -> float:
	var best = 99999.0
	for u in units:
		if u.dead or u._pending_die:
			continue
		var d = u.position.distance_to(pos)
		if d < best:
			best = d
	return best


func _count_charging(units, _pos) -> int:
	var n = 0
	for u in units:
		if u.dead or u._pending_die:
			continue
		if u._current_attack_behavior is ChargingAttackBehavior:
			if u._move_locked or not u._can_move:
				n += 1
	return n


class _ByDistance:
	static func sort(a, b) -> bool:
		return a[0] < b[0]


func _nearby_threats(main, player, count) -> String:
	var all = []
	for u in main._entity_spawner.enemies + main._entity_spawner.bosses:
		if not is_instance_valid(u) or u.dead:
			continue
		all.push_back([u.position.distance_to(player.position), u.enemy_id])
	# Plain sort() on [float, String] pairs triggers "bad comparison function"
	# console spam; compare distances only
	all.sort_custom(_ByDistance, "sort")
	var txt = ""
	for i in range(min(count, all.size())):
		txt += "%s@%d " % [all[i][1], int(all[i][0])]
	return txt.strip_edges()


func _fmt_pos(pos) -> String:
	return "(%d,%d)" % [int(pos.x), int(pos.y)]
