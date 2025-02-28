#!make
PORT = 80
SERVICE_NAME = bridge_tweet_bot
DOCKER_COMPOSE_TAG = $(SERVICE_NAME)_1
PYFILES=*.py src/*.py tests/*/*.py

KUSTOMIZE_VERSION := $(shell test -e /usr/local/bin/kustomize && /usr/local/bin/kustomize version | cut -f2 -d/ | cut -f1 -d' ')
KUBEVAL_VERSION := $(shell test -e /usr/local/bin/kubeval && /usr/local/bin/kubeval --version | grep Version | cut -f2 -d' ')

# Pipeline commands
setup:
	python -m pip install --upgrade pip
	pip install pipenv
	pip install -r requirements.txt
	pip install -r requirements_dev.txt

unit:
	nose2 --output-buffer --pretty-assert --log-capture --verbose --with-coverage --coverage src --coverage-report term --coverage-report html --start-dir tests/unit

integration: down up
	docker-compose -f ./docker-compose.yml run integration_tests python -m unittest discover tests/integration/

lint: 
	pipenv run pydocstyle --add-ignore=D101,D102,D103,D104,D105,D107 .
	pipenv run pycodestyle --ignore=E501 .
	pipenv run pylint $(PYFILES)

format:
	pipenv run black ${PYFILES}
	pipenv run isort ${PYFILES}

check:
	pipenv run black --check ${PYFILES}
	pipenv run isort --check ${PYFILES}
	
scan:
	pipenv run bandit -r . -lll  # Show 3 lines of context
	pipenv run safety check

commitready: format unit integration
	@echo 'Commit ready'

shell:
	pipenv shell

# Docker commands
up:
	docker-compose -f ./docker-compose.yml build
	docker-compose -f ./docker-compose.yml up -d --force-recreate

up-integration:
	docker-compose -f ./docker-compose.yml up --build -d

down:
	docker-compose -f ./docker-compose.yml down --remove-orphans

down-rm:
	docker-compose -f ./docker-compose.yml down --remove-orphans --rmi all

downup: down up

rebuild:
	docker-compose up --build --force-recreate --no-deps $(SERVICE_NAME)

run: rebuild
	docker run  -p $(PORT):$(PORT) --name $(DOCKER_COMPOSE_TAG) -it $(DOCKER_COMPOSE_TAG) /bin/sh

exec-shell:
	docker exec -it $(DOCKER_COMPOSE_TAG) /bin/bash

docker-build:
	docker build -t $(SERVICE_NAME) .

docker-run: docker-build
	docker run  -p $(PORT):$(PORT) --name $(SERVICE_NAME) -it $(SERVICE_NAME)

docker-exec-shell:
	docker exec -it $(SERVICE_NAME) /bin/bash

# Manifest Validators
validate_manifest:
	rm -f .manifest
	kustomize build .deploy/$(TARGET_ENVIRONMENT) >> .manifest
	[ -s .manifest ] || (echo "Manifest is Empty" ; exit 2)
	kubeval .manifest --kubernetes-version 1.18.0 --ignore-missing-schemas
	echo "Manifest Validated"
	rm -rf .manifest

validate_manifest_if_changed:
	if test -n "$(shell git ls-files -m .deploy/)"; \
		then make validate_manifest; \
		else echo deploy/ files unchanged; \
	fi

install_validate_manifest:
ifneq ($(KUSTOMIZE_VERSION), v3.8.1)
	curl -o kustomize.tar.gz --location https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v3.8.1/kustomize_v3.8.1_linux_amd64.tar.gz
	tar -xzvf kustomize.tar.gz kustomize
	chmod u+x kustomize
	sudo mv kustomize /usr/local/bin/
	rm kustomize.tar.gz
endif
ifneq ($(KUBEVAL_VERSION), 0.15.0)
	wget -O kubeval-linux-amd64.tar.gz https://github.com/instrumenta/kubeval/releases/latest/download/kubeval-linux-amd64.tar.gz
	tar xf kubeval-linux-amd64.tar.gz kubeval
	chmod u+x kubeval
	sudo mv kubeval /usr/local/bin/
	rm kubeval-linux-amd64.tar.gz
endif