SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

ifndef IMAGE_TAG
IMAGE_TAG := 9.4.0-local.$(shell date +%Y%m%d%H%M%S)
endif

BASE_IMAGE ?= onlyoffice/documentserver:9.4.0
BUILDKIT_PROGRESS ?= plain
LOCAL_VERSION ?= $(IMAGE_TAG)

REGISTRY ?= localhost:5000
REGISTRY_CONTAINER ?= ds-local-registry
IMAGE_REPO ?= onlyoffice/documentserver-local
IMAGE_NAME ?= $(REGISTRY)/$(IMAGE_REPO)
LOCAL_IMAGE_NAME ?= onlyoffice/documentserver-local

.DEFAULT_GOAL := ds-image

.PHONY: ds-image ds-image-amd64 ds-image-arm64 ds-verify ds-inspect ds-registry

ds-image: ds-registry
	@echo "Building multi-arch image $(IMAGE_NAME):$(IMAGE_TAG)"
	BUILDKIT_PROGRESS="$(BUILDKIT_PROGRESS)" \
	BUILD_OUTPUT=push \
	PLATFORMS=linux/amd64,linux/arm64 \
	IMAGE_NAME="$(IMAGE_NAME)" \
	IMAGE_TAG="$(IMAGE_TAG)" \
	LOCAL_VERSION="$(LOCAL_VERSION)" \
	BASE_IMAGE="$(BASE_IMAGE)" \
	./scripts/build-local-documentserver-image.sh

ds-image-amd64:
	@echo "Building amd64 image $(LOCAL_IMAGE_NAME):$(IMAGE_TAG)"
	BUILDKIT_PROGRESS="$(BUILDKIT_PROGRESS)" \
	BUILD_OUTPUT=load \
	PLATFORMS=linux/amd64 \
	IMAGE_NAME="$(LOCAL_IMAGE_NAME)" \
	IMAGE_TAG="$(IMAGE_TAG)" \
	LOCAL_VERSION="$(LOCAL_VERSION)" \
	BASE_IMAGE="$(BASE_IMAGE)" \
	./scripts/build-local-documentserver-image.sh

ds-image-arm64:
	@echo "Building arm64 image $(LOCAL_IMAGE_NAME):$(IMAGE_TAG)-arm64"
	BUILDKIT_PROGRESS="$(BUILDKIT_PROGRESS)" \
	BUILD_OUTPUT=load \
	PLATFORMS=linux/arm64 \
	IMAGE_NAME="$(LOCAL_IMAGE_NAME)" \
	IMAGE_TAG="$(IMAGE_TAG)-arm64" \
	LOCAL_VERSION="$(LOCAL_VERSION)" \
	BASE_IMAGE="$(BASE_IMAGE)" \
	./scripts/build-local-documentserver-image.sh

ds-verify:
	docker buildx imagetools inspect "$(IMAGE_NAME):$(IMAGE_TAG)"
	docker run --rm --platform linux/amd64 --entrypoint /usr/local/bin/verify-installed-source.sh "$(IMAGE_NAME):$(IMAGE_TAG)"
	docker run --rm --platform linux/arm64 --entrypoint /usr/local/bin/verify-installed-source.sh "$(IMAGE_NAME):$(IMAGE_TAG)"

ds-inspect:
	docker buildx imagetools inspect "$(IMAGE_NAME):$(IMAGE_TAG)"

ds-registry:
	@if [[ "$(IMAGE_NAME)" == "$(REGISTRY)"/* || "$(IMAGE_NAME)" == localhost:* || "$(IMAGE_NAME)" == 127.0.0.1:* ]]; then \
	  if ! docker ps --format '{{.Names}}' | grep -qx "$(REGISTRY_CONTAINER)"; then \
	    docker rm -f "$(REGISTRY_CONTAINER)" >/dev/null 2>&1 || true; \
	    docker run -d --restart=always -p 127.0.0.1:5000:5000 --name "$(REGISTRY_CONTAINER)" registry:2 >/dev/null; \
	  fi; \
	fi
