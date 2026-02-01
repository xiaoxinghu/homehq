.PHONY: setup update

# One-off setup for new machine
setup:
	docker compose up -d

# Update services: stop, pull latest, restart
update:
	docker compose down
	git pull
	docker compose pull
	docker compose up -d
