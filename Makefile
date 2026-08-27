SHELL := /bin/bash

.PHONY: setup zoom teams keepawake reset-camera test lint dist clean-dist

setup:
	chmod +x scripts/*.sh
	./scripts/check_prereqs.sh

zoom:
	./scripts/start_zoom.sh

teams:
	./scripts/start_teams.sh

keepawake:
	./scripts/keepawake.sh

reset-camera:
	./scripts/reset_camera_services.sh

test:
	./tests/run.sh

lint:
	@status=0; \
	echo "Checking shell script syntax (bash -n)..."; \
	while IFS= read -r -d '' f; do \
		if ! bash -n "$$f"; then \
			echo "syntax error in $$f" >&2; \
			status=1; \
		fi; \
	done < <(find . -name '*.sh' -not -path './.git/*' -not -path './dist/*' -print0); \
	if command -v osacompile >/dev/null 2>&1; then \
		echo "Validating AppleScript sources (osacompile)..."; \
		tmp_dir=$$(mktemp -d); \
		for f in scripts/*.scpt; do \
			[ -e "$$f" ] || continue; \
			name=$$(basename "$$f" .scpt); \
			if ! osacompile -o "$$tmp_dir/$$name.scpt" "$$f" >/dev/null 2>&1; then \
				echo "AppleScript compile failed for $$f" >&2; \
				status=1; \
			fi; \
		done; \
		rm -rf "$$tmp_dir"; \
	else \
		echo "osacompile not found -- skipping AppleScript validation (requires macOS with Xcode Command Line Tools; run 'make lint' there to validate .scpt changes)"; \
	fi; \
	exit $$status

dist:
	@if [ -z "$(VERSION)" ]; then \
		echo "usage: make dist VERSION=<x.y.z>" >&2; \
		exit 1; \
	fi
	./scripts/build_release.sh "$(VERSION)"

clean-dist:
	@repo_root="$(CURDIR)"; \
	if [ -z "$$repo_root" ] || [ "$$repo_root" = "/" ]; then \
		echo "refusing to run: repository root is unset or is '/'" >&2; \
		exit 1; \
	fi; \
	target="$$repo_root/dist"; \
	if [ "$$(basename "$$target")" != "dist" ]; then \
		echo "refusing to remove unexpected path: $$target" >&2; \
		exit 1; \
	fi; \
	if [ -d "$$target" ]; then \
		rm -rf -- "$$target"; \
		echo "removed $$target"; \
	else \
		echo "nothing to clean ($$target does not exist)"; \
	fi
