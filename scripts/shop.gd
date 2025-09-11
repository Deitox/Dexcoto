class_name ShopDB
extends Node

# Central catalogs to avoid reconstructing arrays on each call.
# Note: These are treated as read-only. Callers should not mutate entries.
const WEAPONS: Array[Dictionary] = [
		{"kind":"weapon","id":"pistol","name":"Pistol","cost":8,"rarity":"Common",
		 "desc":"Balanced sidearm.",
		 "fire_interval":0.35, "damage":10, "speed":500, "projectiles":1, "color": Color(1,1,0.2)},
		{"kind":"weapon","id":"smg","name":"SMG","cost":10,"rarity":"Common",
		 "desc":"Fast, low damage.",
		 "fire_interval":0.18, "damage":6, "speed":520, "projectiles":1, "color": Color(0.2,1,1)},
		{"kind":"weapon","id":"shotgun","name":"Shotgun","cost":14,"rarity":"Uncommon",
		 "desc":"Slow, fires 3 projectiles.",
		 "fire_interval":0.60, "damage":12, "speed":460, "projectiles":3, "color": Color(1,0.5,0.3)},
		{"kind":"weapon","id":"rifle","name":"Rifle","cost":12,"rarity":"Uncommon",
		 "desc":"Hard-hitting mid fire rate.",
		 "fire_interval":0.45, "damage":16, "speed":560, "projectiles":1, "color": Color(0.8,0.9,1)},
		{"kind":"weapon","id":"minigun","name":"Minigun","cost":16,"rarity":"Rare",
		 "desc":"Very fast, low damage.",
		 "fire_interval":0.10, "damage":4, "speed":520, "projectiles":1, "color": Color(0.7,0.7,1)},
		{"kind":"weapon","id":"cannon","name":"Cannon","cost":18,"rarity":"Epic",
		 "desc":"Very slow, huge damage.",
		 "fire_interval":0.90, "damage":28, "speed":450, "projectiles":1, "color": Color(1,0.8,0.5)},
		# New weapons
		{"kind":"weapon","id":"laser","name":"Laser","cost":15,"rarity":"Uncommon",
		 "desc":"High speed, moderate damage.",
		 "fire_interval":0.40, "damage":12, "speed":900, "projectiles":1, "color": Color(1,1,0.6)},
		{"kind":"weapon","id":"railgun","name":"Railgun","cost":22,"rarity":"Epic",
		 "desc":"Extremely fast shots (often beam).", 
		 "fire_interval":0.80, "damage":30, "speed":1200, "projectiles":1, "color": Color(0.9,0.9,1)},
		{"kind":"weapon","id":"flamethrower","name":"Flamethrower","cost":16,"rarity":"Rare",
		 "desc":"Rapid stream. Fire element; chance to Ignite.",
		 "fire_interval":0.08, "damage":3, "speed":420, "projectiles":1, "color": Color(1,0.6,0.2),
		 "element":"fire", "element_proc":0.25, "ignite_factor":0.4, "ignite_duration":2.0},
		{"kind":"weapon","id":"boomerang","name":"Boomerang","cost":14,"rarity":"Uncommon",
		 "desc":"Wide spread of 2 projectiles.",
		 "fire_interval":0.55, "damage":10, "speed":520, "projectiles":2, "color": Color(0.8,1,0.8)},
		{"kind":"weapon","id":"crossbow","name":"Crossbow","cost":13,"rarity":"Uncommon",
		 "desc":"Slow but accurate bolt.",
		 "fire_interval":0.65, "damage":18, "speed":540, "projectiles":1, "color": Color(0.9,0.8,0.7)},
		{"kind":"weapon","id":"burst","name":"Burst Pistol","cost":12,"rarity":"Common",
		 "desc":"Fires 2 projectiles per shot.",
		 "fire_interval":0.42, "damage":8, "speed":520, "projectiles":2, "color": Color(0.7,1,0.9)},
		{"kind":"weapon","id":"splitter","name":"Splitter","cost":18,"rarity":"Rare",
		 "desc":"3 projectiles, moderate speed.",
		 "fire_interval":0.50, "damage":11, "speed":540, "projectiles":3, "color": Color(0.7,0.9,1)},
		{"kind":"weapon","id":"cannon_mk2","name":"Cannon Mk.II","cost":24,"rarity":"Legendary",
		 "desc":"Very slow, massive damage.",
		 "fire_interval":1.10, "damage":40, "speed":460, "projectiles":1, "color": Color(1,0.9,0.6)},
		# Elemental weapons
		{"kind":"weapon","id":"cryo_blaster","name":"Cryo Blaster","cost":16,"rarity":"Rare",
		 "desc":"Cryo element. Chance to Freeze.",
		 "fire_interval":0.42, "damage":12, "speed":540, "projectiles":1, "color": Color(0.6,0.9,1.0),
		 "element":"cryo", "element_proc":0.25, "freeze_duration":0.9},
		{"kind":"weapon","id":"shock_rifle","name":"Shock Rifle","cost":18,"rarity":"Rare",
		 "desc":"Shock element. On hit, arcs to nearby foes.",
		 "fire_interval":0.38, "damage":11, "speed":560, "projectiles":1, "color": Color(0.8,1.0,1.0),
		 "element":"shock", "element_proc":0.35, "arc_count":2, "arc_radius":140.0, "arc_factor":0.5},
		{"kind":"weapon","id":"void_projector","name":"Void Projector","cost":20,"rarity":"Epic",
		 "desc":"Void element. Applies Vulnerable debuff.",
		 "fire_interval":0.55, "damage":16, "speed":600, "projectiles":1, "color": Color(0.8,0.5,1.0),
		 "element":"void", "element_proc":0.30, "vuln":0.20, "vuln_duration":2.5},
		# Explosive weapons
		{"kind":"weapon","id":"grenade_launcher","name":"Grenade Launcher","cost":18,"rarity":"Rare",
		 "desc":"Explosive rounds. AoE on hit.",
		 "fire_interval":0.60, "damage":18, "speed":480, "projectiles":1, "color": Color(1.0,0.8,0.5),
		 "explosive": true, "expl_radius": 120.0, "expl_factor": 0.9},
		{"kind":"weapon","id":"rocket_launcher","name":"Rocket Launcher","cost":22,"rarity":"Epic",
		 "desc":"High damage explosive rockets.",
		 "fire_interval":0.85, "damage":26, "speed":520, "projectiles":1, "color": Color(1.0,0.9,0.6),
		 "explosive": true, "expl_radius": 160.0, "expl_factor": 1.0},
		{"kind":"weapon","id":"cluster_bomb","name":"Cluster Bomb","cost":24,"rarity":"Legendary",
		 "desc":"Explodes in a large radius.",
		 "fire_interval":0.95, "damage":22, "speed":460, "projectiles":1, "color": Color(1.0,0.85,0.6),
		 "explosive": true, "expl_radius": 200.0, "expl_factor": 0.8},
		# Stacking-kill weapons
		{"kind":"weapon","id":"berserker","name":"Berserker","cost":18,"rarity":"Rare",
		 "desc":"Kills grant +2% Damage per stack (fewer kills at higher tier).",
		 "fire_interval":0.40, "damage":10, "speed":520, "projectiles":1, "color": Color(1.0,0.4,0.4),
		 "stack": {"type":"damage","per_stack":0.02,"base_kills":6}},
		{"kind":"weapon","id":"tempo","name":"Tempo","cost":18,"rarity":"Rare",
		 "desc":"Kills grant +2% Attack Speed per stack (fewer kills at higher tier).",
		 "fire_interval":0.30, "damage":8, "speed":540, "projectiles":1, "color": Color(0.6,1.0,0.6),
		 "stack": {"type":"attack_speed","per_stack":0.02,"base_kills":6}},
		{"kind":"weapon","id":"bulwark","name":"Bulwark","cost":20,"rarity":"Epic",
		 "desc":"Kills grant +3 Max HP per stack (fewer kills at higher tier).",
		 "fire_interval":0.55, "damage":14, "speed":500, "projectiles":1, "color": Color(0.6,0.8,1.0),
		 "stack": {"type":"max_hp","per_stack":3,"base_kills":7}},
		# Constructor-style weapon that spawns turrets on kill stacks
		{"kind":"weapon","id":"constructor","name":"Constructor","cost":14,"rarity":"Uncommon",
		 "desc":"Kills spawn turrets after a few kills (fewer kills at higher tier).",
		 "fire_interval":0.45, "damage":9, "speed":520, "projectiles":1, "color": Color(0.7,1.0,0.3),
		 "stack": {"type":"turret_spawn","per_stack":1,"base_kills":4}},
		# New: Crit-stacking weapon
		{"kind":"weapon","id":"assassin","name":"Assassin","cost":18,"rarity":"Rare",
		 "desc":"Kills grant +2% Crit Chance (overflow boosts crit damage).",
		 "fire_interval":0.38, "damage":9, "speed":560, "projectiles":1, "color": Color(1.0,0.8,0.2),
		 "stack": {"type":"crit_chance","per_stack":0.02,"base_kills":6}},
]

