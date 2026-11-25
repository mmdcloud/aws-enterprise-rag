.PHONY: test lint fmt clean local-up local-down tf-init tf-validate

test:
	python3 -m unittest discover -s tests -v

lint:
	python3 -m ruff check src tests 2>/dev/null || true

fmt:
	python3 -m black --check src tests 2>/dev/null || true

local-up:
	docker-compose up -d

local-down:
	docker-compose down -v

tf-init:
	cd terraform && terraform init -backend=false

tf-validate:
	cd terraform && terraform validate

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	rm -rf .pytest_cache .coverage htmlcov
