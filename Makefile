.PHONY: up up-logging up-full up-saas down restart logs status deploy-k8s test lint clean demo validate-alerts build-exporters validate

up:
	docker compose up -d

up-logging:
	docker compose --profile logging up -d

up-full:
	docker compose --profile full up -d

up-saas:
	docker compose --profile logging --profile saas up -d

down:
	docker compose down

restart:
	docker compose down
	docker compose up -d

logs:
	docker compose logs -f

status:
	docker compose ps

deploy-k8s:
	kubectl apply -k k8s/

test:
	pytest

lint:
	ruff check

clean:
	docker compose down -v --remove-orphans
	rm -rf *_data/

demo:
	bash scripts/demo.sh

validate-alerts:
	promtool check rules configs/prometheus/alert_rules.yml

build-exporters:
	docker build -t panoptes-custom-exporter ./exporters/custom-exporter
	docker build -t panoptes-webhook-receiver ./remediation/webhook-receiver

validate:
	promtool check config configs/prometheus/prometheus.yml
	promtool check rules configs/prometheus/alert_rules.yml
	yamllint configs/
	docker compose config --quiet
