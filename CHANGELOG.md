# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to
Semantic Versioning (SemVer) when practical.

## [Unreleased]
- Balance polish based on playtesting feedback.
- Export presets and CI artifacts.

## [0.2.0] - 2025-09-11

### Added
- Crit system with 100% hard cap; excess crit chance converts to crit damage.
- Defense stat (Damage Taken multiplier) and defense items:
  - Kevlar Vest, Riot Armor, Plated Armor, Nanoshield.
- New stacking weapons (on-kill):
  - Assassin (+2% Crit Chance per stack; overflow → crit damage).
  - Guardian (+2% Defense per stack).
  - Accelerator (+5% Projectile Speed per stack).
  - Sprinter (+2% Move Speed per stack; benefits from overflow → currency).
- Move Speed cap (3× base). Overflow converts to Currency Gain (tracked and shown).
- Projectile speed → beam conversion: “Proj Speed → Beam Dmg” now appears in Overflows.
- True channel beams:
  - Continuous beam once speed threshold is exceeded (no rapid line spam).
  - Beam origin follows the shooter (player/turret) while channeling.
  - Robust retargeting (cone-first then ray, skips pooled/inactive/0‑HP/invisible enemies).
  - Graceful linger while firing (interval-scaled), and hidden when no valid target to avoid “shooting air.”
- Floating damage numbers:
  - Added to bosses and burn (Ignite) DoT ticks; general hit feedback already present.
- Stats panel “Overflows” section consolidating conversions:
  - Attack Speed → Damage, Projectiles → Damage, Move Speed → Currency, Proj Speed → Beam Dmg.
- Cap coloring: Attack Speed and Move Speed turn orange at cap.
- Detailed anti-teleport guard instrumentation printing scene/UI flags, enemy and beam snapshots.

### Changed
- Wave duration scales +4s per wave (capped at 90s / 1.5 min).
- Enemy caps (soft/hard) scale by wave (up to ~4×) for higher late‑wave density.
- XP curve made non-linear (quadratic) to slow late‑game leveling.
- Shop pricing scaled globally by wave (×1.10^(wave−1)) after tier multipliers.
- Stats panel layout cleaned up (removed explicit Attack Speed cap row; kept Min Interval).

### Fixed
- Beams flicker/no-DPS issues:
  - Retargeting avoids pooled/inactive targets; hides beam when no valid target rather than drawing to stale endpoints.
  - Channel beams no longer “shoot at emptiness” during spawn gaps.
- Various GDScript parse/typing issues (ternary, indentation, explicit Vector2 types).
- Bosses now support floating damage numbers the same as enemies.
- Stats panel errors when reading player state (used `get("weapons")` and type checks).

### Developer / Diagnostics
- `beams` group added; beams expose `is_channeling()` and `debug_state()` for quick snapshots.
- Anti-teleport guard logs:
  - Step distance, limit, delta, velocity vector/magnitude, previous/attempted positions.
  - paused/intermission/awaiting_character/ui_modal flags.
  - Enemy totals and active+visible counts.
  - Beam totals, channeling/visible counts, and a few beam state samples.

## [0.1.0] - 2025-08-XX
- Initial public prototype (waves, shop, upgrades, basic weapons/items, pooling, mobile renderer).


[Unreleased]: https://example.com/compare/0.2.0...HEAD
[0.2.0]: https://example.com/releases/0.2.0
[0.1.0]: https://example.com/releases/0.1.0
