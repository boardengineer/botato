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

	# --- #4. Guide: brotato-builds.com/builds/Ranger ("SMG Range Scaler"). Pure
	# ranged (CANNOT use melee), +50 range, +50% ranged damage, -25% max HP from
	# upgrades. Kiting -- "delete enemies before they get close" -- so it takes
	# little damage and needs no early phase_boost (like Well Rounded). HP is
	# deprioritised (the -25% penalty); armour/dodge carry defence.
	"character_ranger": {
		"weapon_type": "ranged",
		"stats": {
			"stat_ranged_damage": 10.0,
			"stat_attack_speed": 8.0,
			"stat_harvesting": 8.0,
			"stat_percent_damage": 7.0,
			"stat_crit_chance": 6.0,
			"stat_range": 5.0,
			"stat_armor": 5.0,
			"stat_dodge": 5.0,
			"stat_max_hp": 3.0,
			"stat_lifesteal": 3.0,
		},
		"harvest_cap": 35,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #5. Guide: brotato-builds.com/builds/Mage ("Taser Wizard"). Mage does
	# damage ONLY through elemental weapons: -100% ranged AND melee damage mods,
	# +elemental. So weapon_set locks buys to the elemental class (set_elemental
	# = taser/wand/flamethrower/torch/lightning shiv); a pistol etc. would do 0.
	# Elemental damage leads, then attack speed and luck (find burn items) with
	# armour/HP-regen defence. The harness gives it a wand start (not a pistol).
	"character_mage": {
		"weapon_type": "any",
		"weapon_set": "set_elemental",
		"stats": {
			"stat_elemental_damage": 10.0,
			"stat_attack_speed": 8.0,
			"stat_percent_damage": 6.5,
			"stat_luck": 5.5,
			"stat_armor": 5.0,
			"stat_hp_regeneration": 5.0,
			"stat_max_hp": 5.0,
			"stat_crit_chance": 4.0,
			"stat_dodge": 4.0,
		},
		"phase_boost": {"until_wave": 6, "stats": {
			"stat_max_hp": 1.6, "stat_armor": 1.5, "stat_hp_regeneration": 1.5,
		}},
		"harvest_cap": 0,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #6. Guide: brotato-builds.com/builds/Chunky ("HP & Explosive"). Tank:
	# +25% max HP and every 3 Max HP grants 1% damage, so Max HP is both survival
	# AND offence. Armour is defence + Spiky Shield damage. -100% lifesteal, -50%
	# HP regen and dodge => those are trap stats (excluded). High base HP, no
	# early fragility, so no phase_boost. Melee (Rock/Spiky Shield/Chopper).
	"character_chunky": {
		"weapon_type": "melee",
		"stats": {
			"stat_max_hp": 10.0,
			"stat_armor": 8.0,
			"stat_percent_damage": 6.0,
			"stat_attack_speed": 6.0,
			"stat_melee_damage": 4.0,
			"stat_crit_chance": 4.0,
			"stat_luck": 4.0,
			"stat_speed": 3.0,
		},
		"harvest_cap": 0,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #7. Guide: brotato-builds.com/builds/Old ("Small Map Engineer"). Old's
	# traits make it EASY -- enemies -25% speed and -10 count, map -33%, +10
	# harvesting -- and it has NO weapon restriction. The guide's optimal is an
	# engineering/turret build, but turrets need turret-aware steering + tool
	# seeking (not built yet), so this uses a bot-reliable RANGED kite build that
	# rides Old's easy traits, with harvesting economy and a tanky/defensive lean.
	"character_old": {
		"weapon_type": "ranged",
		"stats": {
			"stat_ranged_damage": 8.0,
			"stat_attack_speed": 7.0,
			"stat_harvesting": 7.0,
			"stat_percent_damage": 6.5,
			"stat_max_hp": 6.0,
			"stat_armor": 6.0,
			"stat_crit_chance": 4.5,
			"stat_dodge": 4.0,
		},
		"harvest_cap": 40,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #8. Guides: brotatodex.com/character/character_lucky ("Luck Damage") +
	# metabrotato.com lucky-slingshot-build. +100 Luck, +25% stat gains, bonus
	# damage on gold pickup (luck-scaled) -- but -60% attack speed (slow fragile
	# early game) and -50% XP (shop is the scaling path, not levels). Steering
	# row already gold-seeks and never stands still, which feeds the pickup
	# damage. Luck first, attack speed to dig out of the -60, tank HP/armor,
	# ranged kiting weapons.
	"character_lucky": {
		"weapon_type": "ranged",
		# First pass (luck 10 > atkspd 8) went 0/3 (w19/10/17): Lucky already
		# STARTS at +100 luck, so buying more is diminishing returns while the
		# -60% attack speed starves DPS the whole run. Attack speed leads now.
		"stats": {
			"stat_attack_speed": 10.0,
			"stat_ranged_damage": 8.0,
			"stat_percent_damage": 7.0,
			"stat_max_hp": 7.0,
			"stat_armor": 6.0,
			"stat_harvesting": 5.0,
			"stat_luck": 4.0,
			"stat_crit_chance": 4.0,
			"stat_dodge": 4.0,
		},
		# The -60% attack speed makes the opening slow AND fragile: boost kill
		# speed and HP until the build comes online.
		"phase_boost": {"until_wave": 7, "stats": {
			"stat_attack_speed": 1.8, "stat_max_hp": 1.6,
		}},
		"harvest_cap": 35,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #9. Guide: brotato-builds.com/builds/Mutant ("XP Scaling"). Real traits
	# are simple: -66% XP needed (levels ~3x faster -- level-ups ARE the scaling
	# engine) and +50% item prices (the shop is expensive). No weapon or damage
	# penalties, so proven ranged kiting. Balanced damage/defence weights so the
	# frequent level-ups build a rounded potato; harvesting funds the inflated
	# shop; min_buy raised so it does not overpay for marginal items at +50%.
	"character_mutant": {
		"weapon_type": "ranged",
		"stats": {
			"stat_ranged_damage": 8.0,
			"stat_attack_speed": 7.0,
			"stat_max_hp": 6.5,
			"stat_percent_damage": 6.5,
			"stat_harvesting": 6.0,
			"stat_armor": 5.5,
			"stat_dodge": 5.0,
			"stat_crit_chance": 4.5,
			"stat_lifesteal": 3.0,
		},
		"harvest_cap": 40,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 3.0,
	},

	# --- #10. Guide: brotatodex.com/character/character_generalist ("Cactus &
	# Slingshot Hybrid"). Must run 3 melee + 3 ranged -- the GAME enforces the
	# split via max_melee/ranged_weapons in has_weapon_slot_available, which the
	# scorer already consults, so weapon_type "any" fills 3+3 on its own. Melee
	# damage boosts ranged and vice versa: weight both flat damages high, then
	# HP/armour, attack speed + crit, with the guide's early luck + harvesting.
	"character_generalist": {
		"weapon_type": "any",
		"stats": {
			"stat_melee_damage": 8.0,
			"stat_ranged_damage": 8.0,
			"stat_max_hp": 6.5,
			"stat_attack_speed": 6.5,
			"stat_percent_damage": 6.0,
			"stat_armor": 5.5,
			"stat_crit_chance": 5.0,
			"stat_harvesting": 5.0,
			"stat_luck": 4.0,
			"stat_dodge": 3.5,
		},
		"harvest_cap": 35,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #11. Guide: brotatodex.com/character/character_loud ("Enemy Overload
	# Farmer") + metabrotato.com best-loud-build. +30% damage, +50% enemies (the
	# extra kills ARE the economy), harvesting -3 per wave (a decaying trap stat
	# -- excluded). Kill-focused: attack speed + damage to clear the denser
	# waves, max HP emphasized (guide: critical), lifesteal sustains through the
	# horde. Ranged kiting -- the arbiter's strength suits +50% enemy density.
	"character_loud": {
		"weapon_type": "ranged",
		"stats": {
			"stat_attack_speed": 9.0,
			"stat_ranged_damage": 8.0,
			"stat_max_hp": 7.5,
			"stat_percent_damage": 7.0,
			"stat_crit_chance": 5.5,
			"stat_lifesteal": 5.0,
			"stat_armor": 5.0,
			"stat_dodge": 4.0,
		},
		"harvest_cap": 0,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #12. Guide: brotatodex.com/character/character_multitasker ("12-Stick
	# DPS"). 12 weapon slots, +20% damage, -5% damage per extra weapon -- volume
	# wins. Melee stick route: melee damage + percent damage + attack speed +
	# max HP. max_weapons 12 fills the board; combines only trigger at 12/12
	# (the scorer's would_combine needs a full board), which matches the guide's
	# "don't combine until full" automatically.
	"character_multitasker": {
		"weapon_type": "melee",
		"stats": {
			"stat_melee_damage": 9.0,
			"stat_percent_damage": 8.0,
			"stat_attack_speed": 7.5,
			"stat_max_hp": 7.0,
			"stat_armor": 5.0,
			"stat_crit_chance": 4.5,
			"stat_lifesteal": 4.0,
			"stat_hp_regeneration": 3.5,
		},
		"phase_boost": {"until_wave": 6, "stats": {
			"stat_max_hp": 1.6, "stat_armor": 1.4,
		}},
		"harvest_cap": 0,
		"item_bonus": {},
		"max_weapons": 12,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #13. Guide: brotato-builds.com/builds/Wildling ("Lifesteal Setup").
	# +30% lifesteal with Primitive weapons (stick start), so weapon_set locks
	# buys to set_primitive (stick/rock/spear/hatchet/cactus mace/sharp tooth/
	# slingshot/torch). Offence-forward -- the innate lifesteal IS the sustain
	# (guide: skip healing items; base lifesteal suffices), so hp_regen/lifesteal
	# weights stay low and melee damage + attack speed lead. Steering row is
	# already an aggressive melee engager (caution 0.55, engage 8).
	"character_wildling": {
		"weapon_type": "any",
		"weapon_set": "set_primitive",
		"stats": {
			"stat_melee_damage": 8.5,
			"stat_attack_speed": 8.0,
			"stat_percent_damage": 7.0,
			"stat_max_hp": 6.0,
			"stat_ranged_damage": 5.0,
			"stat_crit_chance": 5.0,
			"stat_armor": 4.5,
			"stat_lifesteal": 3.0,
		},
		"phase_boost": {"until_wave": 6, "stats": {
			"stat_max_hp": 1.6, "stat_armor": 1.4,
		}},
		"harvest_cap": 0,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #14. Guide: brotatodex.com/character/character_pacifist ("Peaceful
	# Hand"). -100% damage and -100 engineering: EVERY damage stat is a trap
	# stat (all weights zero). Income is 0.65 mats+XP per enemy ALIVE at wave
	# end -- economy first, defence second. Weapons are pure utility knockback/
	# slow (guide: 6 Hands + taser utility) = the support set. The steering row
	# is the deeply tuned herding kit from the tracker work (perimeter orbit,
	# dps 0, lethality 3) -- it survives, the shop just has to fund it.
	"character_pacifist": {
		"weapon_type": "any",
		"weapon_set": "set_support",
		"stats": {
			"stat_harvesting": 10.0,
			"stat_dodge": 7.0,
			"stat_armor": 6.5,
			"stat_max_hp": 6.0,
			"stat_hp_regeneration": 5.5,
			"stat_speed": 4.5,
			"stat_attack_speed": 3.0,
			"stat_luck": 3.0,
		},
		# First pass died waves 4 and 7: with zero damage the whole early game is
		# dodging with a naked HP pool (the tuned herding steering assumes the
		# HP/dodge of a developed build). Front-load defence HARD.
		"phase_boost": {"until_wave": 8, "stats": {
			"stat_dodge": 2.0, "stat_max_hp": 1.8,
			"stat_armor": 1.7, "stat_speed": 1.5,
		}},
		"harvest_cap": 60,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #15. Guide: brotato-builds.com/builds/Gladiator ("Multi Weapon").
	# +20% attack speed per UNIQUE melee weapon, +5 melee damage, no ranged
	# weapons, -40% attack speed base, -30 luck. Six different melee weapons is
	# the engine (shop variety supplies distinct ids on its own; a duplicate
	# combine on a full board frees a slot for a new unique). Attack speed +
	# melee damage lead, then armour/HP/regen so it can live inside packs.
	"character_gladiator": {
		"weapon_type": "melee",
		"unique_weapons": true,   # +20% attack speed per DISTINCT family -> variety, no dupes/combines
		"stats": {
			"stat_attack_speed": 9.0,
			"stat_melee_damage": 8.5,
			"stat_percent_damage": 6.5,
			"stat_max_hp": 6.5,
			"stat_armor": 6.0,
			"stat_hp_regeneration": 5.0,
			"stat_crit_chance": 4.0,
			"stat_lifesteal": 4.0,
		},
		"phase_boost": {"until_wave": 6, "stats": {
			"stat_max_hp": 1.6, "stat_armor": 1.4,
		}},
		"harvest_cap": 0,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #16. Guide: brotatodex.com/character/character_saver ("Piggy Bank
	# Economy") + number13.de spear build. +15 harvesting, +1% damage per 25
	# materials HELD, Piggy Bank pays +20% of kept materials each wave -- the
	# one character where hoarding IS the damage stat, so gold_floor 400 breaks
	# the universal spend-down (+16% damage held, guide targets ~800-1000 by
	# wave 10 but the floor must not starve early items). +50% item prices like
	# Mutant => min_buy 3. Spear start: melee primitive; survival stats lead.
	"character_saver": {
		"weapon_type": "melee",
		"stats": {
			"stat_attack_speed": 7.5,
			"stat_melee_damage": 7.0,
			"stat_harvesting": 7.0,
			"stat_max_hp": 6.5,
			"stat_dodge": 6.0,
			"stat_hp_regeneration": 5.5,
			"stat_armor": 5.5,
			"stat_crit_chance": 4.0,
		},
		"gold_floor": 250,
		"phase_boost": {"until_wave": 6, "stats": {
			"stat_max_hp": 1.6, "stat_armor": 1.4,
		}},
		"harvest_cap": 60,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 3.0,
	},

	# --- #17. Guide: brotato-builds.com/builds/Sick ("SMG Setup"). +25%
	# lifesteal, loses 1 HP/second, -100% HP regen (trap stat -- excluded, and
	# the guide says skip extra lifesteal too: the innate 25% is the sustain).
	# High-hit-count ranged (SMG) so every wave is a lifesteal stream; ranged
	# damage + attack speed + armour lead; keep moving and shooting.
	"character_sick": {
		"weapon_type": "ranged",
		"hitrate_pref": true,   # innate 25% lifesteal scales with HITS -> favour fast weapons (SMG)
		"stats": {
			"stat_ranged_damage": 8.5,
			"stat_attack_speed": 8.5,
			"stat_max_hp": 6.5,
			"stat_armor": 6.5,
			"stat_percent_damage": 6.0,
			"stat_crit_chance": 4.5,
			"stat_dodge": 4.5,
			"stat_speed": 3.5,
		},
		"phase_boost": {"until_wave": 6, "stats": {
			"stat_max_hp": 1.5, "stat_armor": 1.4,
		}},
		"harvest_cap": 0,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #18. Guide: metabrotato.com farmer-build-pruner-guide ("Material
	# Hoarder"). +20 harvesting, harvesting grows +3/wave, -50% gold drops (the
	# economy IS the growth, not enemy drops). Economy-first then convert to
	# damage/defence. Ranged kiting (Circular Saw/Chainsaw are tool weapons but
	# the arbiter handles ranged best; pistol start is fine here). Harvesting
	# leads with a high cap since it compounds, then damage + defence.
	"character_farmer": {
		"weapon_type": "ranged",
		"stats": {
			"stat_harvesting": 10.0,
			"stat_ranged_damage": 7.5,
			"stat_attack_speed": 7.0,
			"stat_max_hp": 6.5,
			"stat_percent_damage": 6.0,
			"stat_armor": 6.0,
			"stat_dodge": 4.5,
			"stat_crit_chance": 4.0,
		},
		# Bimodal without this: economy-late runs reach w19, but a slow start
		# (thin HP, -50% gold drops delays the shop) collapsed at w10/w12. Buy
		# survival early while harvesting compounds.
		"phase_boost": {"until_wave": 7, "stats": {
			"stat_max_hp": 1.7, "stat_armor": 1.5, "stat_attack_speed": 1.4,
		}},
		"harvest_cap": 60,
		"item_bonus": {},
		"max_weapons": 6,
		"reroll_keep": 5,
		"max_rerolls": 15,
		"min_buy": 2.0,
	},

	# --- #19. Guide: brotatodex.com/character/character_ghost ("Ethereal Axe
	# Dodge"). +10 ethereal bonus, +30 dodge, DODGE CAP 90 (vs the usual 60),
	# -100 armor. Survival is ENTIRELY dodge -> weight it far above anything
	# (each point matters up to 90, and armor is a trap: -100 base amplifies
	# every hit, so armor weight is ZERO). weapon_set set_ethereal (ghost axe/
	# flint/scepter). Then max HP + healing; no armor.
	"character_ghost": {
		"weapon_type": "any",
		"weapon_set": "set_ethereal",
		"stats": {
			"stat_dodge": 12.0,
			"stat_max_hp": 8.0,
			"stat_lifesteal": 6.0,
			"stat_hp_regeneration": 6.0,
			"stat_percent_damage": 6.0,
			"stat_attack_speed": 6.0,
			"stat_melee_damage": 5.0,
			"stat_crit_chance": 4.0,
		},
		"phase_boost": {"until_wave": 7, "stats": {
			"stat_dodge": 1.6, "stat_max_hp": 1.6,
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
