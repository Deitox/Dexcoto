# Dexcoto

Tiny Godot 4 arena-survivor prototype. Move, auto-aim at the nearest enemy, and survive timed waves that ramp up. Between waves, pick upgrades and shop for items/weapons.

## Requirements

- Godot 4.4 (or any 4.x that supports the 4.4 feature flag in `project.godot`).

## Run

- Open this folder in Godot (Project Manager > Import > select `project.godot`).
- Press F5 to run the main scene (`scenes/Main.tscn`).

## CLI

- Run game: `godot4 --path .`
- Open editor: `godot4 --path . --editor`

## Version Notes

- If using Godot 4.0-4.3, update or remove  `config/features` in `project.godot` (currently set to `4.4`) so it matches your editor version. 

## Controls

- Move: WASD or Arrow Keys (`ui_left`, `ui_right`, `ui_up`, `ui_down`).
- Pause: Esc. While in shop/upgrade/character select (already paused), Esc opens the Pause overlay without resuming the game. Closing the overlay returns to that paused UI. From gameplay, Esc toggles pause normally.
- Intermissions: use the mouse to choose upgrades and buy items.
- Shop: left-click to buy, right-click an offer to lock/unlock it, use Reroll to refresh unlocked offers.

## Gameplay Loop

- Survive a timed wave. Enemies scale by wave and by their tier.
- Intermission: take level-up upgrades equal to levels gained during the wave.
- Shop: spend currency on items/weapons; start the next wave when ready.
- Boss: a boss spawns every 5th wave.

## Systems & Features

- Weapons (up to 6 slots): Auto-fire toward the nearest enemy. Three of the same weapon at the same tier merge into one of the next tier. Higher tiers increase damage and fire rate; every 3 tiers add two projectiles.
- Items: Stackable effects like attack speed, regen, lifesteal, currency gain, projectile speed, max HP, placing turrets for the next wave, and turret-specific stats (Turret Power, Turret Projectile Speed).
- Turrets: Stationary allies purchased in the shop or spawned by certain weapons on kill. If too many accumulate, groups of 3 same-tier turrets merge up to keep counts reasonable. Turret damage scales with your Turret Power stat.
- Projectiles & Beams: Excessive projectile counts are capped; overflow converts into proportional damage. Very fast shots convert into short-lived beams to reduce object churn. The beam threshold is configurable in `scripts/bullet_pool.gd`.
- Enemies & Boss: Enemies scale by tier; bosses scale by wave. Kills grant score, XP, and currency based on enemy power.
- Character Select: Choose a starter at the beginning (from the weapon list), which sets your color and initial weapon.
- HUD & Shop UX: Weapon HUD shows tier coloring; new/merged weapons get temporary highlights. Shop buttons color by rarity/tier; right-click locks offers. Reroll costs 5 and preserves locked, unsold offers.
- Elemental System: Elemental weapons scale with your Elemental Power stat (upgrades). Fire can Ignite (DoT), Cryo can Freeze (briefly immobilize), Shock can Arc to nearby enemies, and Void can inflict Vulnerable (take increased damage) — chances and potency grow with Elemental Power.

### Kill-Stacking Weapons

Some weapons grant stacking bonuses on kill. Higher tiers require fewer kills for each stack:

- Berserker: kills grant +2% Damage per stack.
- Tempo: kills grant +2% Attack Speed per stack.
- Bulwark: kills grant +3 Max HP per stack.
- Constructor: kills spawn a Turret near the player after a few kills; benefits from Turret Power.

## Performance Notes

- Object Pooling: Bullets, enemies, and turrets use pools to reuse nodes.
- Adaptive Pressure: Spawn rate and enemy tier adjust under load; soft and hard caps prevent runaway entity counts.
- Rendering: Uses the mobile renderer by default for broad compatibility (set in `project.godot`).
- Arena Bounds: Walls/outline sized to the viewport or a fixed arena; configurable in `scripts/arena_bounds.gd`.

## Content Overview

- Weapons (selection): Pistol, SMG, Shotgun, Rifle, Minigun, Cannon, Laser, Railgun, Flamethrower (Fire), Cryo Blaster (Cryo), Shock Rifle (Shock), Void Projector (Void), Boomerang, Crossbow, Burst Pistol, Splitter, Cannon Mk.II, Berserker (stacking damage), Tempo (stacking attack speed), Bulwark (stacking max HP), Constructor (spawns turrets on kill).
- Items (selection): Money Charm, Turret, Overcharger, Adrenaline, Lifesteal Charm, Boots, Caffeine, Aerodynamics, Protein Bar, Medkit, Greed Token, Vampiric Orb, Power Core, Stabilizer, Toolkit (+Turret Power), Engineer Manual (+Turret Power), Servomotors (+Turret Projectile Speed), Gyro Stabilizer (+Turret Projectile Speed).
- Upgrades: Weighted by rarity (Common through Legendary). Categories include Attack Speed, Damage, Move Speed, Max HP, Projectile Speed, Regeneration, Elemental Power, and Turret Power. Bonus projectiles now only come from weapon tier upgrades every 3 tiers (adds two).
- Elemental Power: Boosts elemental weapons' damage and effect chance/potency.
- Turret Power: Boosts turret damage.

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

