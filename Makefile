
## Makefile
```make
SHELL := /bin/bash

.PHONY: setup zoom teams keepawake reset-camera

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
