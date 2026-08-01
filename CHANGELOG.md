# Changelog

## Unreleased

### Added

- Rename endpoint to serverless and expand billing surface
- Add --registry <id> flag for private-image creds
- Add rp template update plus --public/--registry on template create
- Add per-resource id filters and time-window flags
- Add rp serverless workers and releases verbs

### Changed

- Apply conventions across the codebase
- Provision bash 4+ on macOS and pin bashunit via action

### Fixed

- Surface transport errors and align docs with behaviour
- Align create/update body to the live v2 spec
- Merge --env over template env on create

## [0.3.0] - 2026-07-30

### Added

- Migrate control plane to Runpod REST API v2

## [0.2.0] - 2026-07-27

### Added

- Add `run` verb to invoke serverless endpoints on the data plane

## [0.1.0] - 2026-07-21

### Changed

- Initial CLI implementation of Runpod's APIs
