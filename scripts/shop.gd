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
