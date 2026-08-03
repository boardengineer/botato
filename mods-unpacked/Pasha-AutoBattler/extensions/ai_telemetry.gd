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
	var esc = 0
	# corr = corridors actually threatening us last frame (charging= counts
	# map-wide chargers and routinely overstates)
	var corr = 0
	var move_behavior = player._movement_behavior
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
		if "last_corridor_count" in move_behavior:
			corr = move_behavior.last_corridor_count

	_last_threats = _nearby_threats(main, player, 3)
	print("BOTLOG t=%d wave=%d hp=%d/%d pos=%s enemies=%d nearE=%d proj=%d charging=%d corr=%d edge=%d dmgW=%d esc=%d %s" % [
		int(main._wave_timer.wait_time - main._wave_timer.time_left),
		RunData.current_wave,
		int(player.current_stats.health), int(player.max_stats.health),
		_fmt_pos(player.position),
		spawner.enemies.size(), int(near_enemy), proj_count, charging, corr,
		int(edge), int(_damage_taken_this_wave), esc, boss_txt])


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
			# v~0 = pillar/AoE; a just-stopped bullet may also read 0, so print
			# the number instead of guessing a label
			src = "proj(v=%d)" % int(hb_parent.velocity.length())
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
