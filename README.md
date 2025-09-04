# Dexcoto

A tiny Godot 4 arena-survivor prototype (Brotato‑inspired). Move, auto‑aim at the nearest enemy, and survive timed waves that ramp up. Between waves, pick upgrades and shop for items/weapons.

## Run

- Open this folder in Godot 4.x (Project Manager > Import > select `project.godot`).
- Press F5 to run the main scene (`scenes/Main.tscn`).

## Controls

- Move: WASD or Arrow Keys (`ui_left`, `ui_right`, `ui_up`, `ui_down`).
- Pause/Resume: Esc.
- Intermissions: use the mouse to choose upgrades and buy items.
- Shop: left‑click to buy, right‑click an offer to lock/unlock it, Reroll to refresh unlocked offers.

## Gameplay Loop

- Survive a wave (timed). Enemies scale by wave and tier.
- Intermission: take level‑up upgrades equal to levels gained during the wave.
- Shop: spend currency on items/weapons; start the next wave when ready.

## Systems & Features

- Weapons (up to 6 slots): Auto‑fire toward nearest enemy. Three of the same weapon at the same tier merge into one of the next tier. Higher tiers increase damage and fire rate; every 3 tiers adds a projectile.
- Items: Stackable effects like attack speed, regen, lifesteal, +projectiles, currency gain, and placing turrets for the next wave.
- Turrets: Stationary allies purchased in the shop. When too many accumulate, groups of 3 same‑tier turrets merge up to keep counts reasonable.
- Projectiles & Beams: Excessive projectile counts are capped; overflow converts to proportional damage. Extremely fast shots become short‑lived beams to reduce object churn.
- Enemies & Boss: Enemies scale by tier; bosses scale by wave. Killing grants score (kills), XP, and currency based on enemy power.
- Character Select: Choose a starter (from weapon list) at the beginning.
- Pause Menu: Resume/Restart/Quit while paused.

## Performance Notes

- Object Pooling: Bullets, enemies, and turrets use pools to reuse nodes.
- Adaptive Pressure: Spawning adjusts rate and enemy tier under load; hard/soft caps prevent runaway counts.
- Rendering: Uses the mobile renderer by default for broad compatibility (`project.godot`).
- Arena Bounds: Walls/outline are sized to the viewport by default; see `scripts/arena_bounds.gd` for options.

## Project Structure

- `project.godot`: Godot project settings (main scene, renderer, resolution).
- `scenes/Main.tscn`: Root scene (UI, timers, pools, wave/intermission/shop/upgrade panels).
- `scenes/Player.tscn`, `scenes/Enemy.tscn`, `scenes/Boss.tscn`, `scenes/Bullet.tscn`, `scenes/Beam.tscn`, `scenes/Turret.tscn`: Actors and visuals.
- `scripts/main.gd`: Game flow, spawning, UI updates, shop/upgrade handling, HUD, character select, turret merging.
- `scripts/player.gd`: Movement, targeting, weapons (merge logic, tier scaling), firing, stats, upgrades, caps.
- `scripts/enemy.gd`, `scripts/boss.gd`: Scaling, rewards, contact damage, pool integration.
- `scripts/bullet.gd`, `scripts/beam.gd`, `scripts/*_pool.gd`: Projectile behavior, beam rendering, and pooling.
- `scripts/shop.gd`, `scripts/shop_panel.gd`: Weapons/items database and shop UI, including right‑click to lock offers.
- `scripts/upgrades.gd`, `scripts/upgrade_panel.gd`: Rarity‑weighted upgrade database and selection UI.
- `scripts/arena_bounds.gd`: Walls and outline sized to viewport or fixed arena.
- `scripts/item_summary.gd`, `scripts/notifications.gd`, `scripts/pause_panel.gd`: Intermission item summary, toast notifications, and pause handling.

## Extending

- New weapons/items: add entries to `scripts/shop.gd` (weapons can set base stats; items describe effects that `main.gd`/`player.gd` apply when purchased).
- New upgrades: add definitions to `scripts/upgrades.gd` and handle their effects in `scripts/player.gd:apply_upgrade`.
- New enemies: extend the enemy scene/script or add variants and update spawning logic in `scripts/main.gd`/`scripts/enemy_pool.gd`.
- Tuning caps: see constants in `scripts/main.gd`, `scripts/player.gd`, `scripts/turret.gd`, and `scripts/bullet_pool.gd`.

## Known Limitations

- Programmer art; no audio.
- No save/progression between runs.
- Some UI strings were updated recently; if you see odd characters in labels, they likely come from old scene text and can be re‑typed in the editor.

## Credits

- Built with Godot 4.x by Deitox. Inspired by Brotato and other arena survival games.

