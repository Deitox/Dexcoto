class_name UpgradeDB
extends Node

const RARITY_WEIGHTS := {
	"Common": 50,
	"Uncommon": 30,
	"Rare": 15,
	"Epic": 4,
	"Legendary": 1,
}

static func all() -> Array[Dictionary]:
	return [
		# Attack Speed (reduces fire interval)
		{"id":"as_5","name":"Attack Speed +5%","rarity":"Common","type":"attack_speed","value":0.05},
		{"id":"as_10","name":"Attack Speed +10%","rarity":"Uncommon","type":"attack_speed","value":0.10},
		{"id":"as_15","name":"Attack Speed +15%","rarity":"Rare","type":"attack_speed","value":0.15},
		{"id":"as_20","name":"Attack Speed +20%","rarity":"Epic","type":"attack_speed","value":0.20},
		{"id":"as_30","name":"Attack Speed +30%","rarity":"Legendary","type":"attack_speed","value":0.30},
		# Damage
		{"id":"dmg_10","name":"Damage +10%","rarity":"Common","type":"damage","value":0.10},
		{"id":"dmg_20","name":"Damage +20%","rarity":"Uncommon","type":"damage","value":0.20},
		{"id":"dmg_30","name":"Damage +30%","rarity":"Rare","type":"damage","value":0.30},
		{"id":"dmg_40","name":"Damage +40%","rarity":"Epic","type":"damage","value":0.40},
		{"id":"dmg_60","name":"Damage +60%","rarity":"Legendary","type":"damage","value":0.60},
		# Move Speed
		{"id":"ms_6","name":"Move Speed +6%","rarity":"Common","type":"move_speed","value":0.06},
		{"id":"ms_12","name":"Move Speed +12%","rarity":"Uncommon","type":"move_speed","value":0.12},
		{"id":"ms_18","name":"Move Speed +18%","rarity":"Rare","type":"move_speed","value":0.18},
		{"id":"ms_24","name":"Move Speed +24%","rarity":"Epic","type":"move_speed","value":0.24},
		# Max HP (flat)
		{"id":"hp_10","name":"Max HP +10","rarity":"Common","type":"max_hp","value":10},
		{"id":"hp_20","name":"Max HP +20","rarity":"Uncommon","type":"max_hp","value":20},
		{"id":"hp_30","name":"Max HP +30","rarity":"Rare","type":"max_hp","value":30},
		{"id":"hp_40","name":"Max HP +40","rarity":"Epic","type":"max_hp","value":40},
		# Bullet Speed
		{"id":"bs_10","name":"Projectile Speed +10%","rarity":"Common","type":"bullet_speed","value":0.10},
		{"id":"bs_20","name":"Projectile Speed +20%","rarity":"Uncommon","type":"bullet_speed","value":0.20},
		{"id":"bs_30","name":"Projectile Speed +30%","rarity":"Rare","type":"bullet_speed","value":0.30},
		{"id":"bs_40","name":"Projectile Speed +40%","rarity":"Epic","type":"bullet_speed","value":0.40},
		# Regeneration
		{"id":"reg_0_5","name":"Regen +0.5/s","rarity":"Common","type":"regen","value":0.5},
		{"id":"reg_1_0","name":"Regen +1.0/s","rarity":"Uncommon","type":"regen","value":1.0},
		{"id":"reg_1_5","name":"Regen +1.5/s","rarity":"Rare","type":"regen","value":1.5},
		{"id":"reg_2_0","name":"Regen +2.0/s","rarity":"Epic","type":"regen","value":2.0},
		# Additional buffs for variety
		{"id":"as_8","name":"Attack Speed +8%","rarity":"Common","type":"attack_speed","value":0.08},
		{"id":"dmg_15","name":"Damage +15%","rarity":"Uncommon","type":"damage","value":0.15},
		{"id":"ms_30","name":"Move Speed +30%","rarity":"Legendary","type":"move_speed","value":0.30},
		{"id":"hp_60","name":"Max HP +60","rarity":"Legendary","type":"max_hp","value":60},
		{"id":"bs_50","name":"Projectile Speed +50%","rarity":"Legendary","type":"bullet_speed","value":0.50},
		{"id":"reg_3_0","name":"Regen +3.0/s","rarity":"Legendary","type":"regen","value":3.0},
		# Elemental Power (affects elemental weapons' damage and effect chance/potency)
		{"id":"elem_5","name":"Elemental Power +5%","rarity":"Common","type":"elemental_power","value":0.05},
		{"id":"elem_10","name":"Elemental Power +10%","rarity":"Uncommon","type":"elemental_power","value":0.10},
		{"id":"elem_20","name":"Elemental Power +20%","rarity":"Rare","type":"elemental_power","value":0.20},
		{"id":"elem_30","name":"Elemental Power +30%","rarity":"Epic","type":"elemental_power","value":0.30},
		{"id":"elem_40","name":"Elemental Power +40%","rarity":"Legendary","type":"elemental_power","value":0.40},
		# Explosive Power (affects explosive weapons' AoE damage/radius)
		{"id":"exp_10","name":"Explosive Power +10%","rarity":"Uncommon","type":"explosive_power","value":0.10},
		{"id":"exp_20","name":"Explosive Power +20%","rarity":"Rare","type":"explosive_power","value":0.20},
		{"id":"exp_30","name":"Explosive Power +30%","rarity":"Epic","type":"explosive_power","value":0.30},
		# Turret Power
		{"id":"tp_10","name":"Turret Power +10%","rarity":"Uncommon","type":"turret_power","value":0.10},
		{"id":"tp_20","name":"Turret Power +20%","rarity":"Rare","type":"turret_power","value":0.20},
		{"id":"tp_30","name":"Turret Power +30%","rarity":"Epic","type":"turret_power","value":0.30},
		# Defense (reduces damage taken)
		{"id":"def_10","name":"Defense +10%","rarity":"Uncommon","type":"defense","value":0.10},
		{"id":"def_15","name":"Defense +15%","rarity":"Rare","type":"defense","value":0.15},
		{"id":"def_20","name":"Defense +20%","rarity":"Epic","type":"defense","value":0.20},
		{"id":"def_25","name":"Defense +25%","rarity":"Legendary","type":"defense","value":0.25},
	]

static func weighted_choices(count: int, exclude_ids: Array[String] = []) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for u in all():
		var id: String = String(u["id"])
		if exclude_ids.has(id):
			continue
		var rarity: String = String(u["rarity"])
		var w: int = int(RARITY_WEIGHTS.get(rarity, 1))
		pool.append({"w": w, "u": u})
	var result: Array[Dictionary] = []
	var attempts: int = 0
	while result.size() < count and attempts < 1000 and pool.size() > 0:
		attempts += 1
		var total_w: int = 0
		for e in pool:
			total_w += int(e["w"])
		var r: int = randi() % max(1, total_w)
		var acc: int = 0
		var picked_index: int = -1
		for i in range(pool.size()):
			acc += int(pool[i]["w"])
			if r < acc:
				picked_index = i
				break
		if picked_index >= 0:
			var upg: Dictionary = pool[picked_index]["u"]
			result.append(upg)
			pool.remove_at(picked_index)
	return result
