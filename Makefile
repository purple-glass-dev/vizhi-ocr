# Vizhi OCR — build & release tasks.
#
# Versioning is driven by git tags (vX.Y.Z). Bump with `make bump-patch|bump-minor|bump-major`,
# then `make app` to produce dist/VizhiOCR.app with the version + commit hash baked in

SHELL := /bin/bash

VERSION := $(shell git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0)
COMMIT  := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)

.PHONY: help version bump-patch bump-minor bump-major app dmg notarized-dmg cask test

help:
	@echo "Vizhi OCR — make targets:"
	@echo "  make version       Show the current version tag and commit"
	@echo "  make bump-patch    v$(VERSION:v%=%) -> next patch tag (bug fixes)"
	@echo "  make bump-minor    Next minor tag (new features, backwards compatible)"
	@echo "  make bump-major    Next major tag (breaking changes)"
	@echo "  make app           Build dist/VizhiOCR.app (version + commit baked in)"
	@echo "  make dmg           Build a distributable DMG"
	@echo "  make notarized-dmg Build + notarize the DMG, then refresh the Homebrew cask"
	@echo "  make cask          Refresh the Homebrew cask from the current DMG (external tap)"
	@echo "  make test          Run the Swift test suite"

version:
	@echo "Version: $(VERSION)"
	@echo "Commit:  $(COMMIT)"

bump-patch:
	@scripts/bump-version.sh patch

bump-minor:
	@scripts/bump-version.sh minor

bump-major:
	@scripts/bump-version.sh major

app:
	@scripts/build-app.sh

dmg:
	@scripts/build-dmg.sh

notarized-dmg:
	@scripts/notarize.sh

cask:
	@scripts/update-cask.sh

test:
	@swift test