const ITEMS: Array[Dictionary] = [
		{"kind":"item","id":"money_charm","name":"Money Charm","cost":12,"rarity":"Uncommon",
		 "desc":"Earn 20% more currency."},
		{"kind":"item","id":"turret","name":"Turret","cost":18,"rarity":"Rare",
		 "desc":"Place a stationary turret next wave."},
		
		{"kind":"item","id":"overcharger","name":"Overcharger","cost":14,"rarity":"Rare",
		 "desc":"+15% attack speed."},
		{"kind":"item","id":"adrenaline","name":"Adrenaline","cost":10,"rarity":"Common",
		 "desc":"+0.5 HP regen/s."},
		{"kind":"item","id":"lifesteal_charm","name":"Lifesteal Charm","cost":12,"rarity":"Uncommon",
		 "desc":"Heal 1 HP per kill."},
		# New items
		{"kind":"item","id":"boots","name":"Boots","cost":10,"rarity":"Common",
		 "desc":"+10% move speed."},
		{"kind":"item","id":"caffeine","name":"Caffeine","cost":12,"rarity":"Uncommon",
		 "desc":"+10% attack speed."},
		
		{"kind":"item","id":"aerodynamics","name":"Aerodynamics","cost":10,"rarity":"Common",
		 "desc":"+20% projectile speed."},
		{"kind":"item","id":"protein_bar","name":"Protein Bar","cost":10,"rarity":"Common",
		 "desc":"+15 Max HP."},
		{"kind":"item","id":"medkit","name":"Medkit","cost":12,"rarity":"Uncommon",
		 "desc":"+1.0 HP regen/s."},
		{"kind":"item","id":"greed_token","name":"Greed Token","cost":14,"rarity":"Rare",
		 "desc":"+15% currency gain."},
		{"kind":"item","id":"vampiric_orb","name":"Vampiric Orb","cost":16,"rarity":"Rare",
		 "desc":"+1 HP per kill."},
		{"kind":"item","id":"power_core","name":"Power Core","cost":16,"rarity":"Rare",
		 "desc":"+10% damage."},
		{"kind":"item","id":"stabilizer","name":"Stabilizer","cost":10,"rarity":"Uncommon",
		 "desc":"-2° spread (tighter shots)."},
		# Elemental Power items
		{"kind":"item","id":"elemental_amp","name":"Elemental Amplifier","cost":14,"rarity":"Uncommon",
		 "desc":"+10% Elemental Power."},
		{"kind":"item","id":"elemental_catalyst","name":"Elemental Catalyst","cost":18,"rarity":"Rare",
		 "desc":"+20% Elemental Power."},
		{"kind":"item","id":"elemental_core","name":"Elemental Core","cost":22,"rarity":"Epic",
		 "desc":"+30% Elemental Power."},
		{"kind":"item","id":"arcanum","name":"Arcanum","cost":26,"rarity":"Legendary",
		 "desc":"+40% Elemental Power."},
		# Cross-synergy items
		{"kind":"item","id":"volatile_rounds","name":"Volatile Rounds","cost":16,"rarity":"Rare",
		 "desc":"Non-explosive hits have a chance to explode."},
		{"kind":"item","id":"elemental_fuse","name":"Elemental Fuse","cost":18,"rarity":"Rare",
		 "desc":"Non-elemental hits may inflict a random element."},
		{"kind":"item","id":"payload_catalyst","name":"Payload Catalyst","cost":20,"rarity":"Epic",
		 "desc":"Explosions may proc a random element."},
		{"kind":"item","id":"superconductor","name":"Superconductor","cost":22,"rarity":"Epic",
		 "desc":"Shock effects arc to more targets and reach farther."},
		# Turret projectile speed items (infrequent)
		{"kind":"item","id":"turret_servos","name":"Servomotors","cost":16,"rarity":"Rare",
		 "desc":"+20% Turret Projectile Speed."},
		{"kind":"item","id":"gyro_stabilizer","name":"Gyro Stabilizer","cost":22,"rarity":"Epic",
		 "desc":"+35% Turret Projectile Speed."},
		# Turret Power items
		{"kind":"item","id":"toolkit","name":"Toolkit","cost":12,"rarity":"Uncommon",
		 "desc":"+10% Turret Power."},
		{"kind":"item","id":"engineer_manual","name":"Engineer Manual","cost":16,"rarity":"Rare",
		 "desc":"+20% Turret Power."},
]

