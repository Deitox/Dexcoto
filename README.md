# Dexcoto

Tiny Godot 4 arena-survivor prototype. Move, auto-aim at the nearest enemy, and survive timed waves that ramp up. Between waves, pick upgrades and shop for items/weapons.

## Requirements

- Godot 4.4 (or any 4.x that supports the 4.4 feature flag in `project.godot`).

## Run

- Open this folder in Godot (Project Manager → Import → select `project.godot`).
- Press F5 to run the main scene (`scenes/Main.tscn`).

## Controls

- Move: WASD or Arrow Keys (`ui_left`, `ui_right`, `ui_up`, `ui_down`).
- Pause/Resume: Esc.
- Intermissions: use the mouse to choose upgrades and buy items.
- Shop: left-click to buy, right-click an offer to lock/unlock it, use Reroll to refresh unlocked offers.

## Gameplay Loop

- Survive a timed wave. Enemies scale by wave and by their tier.
- Intermission: take level-up upgrades equal to levels gained during the wave.
- Shop: spend currency on items/weapons; start the next wave when ready.
- Boss: a boss spawns every 5th wave.

## Systems & Features

- Weapons (up to 6 slots): Auto-fire toward the nearest enemy. Three of the same weapon at the same tier merge into one of the next tier. Higher tiers increase damage and fire rate; every 3 tiers adds a projectile.
- Items: Stackable effects like attack speed, regen, lifesteal, +projectiles, currency gain, projectile speed, max HP, and placing turrets for the next wave.
- Turrets: Stationary allies purchased in the shop. If too many accumulate, groups of 3 same-tier turrets merge up to keep counts reasonable.
- Projectiles & Beams: Excessive projectile counts are capped; overflow converts into proportional damage. Extremely fast shots convert into short-lived beams to reduce object churn.
- Enemies & Boss: Enemies scale by tier; bosses scale by wave. Kills grant score, XP, and currency based on enemy power.
- Character Select: Choose a starter at the beginning (from the weapon list), which sets your color and initial weapon.
- HUD & Shop UX: Weapon HUD shows tier coloring; new/merged weapons get temporary highlights. Shop buttons color by rarity/tier; right-click locks offers. Reroll costs 5 and preserves locked, unsold offers.

## Performance Notes

- Object Pooling: Bullets, enemies, and turrets use pools to reuse nodes.
- Adaptive Pressure: Spawn rate and enemy tier adjust under load; soft and hard caps prevent runaway entity counts.
- Rendering: Uses the mobile renderer by default for broad compatibility (set in `project.godot`).
- Arena Bounds: Walls/outline sized to the viewport or a fixed arena; configurable in `scripts/arena_bounds.gd`.

## Content Overview

- Weapons (selection): Pistol, SMG, Shotgun, Rifle, Minigun, Cannon, Laser, Railgun, Flamethrower, Boomerang, Crossbow, Burst Pistol, Splitter, Cannon Mk.II.
- Items (selection): Money Charm, Turret, Scope, Overcharger, Adrenaline, Lifesteal Charm, Boots, Caffeine, Ammo Belt, Aerodynamics, Protein Bar, Medkit, Greed Token, Vampiric Orb, Power Core, Stabilizer.
- Upgrades: Weighted by rarity (Common → Legendary). Categories include Attack Speed, Damage, Move Speed, Max HP, Projectile Speed, Regeneration, and +Projectiles.

## Project Structure

- `project.godot`: Godot project settings (main scene, renderer, resolution).
- `scenes/Main.tscn`: Root scene (UI, timers, pools, wave/intermission/shop/upgrade panels).
- `scenes/Player.tscn`, `scenes/Enemy.tscn`, `scenes/Boss.tscn`, `scenes/Bullet.tscn`, `scenes/Beam.tscn`, `scenes/Turret.tscn`: Actors and visuals.
- `scripts/main.gd`: Game flow, spawning, UI updates, shop/upgrade handling, HUD, character select, turret merging, boss waves.
- `scripts/player.gd`: Movement, targeting, weapon firing, merges, stat caps/overflow, upgrades.
- `scripts/enemy.gd`, `scripts/boss.gd`: Scaling, rewards, contact damage, pool integration.
- `scripts/bullet.gd`, `scripts/beam.gd`, `scripts/*_pool.gd`: Projectile behavior, beam rendering, and pooling.
- `scripts/shop.gd`, `scripts/shop_panel.gd`: Weapons/items database and shop UI (right-click lock, reroll).
- `scripts/upgrades.gd`, `scripts/upgrade_panel.gd`: Rarity-weighted upgrade database and selection UI.
- `scripts/arena_bounds.gd`: Walls and outline sized to viewport or fixed arena.
- `scripts/item_summary.gd`, `scripts/notifications.gd`, `scripts/pause_panel.gd`: Intermission item summary, toasts, and pause handling.

## Extending

- New weapons/items: add entries to `scripts/shop.gd` (weapons define base stats; items describe effects applied by `main.gd`/`player.gd`).
- New upgrades: add definitions to `scripts/upgrades.gd` and handle their effects in `scripts/player.gd:apply_upgrade`.
- New enemies: extend enemy scenes/scripts or add variants and update spawning logic in `scripts/main.gd`/`scripts/enemy_pool.gd`.
- Tuning caps: see constants in `scripts/main.gd`, `scripts/player.gd`, `scripts/turret.gd`, and `scripts/bullet_pool.gd`.

## Known Limitations

- Programmer art; no audio.
- No save/progression between runs.
- If you see odd characters in old UI labels, retype them in the editor (encoding artifacts in some legacy scene text).

## Credits

- Built with Godot 4.x by Deitox. Inspired by Brotato and other arena survival games.

