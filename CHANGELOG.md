# Changelog

## [Unreleased]

### Added
- `Composite.apply_tagged/1` and `Composite.apply_tagged/3` — return
  `:unchanged` when the applied query compares equal (`==`) to the input, or
  `{:changed, query}` otherwise. This lets callers short-circuit instead of
  passing an unchanged query to `Repo.all/1`.

### Changed
- Minimum Elixir version bumped from `~> 1.9` to `~> 1.14`, matching Ecto's
  own minimum.
- Declaring the same `dependency/4` name twice now emits `IO.warn/1`. The
  previous loader is still overwritten (behavior preserved).
- Documented that duplicate `param/4` paths chain handlers in declaration
  order — this is intentional, not a bug.

### Fixed
- Dependencies now load in the order specified by `:requires`. The previous
  `MapSet`-based implementation did not preserve declaration order.
- `strict: true` no longer crashes when a known nested parameter has a `nil`
  value or when both a parent path and its nested path are declared.

### Internal
- Refactored `maybe_raise_on_unknown_params` to use `Map.fetch/2` instead of
  `Enum.find/2` (O(n·m) → amortized O(n)).
- Added GitHub Actions CI (tests on Elixir 1.14 / OTP 25 and 1.19.4 / OTP 28.3,
  plus `mix format --check-formatted`).
- Added runnable doctests for `default_ignore?/1`, `new/2`, `apply_tagged/1`.
- Updated development dependencies.

## [0.6.0] - 2025-08-30

### Added
- Configurable default `:ignore?` via `new/1` and `new/3` options ([#10]).

## [0.5.1] - 2025-04-02

### Fixed
- Mark dependency as loaded immediately after loading to prevent re-entry
  loops with cross-dependencies.

## [0.5.0] - 2024-11-09

### Added
- `:strict` option on `new/1` / `new/3` — raises when params contain keys
  not declared via `param/4` ([#8]).
- `Inspect` protocol implementation that hides internal struct fields.
- Link to introductory article in package metadata.

## [0.4.3] - 2024-02-19

### Changed
- Documentation housekeeping: extended README, added license file, wired
  README as the main docs page.

## [0.4.2] - 2022-06-15

### Fixed
- Exception in `Composite.apply/1` when the input query was a module name ([#5]).

## [0.4.1] - 2022-05-11

### Fixed
- Don't load cross-dependencies twice.

## [0.4.0] - 2021-11-19

### Added
- `Composite.force_require/2` — forces a dependency load regardless of params.
- `dependency/4` loaders with arity 2 — receive `params` as the second argument.

## [0.3.0] - 2021-09-11

### Added
- Param handlers with arity 1 (receive only the query).
- `:ignore_requires` option — load dependencies even when the value is ignored
  (useful together with a custom `:on_ignore`).
- Extended default `:ignore?` implementation (recognises `nil`, `""`, `[]`, `%{}`).

### Changed
- `param/4` now raises on unknown options instead of silently ignoring them.

## [0.2.1] - 2020-12-18

### Added
- Basic description and code examples in README.

## [0.2.0] - 2020-11-20

Initial public release.

### Added
- Core building blocks: `new/0`, `new/2`, `param/3`, `param/4`, `dependency/3`,
  `dependency/4`, `apply/1`, `apply/3`.
- `:on_ignore` option on `param/4`.
- `Ecto.Queryable` implementation for direct use with `Repo.*` functions.
- Support for `:requires` specified as a function of the parameter's value.

[Unreleased]: https://github.com/fuelen/composite/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/fuelen/composite/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/fuelen/composite/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/fuelen/composite/compare/v0.4.3...v0.5.0
[0.4.3]: https://github.com/fuelen/composite/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/fuelen/composite/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/fuelen/composite/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/fuelen/composite/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/fuelen/composite/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/fuelen/composite/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/fuelen/composite/releases/tag/v0.2.0

[#5]: https://github.com/fuelen/composite/issues/5
[#8]: https://github.com/fuelen/composite/issues/8
[#10]: https://github.com/fuelen/composite/issues/10
