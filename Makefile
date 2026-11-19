# UltiRace — see docs/TOOLCHAIN.md for the underlying commands.
# GNU Make 3.81 compatible (macOS /usr/bin/make).

GODOT   ?= /Applications/Godot.app/Contents/MacOS/Godot
BLENDER ?= /Applications/Blender.app/Contents/MacOS/Blender
GODOT_DIR := godot
RACES   ?= 500
SHOT    ?= docs/screenshots/boot.png

.PHONY: help test test-go test-godot lint fixtures sync check-sync server balance assets e2e \
        import screenshot ios ios-export ios-device ios-run ios-check doctor preflight clean

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

test: test-go test-godot ## go test -race + Godot gdUnit4 tests (headless)

test-go: ## Go unit tests with the race detector
	go test -race ./...

lint: ## gofmt + go vet
	@out=$$(gofmt -l . 2>/dev/null | grep -v '^godot/'); if [ -n "$$out" ]; then echo "gofmt needed:"; echo "$$out"; exit 1; fi
	go vet ./...

import: ## Godot headless import (run after new assets)
	$(GODOT) --headless --path $(GODOT_DIR) --import >/dev/null 2>&1 || true

test-godot: import ## gdUnit4 tests in godot/test (headless)
	cd $(GODOT_DIR) && GODOT_BIN=$(GODOT) ./addons/gdUnit4/runtest.sh --headless --ignoreHeadlessMode -a res://test

fixtures: ## Go writes gamedata/fixtures
	ULTIRACE_WRITE_FIXTURES=1 go test ./... -run Fixture -count=1

sync: ## copy gamedata/ into godot/gamedata/ (json only)
	rm -rf $(GODOT_DIR)/gamedata && mkdir -p $(GODOT_DIR)/gamedata
	cd gamedata && find . -name '*.json' -o -name '*.txt' | while read f; do mkdir -p ../$(GODOT_DIR)/gamedata/$$(dirname $$f); cp $$f ../$(GODOT_DIR)/gamedata/$$f; done

check-sync: ## fail if godot/gamedata is stale
	@mkdir -p gamedata $(GODOT_DIR)/gamedata; tmp=$$(mktemp -d); cd gamedata && find . -name '*.json' -o -name '*.txt' | sort > $$tmp/a; cd ../$(GODOT_DIR)/gamedata && find . -name '*.json' -o -name '*.txt' | sort > $$tmp/b; cd ../..; \
	diff -q $$tmp/a $$tmp/b >/dev/null || { echo "godot/gamedata file list differs: run make sync"; exit 1; }; \
	while read f; do cmp -s gamedata/$$f $(GODOT_DIR)/gamedata/$$f || { echo "stale: $$f (run make sync)"; exit 1; }; done < $$tmp/a; echo "gamedata in sync"

server: ## run the server in test mode (add ARGS="-sim-lag=120ms -sim-jitter=40ms")
	go run ./cmd/server -test $(ARGS)

balance: ## balance sim → docs/BALANCE_REPORT.md
	go run ./cmd/balance -races $(RACES)

assets: ## Blender headless → godot/assets/*.glb + turntables
	./art/export.sh

e2e: ## real server binary + headless Godot bot clients
	./scripts/e2e.sh

screenshot: import ## run the game windowed and save $(SHOT)
	@mkdir -p $(dir $(SHOT))
	$(GODOT) --path $(GODOT_DIR) --resolution 1280x720 --position 0,0 -- --shot $(abspath $(SHOT))

ios-export: ## Godot headless iOS export → build/ios/UltiRace.xcodeproj
	./scripts/ios.sh export

ios-device: ## signed build for the connected iPhone
	./scripts/ios.sh device

ios-run: ## build, install and launch on the connected iPhone
	./scripts/ios.sh run

ios-check: ## unsigned generic-iOS compile (CI)
	./scripts/ios.sh compile-check

ios: ## export + xcodebuild archive
	./scripts/ios.sh archive

doctor: ## toolchain versions PASS/FAIL
	./scripts/doctor.sh

preflight: ## toolchain smoke tests
	./scripts/preflight.sh

clean:
	rm -rf build
