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
	# phase_boost: before until_wave, multiply the named stats' weights (early
	# survival for fragile kits, etc.). Empty = no phasing.
	"phase_boost": {},
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

	# --- #2. Guide: brotato-builds.com/builds/Brawler ("Speed Demon"). Melee,
	# Claw/unarmed: rush attack speed + melee damage + crit, cap dodge fast, take
	# HP regen and some HP to survive the short range. Not an economy character.
	"character_brawler": {
		"weapon_type": "melee",
		# Fragile 10-HP kit. Offence leads (kill speed is a melee kit's real
		# defence -- a defence-first pass killed enemies slower and died EARLIER),
		# with dodge and HP regen as the survival stats the guide calls for.
		"stats": {
			"stat_attack_speed": 9.0,
			"stat_melee_damage": 8.0,
			"stat_crit_chance": 7.0,
			"stat_dodge": 7.0,
			"stat_hp_regeneration": 6.0,
			"stat_percent_damage": 6.0,
			"stat_crit_damage": 5.0,
			"stat_max_hp": 5.0,
			"stat_armor": 4.0,
			"stat_lifesteal": 4.0,
		},
		# The offence weights win late, but the 10-HP opening is where the bot
		# collapses (a batch died wave 8). Front-load survival through wave 6 so
		# it reaches the point its kill speed can carry it.
		"phase_boost": {"until_wave": 7, "stats": {
			"stat_max_hp": 2.2, "stat_dodge": 1.8,
			"stat_hp_regeneration": 1.8, "stat_armor": 1.5,
		}},
		"harvest_cap": 0,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #3. Guide: brotato-builds.com/builds/Crazy ("Knife Pro"). Precise
	# weapons + crit. Crazy STARTS with a knife, gets +100% Precise class bonus
	# and +25% attack speed but -30% dodge (so dodge is a trap stat -- excluded).
	# Melee knife route fits its start + the melee-leaning steering row
	# (caution 0.7, engage 6); its high attack speed kills fast enough to survive.
	"character_crazy": {
		"weapon_type": "melee",
		"stats": {
			"stat_crit_chance": 10.0,
			"stat_melee_damage": 8.0,
			"stat_attack_speed": 8.0,
			"stat_crit_damage": 7.0,
			"stat_percent_damage": 6.5,
			"stat_max_hp": 6.0,
			"stat_armor": 5.0,
			"stat_lifesteal": 4.0,
			"stat_hp_regeneration": 3.0,
		},
		# -30% base dodge => no dodge weight; survival comes from HP/armor, with
		# an early phase_boost since it is squishy (like Brawler).
		"phase_boost": {"until_wave": 6, "stats": {
			"stat_max_hp": 1.8, "stat_armor": 1.5, "stat_hp_regeneration": 1.5,
		}},
		"harvest_cap": 0,
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
