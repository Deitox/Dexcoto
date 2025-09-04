class_name ShopDB
extends Node

static func weapons() -> Array[Dictionary]:
    return [
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
         "desc":"Rapid low-damage stream.",
         "fire_interval":0.08, "damage":3, "speed":420, "projectiles":1, "color": Color(1,0.6,0.2)},
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
    ]

static func items() -> Array[Dictionary]:
    return [
        {"kind":"item","id":"money_charm","name":"Money Charm","cost":12,"rarity":"Uncommon",
         "desc":"Earn 20% more currency."},
        {"kind":"item","id":"turret","name":"Turret","cost":18,"rarity":"Rare",
         "desc":"Place a stationary turret next wave."},
        {"kind":"item","id":"scope","name":"Scope","cost":10,"rarity":"Uncommon",
         "desc":"+1 projectile to all weapons."},
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
        {"kind":"item","id":"ammo_belt","name":"Ammo Belt","cost":12,"rarity":"Uncommon",
         "desc":"+1 projectile to all weapons."},
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
    ]

static func generate_offers(count: int, wave: int = 1) -> Array[Dictionary]:
    var pool: Array[Dictionary] = []
    pool.append_array(weapons())
    pool.append_array(items())
    var offers: Array[Dictionary] = []
    for i in range(count):
        if pool.is_empty():
            break
        var idx := randi() % pool.size()
        var base: Dictionary = pool[idx]
        pool.remove_at(idx)
        var offer: Dictionary = base.duplicate(true)
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
