# Dexcoto

A tiny Godot 4, Brotato-inspired arena survival prototype. Move around, auto-fire toward the nearest enemy, survive waves that ramp over time.

## Run

- Open this folder in Godot 4.x (Project Manager → Import → select `project.godot`).
- Press F5 to run.

## Controls

- Move: WASD or Arrow Keys (`ui_left`, `ui_right`, `ui_up`, `ui_down`).

## Structure

- `project.godot`: Godot project settings.
- `scenes/Main.tscn`: Root scene (timers, UI, spawns, wave logic).
- `scenes/Player.tscn`: Player character with auto-fire.
- `scenes/Enemy.tscn`: Basic enemy that chases and deals contact damage.
- `scenes/Bullet.tscn`: Bullet projectile.
- `scenes/Beam.tscn`: Beam visual used when projectile speed is very high.
- `scripts/*.gd`: GDScript logic for the above.

## Performance Notes

- The bullet pool caps extreme projectile speeds to avoid lag. Above a speed threshold, shots render as a short-lived beam and convert excess speed into proportional damage, reducing spawned objects while keeping builds powerful.

## Rewards

- Enemies now grant XP and currency proportional to their power. Higher-tier enemies yield more rewards; the score still reflects kills, while XP and currency scale up with enemy health/damage.

## Next Ideas

- Add XP and level-up choices between waves.
- More enemy types and elites.
- Items with modifiers to fire rate, damage, move speed.
- Dashes or defensive skills.
- Arena boundaries and hazards.
