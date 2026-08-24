# Changelog

## Unreleased

### Added

- Add filters and detail columns to rp stock dc

### Changed

- Add task-oriented how-to guides
- Improve example formatting in command reference blocks

### Fixed

- Redirect GitHub Pages root to /manual/

## [1.2.0] - 2026-08-22

### Added

- Add spot pod support via --bid-per-gpu and --interruptible
- Add --insecure flag to skip TLS verification for in-pod runs
- Add --public-ip for community-cloud pods
- Add per-user multi-account credential store
- Import API key from runpodctl config
- Add MkDocs Material manual published to GitHub Pages

### Changed

- Add Scope note clarifying rp is not a runpodctl replacement
- Document the `rp auth use` alias and fix summary shape

### Fixed

- Resolve lint and docs-compat regressions
- Honour --user in rp ssh info for non-root containers
- Satisfy shellcheck SC2015 in account write

## [1.1.0] - 2026-08-21

### Added

- Post-parse flag-alias layer (RP_FLAG_ALIASES)
- Serverless data-plane verbs status and health
- Add --ssh flag to rp pod create (startSsh:true)
- Add --min-cuda-version flag to rp pod create (gpu.minCudaVersion)
- Add --compute-type GPU|CPU coercion alias to rp pod create
- Extend serverless update with --template-id, --name, and scale-by/scale-threshold
- Add --volume-mount-path to template create and update
- Add rp hub list (GraphQL listings, client-side --type filter)
- Extend `rp account` with email and notify toggles
- Align ssh keys to v2 REST and add GraphQL-sunset readiness

### Changed

- Annotate runpodctl-compatible flag aliases in --help and rp doc
- Regenerate manual to reflect v2-aligned ssh keys and S3 wording
- Make ssh-key the single source of truth and deprecate ssh key verbs

### Fixed

- Make npm publish idempotent in release workflow
- 401 from quoted .env values
- Test polluting cwd with a stray '15' file
- Accept case-insensitive values for all-caps enum flags

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
