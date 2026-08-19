# Changelog

## Unreleased

### Changed

- Fix 401 from quoted .env values

### Fixed

- Make npm publish idempotent in release workflow

## [1.0.0] - 2026-08-17

### Added

- Exit-code contract — map 404->4 and rejected key (401/403)->3
- Adopt v2 cluster, catalog, ssh-key surfaces and templateId

### Fixed

- Source lib/paginate.sh in resource_test setup
- Resolve Linux CI failures in unit suite
- Low-severity security and quality findings
- Address code-review on v1.0 publish
- Pin Homebrew/actions/setup-homebrew to a valid ref

## [0.4.0] - 2026-08-02

### Added

- Rename endpoint to serverless and expand billing surface
- Add --registry <id> flag for private-image creds
- Add rp template update plus --public/--registry on template create
- Add per-resource id filters and time-window flags
- Add rp serverless workers and releases verbs
- Migrate rp stock dc to v2 catalog/datacenters (keep S3 column via GraphQL fallback)
- Add CPU-only pods and rp stock cpus
- Add `rp registry delegations` sub-resource
- Expose `--type` storage tier on create
- Add global-networking, locked, volume-path flags and mount mutex guard
- Add live SSE log streaming for pods and serverless workers
- Add filter flags to `rp stock gpu`
- Add `rp api` escape hatch, list pagination, and file-based auth
- Add `rp doc` for user-facing command and verb documentation
- Complete and standardise `rp doc` across every command and ver

### Changed

- Apply conventions across the codebase
- Provision bash 4+ on macOS and pin bashunit via action
- Generalize CLI framing and centralize tunable defaults
- Rewrite rp::table as portable, column-aligned renderer

### Fixed

- Surface transport errors and align docs with behaviour
- Align create/update body to the live v2 spec
- Merge --env over template env on create
- Pre-check required flags before pod and serverless create

## [0.3.0] - 2026-07-30

### Added

- Migrate control plane to Runpod REST API v2

## [0.2.0] - 2026-07-27

### Added

- Add `run` verb to invoke serverless endpoints on the data plane

## [0.1.0] - 2026-07-21

### Changed

- Initial CLI implementation of Runpod's APIs
