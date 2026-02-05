APP = cloudrun-firebase
TAG = $(shell echo "$$(date +%F)-$$(git rev-parse --short HEAD)")

help:
	@echo "Run make <target> where target is one of the following..."
	@echo
	@echo "  all                      - run requirements, lint, test, and build"
	@echo "  requirements             - install runtime dependencies"
	@echo "  development-requirements - install development dependencies"
	@echo "  pre-commit-install       - install pre-commit hooks"
	@echo "  pre-commit-update        - update pre-commit hooks"
	@echo "  pre-commit-run           - run pre-commit on all files"
	@echo "  pre-commit-clean         - remove pre-commit hooks"
	@echo "  lint                     - run flake8, pylint, black, and isort checks"
	@echo "  black                    - format code with black"
	@echo "  isort                    - sort imports with isort"
	@echo "  test                     - run unit tests"
	@echo "  build                    - build docker container"
	@echo "  clean                    - clean up workspace and containers"

all: requirements lint test build

requirements:
	pip install --quiet --upgrade --requirement requirements.txt

development-requirements: requirements
	pip install --quiet --upgrade --requirement development-requirements.txt

pre-commit-install: development-requirements
	pre-commit install
	detect-secrets scan > .secrets.baseline

pre-commit-update: development-requirements
	pre-commit autoupdate
	$(MAKE) pre-commit-run

pre-commit-run: development-requirements
	pre-commit run --all-files

x_pre-commit-clean:
	pre-commit uninstall

lint:
	flake8 --ignore=E501,E231 *.py
	pylint --errors-only --disable=C0301,E1101 *.py
	black --diff *.py
	isort --check-only --diff *.py

fmt: black isort

black:
	black *.py

isort:
	isort *.py

test:
	pytest --verbose

run-all-crud-steps:
	./utils/run-all-crud-steps.sh

local:
	open http://localhost:8080
	python -u -m uvicorn main:app --host "0.0.0.0" --port "8080" --reload

local-docker:
	docker run --rm -p 8080:8080 -v ~/.config/gcloud/application_default_credentials.json:/gcp/creds.json:ro -e GOOGLE_APPLICATION_CREDENTIALS=/gcp/creds.json $(APP):$(TAG)

build: lint
	docker build --tag $(APP):$(TAG) .

clean:
	docker container stop $(APP) || true
	docker container rm $(APP) || true
	@/bin/rm -rvf ./__pycache__ ./tests/__pycache__ .ruff_cache
	@/bin/rm -vf .*~ *.pyc
	@/bin/rm -vf firebase-debug.log firestore-debug.log

deploy:
	gcloud run deploy $(SERVICE_NAME) \
		--source . \
		--project $(PROJECT_ID) \
		--region $(REGION) \
		--allow-unauthenticated

.PHONY: help requirements lint black isort test build clean development-requirements pre-commit-install pre-commit-run pre-commit-clean
