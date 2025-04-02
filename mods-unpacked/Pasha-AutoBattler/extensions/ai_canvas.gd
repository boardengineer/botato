extends Node2D

func _draw():
	if $"/root/Main"._wave_timer.time_left < .05:
		return
	
	if not $"/root/ModLoader".has_node("dami-ModOptions"):
		return
	
	var ModsConfigInterface = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
	
	var visuals_enabled = ModsConfigInterface.mod_configs["Pasha-AutoBattler"]["ENABLE_AI_VISUALS"]
	
	if not visuals_enabled:
		return
	
	var player = $"/root/Main"._players[0]
	var weapon_range = 1_000
	var _entity_spawner = $"/root/Main/EntitySpawner"
	var options_node = $"/root/AutobattlerOptions"
	
	var item_weight = options_node.item_weight
	var projectile_weight = options_node.projectile_weight
	var tree_weight = options_node.tree_weight
	var boss_weight = options_node.boss_weight
	
	var bumper_weight = options_node.bumper_weight
	var egg_weight = options_node.egg_weight
	
	var circle_size_multiplier = 1_000_000
	var circle_max_size = 100
	var red = Color(1, 0, 0, .6)
	var purple = Color(1, 0, 1, .6)
	
	for weapon in player.current_weapons:
		var max_range = weapon.current_stats.max_range
		
		if max_range < weapon_range:
			weapon_range = max_range
	var preferred_distance_squared = weapon_range * weapon_range
	
	draw_arc(player.position, weapon_range, 0, 6.28, 100, Color.red)
	
	# Eat consumables, weighted by missing hp
	var max_health = float(player.max_stats.health)
	var current_health = float(player.current_stats.health)
	var consumable_weight = (1.0 - (current_health / max_health)) * 2
	
	var _consumables_container = $"/root/Main/"._consumables
	for consumable in _consumables_container:
		var consumable_pos = consumable.position
		var consumable_to_player = consumable_pos - player.position
		var squared_distance_to_consumable = consumable_to_player.length_squared()
		
		var size = (1 / squared_distance_to_consumable) * 10 * consumable_weight * circle_size_multiplier
		
		var item_circle_max = circle_max_size / 2
		
		if size > item_circle_max:
			size = item_circle_max
		
		var to_add = (consumable_to_player.normalized() / squared_distance_to_consumable) * 10 * consumable_weight
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			draw_circle(consumable.position, size, Color.blue)
	
	# Go towards "items" (gold pickups)
	var items_container = $"/root/Main/"._active_golds
	var item_weight_squared = item_weight * item_weight
	for item in items_container:
		var item_pos = item.position
		var item_to_player = item_pos - player.position
		var squared_distance_to_item = item_to_player.length_squared()
		
		var size = (1 / squared_distance_to_item) * circle_size_multiplier * item_weight
		
		var item_circle_max = circle_max_size / 4
		
		if size > item_circle_max:
			size = item_circle_max
		
		var to_add = (item_to_player.normalized() / squared_distance_to_item) * item_weight_squared
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			draw_circle(item.position, size, Color.blue)
			
	# Go towards "neutrals" (trees)
	var tree_weight_squared = tree_weight * tree_weight
	for neutral in _entity_spawner.neutrals:
		var color = Color.blue
		var neutral_pos = neutral.position
		var neutral_to_player = neutral_pos - player.position
		var squared_distance_to_neutral = neutral_to_player.length_squared()
		
		var to_add = (neutral_to_player.normalized() / squared_distance_to_neutral) * tree_weight_squared
		
		var size = (1 / squared_distance_to_neutral) * circle_size_multiplier * tree_weight
		
		# Weigh down nearby trees to keep from getting stuck on them
		if squared_distance_to_neutral < (preferred_distance_squared / 2):
			color = red
			
		if size > circle_max_size:
			size = circle_max_size

		if not is_nan(to_add.x) and not is_nan(to_add.y):
			draw_circle(neutral.position, size, color)
			
	# Go away from projectiles
	var projectiles_container = $"/root/Main/EnemyProjectiles"
	var projectile_weight_squared = projectile_weight * projectile_weight
	for projectile in projectiles_container.get_children():
		var projectile_shape = projectile._hitbox._collision.shape
		var extra_range = 0
		if projectile_shape is CircleShape2D:
			extra_range = projectile_shape.radius
		elif projectile_shape is RectangleShape2D:
			extra_range = projectile_shape.extents.x
			if projectile_shape.extents.y > extra_range:
				extra_range = projectile_shape.extents.y
		
		var projectile_pos = projectile.position
		var projectile_to_player = projectile_pos - player.position
		var extra_range_squared = extra_range * extra_range
		var squared_distance_to_item = projectile_to_player.length_squared() - extra_range_squared
		if squared_distance_to_item < 0:
			squared_distance_to_item = .001
		
		var size = 1 / squared_distance_to_item * 1_000_000 * projectile_weight
		
		var to_add = (projectile_to_player.normalized() / squared_distance_to_item) * -1 * projectile_weight_squared
		if squared_distance_to_item > 250_000:
			size = 0
			to_add = Vector2.ZERO
			
		if size > circle_max_size:
			size = circle_max_size
			
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			draw_circle(projectile.position, size, Color.red)
			
	# Move towards distant enemies, away from nearby ones.  Determined by weapons range.
	var egg_weight_squared = egg_weight * egg_weight
	
	for enemy in _entity_spawner.enemies:
		var color = Color.blue
		var is_egg = enemy._attack_behavior is SpawningAttackBehavior
		var enemy_to_player = enemy.position - player.position
		var squared_distance_to_enemy = (enemy_to_player).length_squared()
		
		if circle_size_multiplier == 0:
			continue
		
		var size = 1 / squared_distance_to_enemy * circle_size_multiplier
		
		var to_add = (enemy_to_player.normalized() / squared_distance_to_enemy)
		if squared_distance_to_enemy < preferred_distance_squared:
			color = red
			to_add = to_add * -1
			
		if is_egg:
			size = size * egg_weight_squared
		
		if size > circle_max_size:
			size = circle_max_size
		
		
		draw_circle(enemy.position, size, color)
		
	# Move towards distant enemies, away from nearby ones.  Determined by weapons range.
	var boss_weight_squared = boss_weight * boss_weight
	for boss in _entity_spawner.bosses:
		var boss_to_player = boss.position - player.position
		var squared_distance_to_boss = (boss_to_player).length_squared()
		
		var color = Color.blue
		var size = 1 / squared_distance_to_boss * circle_size_multiplier
		
		var to_add = (boss_to_player.normalized() / squared_distance_to_boss) * boss_weight_squared
		if squared_distance_to_boss < preferred_distance_squared:
			color = red
			to_add = to_add * -1
			
		if size > circle_max_size:
			size = circle_max_size
		
		draw_circle(boss.position, size, color)
		
	var far_corner = ZoneService.current_zone_max_position
	var bumper_x = 0
	var bumper_distance = options_node.bumper_distance
	var square_bumper_distance = bumper_distance * bumper_distance * 40
	
	while bumper_x < far_corner.x:
		var bumper_position = Vector2(bumper_x, 0)
		
		var squared_distance = (bumper_position - player.position).length_squared()
		
		var size = 1 / squared_distance * circle_size_multiplier * bumper_weight
		
		if size > circle_max_size:
			size = circle_max_size
		
		var to_add = (Vector2(-1,1).normalized() / squared_distance) * bumper_weight
		if squared_distance > square_bumper_distance:
			size = 0
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			draw_circle(bumper_position, size, purple)
		
		bumper_x = bumper_x + bumper_distance
		
	bumper_x = 0
	while bumper_x < far_corner.x:
		var bumper_position = Vector2(bumper_x, far_corner.y)
		
		var squared_distance = (bumper_position - player.position).length_squared()
		
		var size = 1 / squared_distance * circle_size_multiplier * bumper_weight
		
		if size > circle_max_size:
			size = circle_max_size
		
		var to_add = (Vector2(1,-1).normalized() / squared_distance) * bumper_weight
		if squared_distance > square_bumper_distance:
			size = 0
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			draw_circle(bumper_position, size, purple)
		
		bumper_x = bumper_x + bumper_distance
		
	var bumper_y = 0
	while bumper_y < far_corner.y:
		var bumper_position = Vector2(0, bumper_y)
		
		var squared_distance = (bumper_position - player.position).length_squared()
		
		var size = 1 / squared_distance * circle_size_multiplier * bumper_weight
		
		if size > circle_max_size:
			size = circle_max_size
		
		var to_add = (Vector2(1,1).normalized() / squared_distance) * bumper_weight
		if squared_distance > square_bumper_distance:
			size = 0
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			draw_circle(bumper_position, size, purple)
		
		bumper_y = bumper_y + bumper_distance
		
	bumper_y = 0
	while bumper_y < far_corner.y:
		var bumper_position = Vector2(far_corner.x, bumper_y)
		
		var squared_distance = (bumper_position - player.position).length_squared()
		
		var size = 1 / squared_distance * circle_size_multiplier * bumper_weight
		
		if size > circle_max_size:
			size = circle_max_size
		
		var to_add = (Vector2(-1,-1).normalized() / squared_distance) * bumper_weight
		if squared_distance > square_bumper_distance:
			size = 0
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			draw_circle(bumper_position, size, purple)
		
		bumper_y = bumper_y + bumper_distance

func _process(_delta):
	update()
