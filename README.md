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
- `scripts/*.gd`: GDScript logic for the above.

## Next Ideas

- Add XP and level-up choices between waves.
- More enemy types and elites.
- Items with modifiers to fire rate, damage, move speed.
- Dashes or defensive skills.
- Arena boundaries and hazards.
