.PHONY: test fmt validate local-up local-down

test:
	python -m pytest -q tests
fmt:
	terraform fmt -recursive terraform
validate:
	python -m compileall -q frontend worker shared scripts tests
	python -m pytest -q tests
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform validate
local-up:
	docker compose -f local/docker-compose.yml up --build -d
local-down:
	docker compose -f local/docker-compose.yml down
