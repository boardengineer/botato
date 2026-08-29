extends Reference
# Automatic-shopping decision logic for the AutoBattler bot. Pure functions over
# RunData -- no UI, no side effects. The shop extension
# (extensions/ui/menus/shop/base_shop.gd) executes these decisions; the level-up
# extension (extensions/ui/menus/ingame/upgrades_ui.gd) calls pick_upgrade().
# Preload this script -- no class_name (see build_plans.gd).

const BuildPlans = preload("res://mods-unpacked/Pasha-AutoBattler/shopping/build_plans.gd")

const COMBINE_SCORE = 100.0   # combining upgrades a weapon's tier -- almost always take it
const NEW_WEAPON_MATCH = 22.0 # an empty slot filled with an on-type weapon

static func get_plan(character_id):
	return BuildPlans.get_plan(character_id)

# --- Reading current stats ---------------------------------------------------

static func current_stat(stat_key, player_index):
	return RunData.get_stat(Keys.generate_hash(stat_key), player_index)

# --- Scoring -----------------------------------------------------------------

# Desirability of a set of stat effects under the plan's weights. Harvesting
# collapses to a token weight once the player is past the plan's harvest_cap so
# the bot pivots off economy on schedule. A stat the plan does not list scores 0.
static func stat_score(effects, plan, player_index):
	var s = 0.0
	var weights = plan["stats"]
	var harvest_now = current_stat("stat_harvesting", player_index)
	# Optional early-game re-weighting: before phase_boost.until_wave, multiply
	# the named stats' weights (e.g. a fragile melee kit front-loads dodge/HP so
	# it survives the opening, then reverts to its offence weights). Mirrors the
	# steering caution_phases idea for the shop.
	var boost = plan.get("phase_boost", {})
	var boosting = boost.has("until_wave") and RunData.current_wave < int(boost["until_wave"])
	var boost_stats = boost.get("stats", {}) if boosting else {}
	for e in effects:
		if e == null:
			continue
		var key = e.key
		if not weights.has(key):
			continue
		var w = float(weights[key])
		if boost_stats.has(key):
			w *= float(boost_stats[key])
		if key == "stat_harvesting" and harvest_now >= plan["harvest_cap"]:
			w *= 0.15
		# The plan weight carries the priority; value only breaks ties within a
		# stat and sets the sign (items with a downside on a wanted stat hurt).
		var v = float(e.value)
		if v < 0.0:
			s -= w
		else:
			s += w + min(v, 20.0) * 0.02
	return s

# Would buying this weapon trigger a 3-of-a-kind combine (tier up)? Mirrors
# ItemService.get_icon_for_duplicate_shop_item line 959: not max tier, board
# full (no free slot), and already holding >=1 identical (same my_id) copy.
static func would_combine(wdata, player_index):
	if wdata.upgrades_into == null:
		return false
	if wdata.tier == Tier.LEGENDARY:
		return false
	if RunData.has_weapon_slot_available(wdata, player_index):
		return false
	var same = 0
	for w in RunData.get_player_weapons(player_index):
		if w.my_id == wdata.my_id:
			same += 1
	return same >= 1

static func weapon_type_str(wdata):
	return "ranged" if wdata.type == WeaponData.Type.RANGED else "melee"

# Does the weapon belong to the named set (e.g. "set_elemental" for Mage)?
static func weapon_in_set(wdata, set_id):
	if wdata.sets == null:
		return false
	for s in wdata.sets:
		if s != null and s.my_id == set_id:
			return true
	return false

static func score_weapon(wdata, plan, player_index):
	# A weapon-set plan (Mage: only elemental weapons do damage) trumps the
	# melee/ranged type gate: a weapon outside the set is worthless even if it
	# would combine.
	var want_set = plan.get("weapon_set", "")
	if want_set != "" and not weapon_in_set(wdata, want_set):
		return -1.0
	# Gladiator: +attack speed per UNIQUE weapon family, so it wants 6 DIFFERENT
	# weapons. Combines still tier a family up WITHOUT losing uniqueness (3 -> 1
	# of the same family) so they stay valuable; but a NON-combining duplicate of
	# a family already held just wastes a slot that a new family should take.
	if plan.get("unique_weapons", false) and not would_combine(wdata, player_index):
		for w in RunData.get_player_weapons(player_index):
			if w.weapon_id == wdata.weapon_id:
				return -1.0
	if would_combine(wdata, player_index):
		return COMBINE_SCORE + float(wdata.tier) * 5.0
	var has_slot = RunData.has_weapon_slot_available(wdata, player_index)
	if not has_slot:
		return -1.0   # board full and it will not combine -> not buyable/useful
	if RunData.get_player_weapons(player_index).size() >= plan["max_weapons"]:
		return -1.0
	if want_set != "":
		return NEW_WEAPON_MATCH + float(wdata.tier) * 3.0   # in-set already verified
	var type_ok = plan["weapon_type"] == "any" or weapon_type_str(wdata) == plan["weapon_type"]
	if not type_ok:
		return -1.0   # a typed plan never fills a slot with the wrong damage type
	return NEW_WEAPON_MATCH + float(wdata.tier) * 3.0

# entry is the shop tuple [item_data, wave_value].
static func score_shop_entry(entry, plan, player_index):
	var data = entry[0]
	if data is WeaponData:
		return score_weapon(data, plan, player_index)
	var s = stat_score(data.effects, plan, player_index)
	if plan["item_bonus"].has(data.my_id):
		s += float(plan["item_bonus"][data.my_id])
	return s

# --- Level-up ----------------------------------------------------------------

# Index of the offered UpgradeData that best fits the plan's stat priorities.
static func pick_upgrade(upgrades, plan, player_index):
	var best_i = 0
	var best = -1.0e20
	for i in range(upgrades.size()):
		if upgrades[i] == null:
			continue
		var sc = stat_score(upgrades[i].effects, plan, player_index)
		if sc > best:
			best = sc
			best_i = i
	return best_i
