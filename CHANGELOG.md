# Changelog

## Unreleased

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