static func weapons() -> Array[Dictionary]:
	# Return the shared catalog. Callers should not mutate entries.
	# If mutation is needed, call .duplicate(true) on entries.
	return WEAPONS

static func items() -> Array[Dictionary]:
	# Return the shared catalog. Callers should not mutate entries.
	return ITEMS

static func rarity_color(r: String) -> Color:
	match r:
		"Common":
			return Color(0.85, 0.85, 0.85)
		"Uncommon":
			return Color(0.4, 1.0, 0.4)
		"Rare":
			return Color(0.4, 0.6, 1.0)
		"Epic":
			return Color(0.8, 0.4, 1.0)
		"Legendary":
			return Color(1.0, 0.7, 0.2)
		_:
			return Color(1, 1, 1)

static func rarity_color_hex(r: String) -> String:
	# Returns hex without leading '#'
	return rarity_color(r).to_html(false)

static func generate_offers(count: int, wave: int = 1) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	pool.append_array(weapons())
	pool.append_array(items())
	var offers: Array[Dictionary] = []
	if pool.is_empty() or count <= 0:
		return offers
	# Cheaper sampling: shuffle once and take the first N
	pool.shuffle()
	var take: int = min(count, pool.size())
	for i in range(take):
		var base: Dictionary = pool[i]
		var offer: Dictionary = (base.duplicate(true) as Dictionary)
		# Chance to roll higher tier for weapons increases with wave
		if String(offer.get("kind","")) == "weapon":
			var t: int = _roll_weapon_tier(wave)
			if t > 1:
				offer["tier"] = t
				# Scale cost for higher tier
				var base_cost: int = int(offer.get("cost", 10))
				var mult: float = pow(1.5, float(t - 1))
				offer["cost"] = int(round(base_cost * mult))
		offers.append(offer)
	return offers

static func _roll_weapon_tier(wave: int) -> int:
	# Increasing probabilities by wave; capped to reasonable maxima
	var w: int = max(1, wave)
	var p2: float = min(0.05 + 0.02 * float(w - 1), 0.55)
	var p3: float = min(0.01 + 0.01 * float(w - 1), 0.30)
	var p4: float = min(0.00 + 0.005 * float(w - 1), 0.15)
	var p5: float = min(0.00 + 0.002 * float(w - 1), 0.08)
	# Normalize tiers by rolling from highest to lowest
	var r := randf()
	if r < p5:
		return 5
	r -= p5
	if r < p4:
		return 4
	r -= p4
	if r < p3:
		return 3
	r -= p3
	if r < p2:
		return 2
	return 1
