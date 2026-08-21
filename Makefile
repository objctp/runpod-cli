RP ?= ./bin/rp

.PHONY: install fmt lint test check docs hooks package stock volumes serverless pods destroy

install:
	@ln -sf "$(CURDIR)/bin/rp" /usr/local/bin/rp 2>/dev/null || echo "Add $(CURDIR)/bin to your PATH instead"

fmt:
	shfmt -i 2 -w $$(find lib commands tests -name '*.sh') bin/rp install.sh

lint:
	shellcheck lib/*.sh commands/*.sh bin/rp install.sh

test:
	bashunit tests

check: lint test

# Regenerate docs/ from the `rp doc` reference blocks in the command sources
# (scripts/gen-manual.sh reads `bin/rp doc`). Run after editing any `# doc:`
# comment so the manual stays in sync with the CLI.
docs:
	@./scripts/gen-manual.sh

# Point git at the committed hooks in .githooks (the pre-commit hook
# regenerates docs/ and stages it, so the manual never drifts). Run once per
# clone; it sets core.hooksPath locally, which only affects this repo.
hooks:
	git config core.hooksPath .githooks
	@echo "git hooks now resolve from .githooks (pre-commit syncs docs/)"

# Build the release tarball + SHA256SUMS locally, mirroring the
# .github/workflows/release.yml steps (version stamped into a staged copy so the
# working tree's lib/_version.sh placeholder is left untouched). Run without a
# git tag to inspect the artefact shape before publishing.
package:
	@set -e; \
	VERSION=$$(git describe --tags --always 2>/dev/null | sed 's/-.*//' || true); \
	[ -n "$$VERSION" ] || VERSION=0.0.0-dev; \
	STAGE=$$(mktemp -d); \
	trap "rm -rf $$STAGE" EXIT; \
	cp -R bin lib commands LICENSE "$$STAGE"/; \
	printf 'RP_VERSION="%s"\n' "$$VERSION" > "$$STAGE/lib/_version.sh"; \
	tar czf "rp-$$VERSION.tar.gz" -C "$$STAGE" bin lib commands LICENSE; \
	sha256sum "rp-$$VERSION.tar.gz" > SHA256SUMS; \
	echo "built rp-$$VERSION.tar.gz + SHA256SUMS"

stock:
	@$(RP) stock gpu; echo; $(RP) stock dc

volumes:
	$(RP) volume list

serverless:
	$(RP) serverless list

pods:
	$(RP) pod list

destroy:
	@$(RP) serverless list; $(RP) pod list; $(RP) volume list
	@echo "delete with: rp <resource> delete <id>"
