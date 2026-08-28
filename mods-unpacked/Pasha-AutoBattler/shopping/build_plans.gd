extends Reference
# Per-character shop/economy plans, each sourced from an internet build guide
# (citations in shopping/SHOP-GUIDES.md). Consumed by shop_advisor.gd. No
# class_name -- ModLoader's class_name registration is unreliable, so callers
# preload this script (mirrors how steering/arbiter.gd is loaded).
#
# A plan expresses a guide as data:
#   weapon_type  favoured damage type for weapon buys: "ranged" | "melee" | "any"
#   stats        stat_key(String) -> desirability weight; the ORDER the guide
#                prioritises stats becomes the relative weights here
#   harvest_cap  once stat_harvesting reaches this, stop over-valuing harvesting
#   item_bonus   item my_id -> extra score, for named guide items whose value is
#                a special effect rather than a stat (Bag, Scar, Cape, ...)
#   max_weapons  stop buying non-combining weapons past this many held
#   reroll_keep  never spend the last of the gold rerolling -- keep at least this
#   max_rerolls  paid rerolls per shop visit (free rerolls are always taken)
#   min_buy      do not buy an item scoring below this

const DEFAULT = {
	"weapon_type": "any",
	"stats": {
		# a sane generalist ordering so an unlisted character still shops sensibly
		"stat_percent_damage": 6.0,
		"stat_attack_speed": 5.0,
		"stat_max_hp": 5.0,
		"stat_ranged_damage": 4.0,
		"stat_melee_damage": 4.0,
		"stat_armor": 4.0,
		"stat_crit_chance": 4.0,
		"stat_lifesteal": 4.0,
		"stat_dodge": 3.0,
		"stat_harvesting": 5.0,
		"stat_hp_regeneration": 2.0,
		"stat_range": 2.0,
	},
	"harvest_cap": 40,
	"item_bonus": {},
	"max_weapons": 6,
	# Brotato pays no interest, so banked gold is wasted damage/defence. Spend it:
	# keep only a small buffer and reroll freely to surface items and weapon
	# combines. The reroll price rises per paid roll, so cost self-limits this.
	"reroll_keep": 5,
	"max_rerolls": 15,
	"min_buy": 2.0,
}

const PLANS = {
	# --- #1 top-left. Guide: brotato-builds.com/builds/Well-Rounded ("Beginner's
	# SMG"). Ranged SMG + Double Barrel; rush Harvesting to 21+, then ranged
	# damage / attack speed, then lifesteal and defence. Ranged fits the arbiter.
	"character_well_rounded": {
		"weapon_type": "ranged",
		"stats": {
			"stat_harvesting": 10.0,
			"stat_ranged_damage": 8.0,
			"stat_attack_speed": 7.0,
			"stat_percent_damage": 6.5,
			"stat_lifesteal": 6.0,
			"stat_max_hp": 5.0,
			"stat_crit_chance": 4.5,
			"stat_armor": 4.0,
			"stat_dodge": 3.0,
			"stat_hp_regeneration": 2.0,
		},
		"harvest_cap": 40,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},
}

static func get_plan(character_id):
	var p = DEFAULT.duplicate(true)
	if PLANS.has(character_id):
		var row = PLANS[character_id]
		for k in row.keys():
			p[k] = row[k]
	return p