## Tuning

- Enemies (in `scripts/main.gd`): `SOFT_CAP_ENEMIES`, `MAX_ENEMIES`, `GROUP_BASE_DELAY`, `GROUP_STAGGER`, `GROUP_GAP_MIN`, `GROUP_GAP_MAX`, and `wave_time`.
- Projectiles (in `scripts/player.gd`): `MAX_TOTAL_PROJECTILES`, `MAX_PROJECTILE_BONUS`, `MIN_WEAPON_INTERVAL`, `MAX_ATTACK_SPEED_MULT`; projectile overload soft cap ~200.
- Beams (in `scripts/bullet_pool.gd`): `SPEED_BEAM_THRESHOLD` controls when bullets convert to beams.

## Weapon Fields

- Base: `id`, `name`, `fire_interval`, `damage`, `speed`, `projectiles`, `color`.
- Elemental (optional): `element`, `element_proc`, `ignite_factor`, `ignite_duration`, `freeze_duration`, `arc_count`, `arc_radius`, `arc_factor`, `vuln`, `vuln_duration`.
- Explosive (optional): `explosive`, `expl_radius`, `expl_factor`.

## Troubleshooting

- Windows import/file locking issues: try `tools/fix_lock.ps1`.
- Console message "[Guard] Cancelled abnormal move": defensive anti-teleport check; safe to ignore.
- Strange degree symbol in old text (e.g., "-2A� spread"): run `python fix_degree_symbol.py` to replace with the intended "-2° spread" across the repo.

## Dev Notes

- Formatting helper: `normalize_gd_tabs.py` for consistent GDScript indentation.
- Useful groups/pools: `enemy_pool`, `turret_pool`, `projectiles`, `enemies`.

### GDScript “:=” Inference Fixers

Strict projects can fail on the warning “The variable type is being inferred from a Variant value…” when using `:=`. The tools below help suppress or target those safely:

- `tools/fix_gd_inference.py`:
  - Broad sweep. Rewrites single‑line `var name := expr` to `var name = expr` (preserves decorators and type hints), across all `.gd` files.
  - Usage:
    - Preview: `python tools/fix_gd_inference.py --report`
    - Apply: `python tools/fix_gd_inference.py --write [path]`

- `tools/fix_gd_inference_conservative.py`:
  - Conservative pass. Only rewrites when RHS “smells Variant‑y” (e.g., `get_node`, `.get(`, `.call(`, `load`, timers/tweens, etc.). Skips typed declarations by default.
  - Usage:
    - Preview: `python tools/fix_gd_inference_conservative.py --report`
    - Apply: `python tools/fix_gd_inference_conservative.py --write [path]`
    - Options: `--include-typed`, `--extra-token TOKEN`, `--list-patterns`

- `tools/fix_gd_inference_strict.py`:
  - CI‑friendly strict mode with line‑ending preservation, excludes, git‑scoped modes, backups, and prompts.
  - Defaults focus on dynamic APIs (node lookups, dynamic calls, resource loads; excludes math built‑ins).
  - Usage:
    - Preview (non‑zero exit if fixable): `python tools/fix_gd_inference_strict.py --report`
    - Apply to tracked files with backups: `python tools/fix_gd_inference_strict.py --write --git-tracked --backup`
    - Apply to a folder with confirm prompts: `python tools/fix_gd_inference_strict.py --write path/to/dir --confirm`
    - Options: `--exclude`, `--git-tracked | --staged | --changed-only`, `--include-typed`, `--extra-token`, `--list-patterns`, `--dry-run`

Recommended workflow:
1) Commit (or stash) changes.
2) Run a preview (`--report` / `--dry-run`) and review output.
3) Apply to a small subtree, build/test, then broaden scope.

## Modding

- See  `MODDING_SDK_README.md` for mod support, licenses (`MODDING_LICENSE.txt`), and third-party notices. 
- Commercial mods require the addendum in `COMMERCIAL_MOD_ADDENDUM_TEMPLATE.txt`.

## Export

- Use Project > Export to add a desktop preset and export binaries. No presets are committed in this repo.

## Known Limitations

- Programmer art; no audio.
- No save/progression between runs.
- If you see odd characters in old UI labels, retype them in the editor (encoding artifacts in some legacy scene text).

## License

- Game code: Proprietary. See `CODE_PROPRIETARY_NOTICE.txt` and `EULA.txt`.
- Modding SDK: MIT-licensed. See `LICENSE-SDK.txt` (SDK only) and `MODDING_SDK_README.md`.
- Modding terms: see `MODDING_LICENSE.txt` and the commercial template in `COMMERCIAL_MOD_ADDENDUM_TEMPLATE.txt`.
- Assets/content: see `ASSET-LICENSE.md` and `THIRD_PARTY_NOTICES.txt`.

## Credits

- Built with Godot 4.x by Deitox. Inspired by Brotato and other arena survival games.

## No Warranty

This project and all included materials are provided "as is" without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement. Use at your own risk.
