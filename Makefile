SHELL := /bin/bash

.PHONY: setup zoom teams keepawake reset-camera test

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
	./scripts/test_makefile.sh
	./scripts/test_check_prereqs.sh
	./scripts/test_launcher_failures.sh
	./scripts/test_ui_label_configuration.sh
