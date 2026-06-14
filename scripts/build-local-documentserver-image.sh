#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-onlyoffice/documentserver-local}"
IMAGE_TAG="${IMAGE_TAG:-9.4.0-local.1}"
BASE_IMAGE="${BASE_IMAGE:-onlyoffice/documentserver:9.4.0}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

LOCAL_VERSION="${LOCAL_VERSION:-${IMAGE_TAG}}"
PRODUCT_VERSION="${PRODUCT_VERSION:-${LOCAL_VERSION%%-local.*}}"
if [[ "${PRODUCT_VERSION}" == "${LOCAL_VERSION}" ]]; then
  PRODUCT_VERSION="${PRODUCT_VERSION:-9.4.0}"
fi
BUILD_NUMBER="${BUILD_NUMBER:-${LOCAL_VERSION#${PRODUCT_VERSION}-}}"
if [[ "${BUILD_NUMBER}" == "${LOCAL_VERSION}" ]]; then
  BUILD_NUMBER="${BUILD_NUMBER:-local.1}"
fi
SOURCE_BUILD_NUMBER="${SOURCE_BUILD_NUMBER:-1}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc 2>/dev/null || echo 1)}"

SOURCE_HASH_POSTFIX="${SOURCE_HASH_POSTFIX:-local-source-build}"
BUILD_OUTPUT="${BUILD_OUTPUT:-push}"

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

docker buildx version >/dev/null

echo "Inspecting base image platforms: ${BASE_IMAGE}" >&2
base_inspect="$(docker buildx imagetools inspect "${BASE_IMAGE}")"
for platform in ${PLATFORMS//,/ }; do
  if ! grep -q "Platform:[[:space:]]*${platform}" <<<"${base_inspect}" && ! grep -q "${platform}" <<<"${base_inspect}"; then
    echo "Base image ${BASE_IMAGE} does not advertise ${platform}" >&2
    exit 1
  fi
done

repo_json_line() {
  local name="$1" path="$2" default_url="$3" source="$4"
  local url ref commit dirty
  url="$(git -C "${path}" config --get remote.origin.url 2>/dev/null || true)"
  if [[ -z "${url}" ]]; then
    url="${default_url}"
  fi
  ref="$(git -C "${path}" describe --tags --exact-match 2>/dev/null || git -C "${path}" symbolic-ref --short -q HEAD 2>/dev/null || git -C "${path}" rev-parse --short HEAD)"
  commit="$(git -C "${path}" rev-parse HEAD)"
  if [[ -n "$(git -C "${path}" status --porcelain)" ]]; then
    dirty=true
  else
    dirty=false
  fi
  jq -nc \
    --arg name "${name}" \
    --arg url "${url}" \
    --arg ref "${ref}" \
    --arg commit "${commit}" \
    --arg source "${source}" \
    --argjson dirty "${dirty}" \
    '{name:$name,url:$url,ref:$ref,commit:$commit,source:$source,dirty:$dirty}'
}

source_repositories_json="$(
  {
    repo_json_line "DocumentServer" "." "https://github.com/ONLYOFFICE/DocumentServer.git" "local-context"
    repo_json_line "server" "server" "https://github.com/ONLYOFFICE/server.git" "local-context"
    repo_json_line "web-apps" "web-apps" "https://github.com/ONLYOFFICE/web-apps.git" "local-context"
    repo_json_line "core" "core" "https://github.com/ONLYOFFICE/core.git" "reused-from-base-image"
    repo_json_line "core-fonts" "core-fonts" "https://github.com/ONLYOFFICE/core-fonts.git" "reused-from-base-image"
    repo_json_line "dictionaries" "dictionaries" "https://github.com/ONLYOFFICE/dictionaries.git" "reused-from-base-image"
    repo_json_line "sdkjs" "sdkjs" "https://github.com/ONLYOFFICE/sdkjs.git" "reused-from-base-image"
  } | jq -s -c .
)"

output_args=()
case "${BUILD_OUTPUT}" in
  push)
    output_args=(--push)
    ;;
  load)
    if [[ "${PLATFORMS}" == *,* ]]; then
      echo "BUILD_OUTPUT=load only supports a single platform; set PLATFORMS=linux/amd64 or use BUILD_OUTPUT=push" >&2
      exit 1
    fi
    output_args=(--load)
    ;;
  none)
    output_args=()
    ;;
  *)
    output_args=(--output "${BUILD_OUTPUT}")
    ;;
esac

echo "Building ${IMAGE_NAME}:${IMAGE_TAG} for ${PLATFORMS}" >&2
docker buildx build \
  --platform "${PLATFORMS}" \
  --build-arg BASE_IMAGE="${BASE_IMAGE}" \
  --build-arg LOCAL_VERSION="${LOCAL_VERSION}" \
  --build-arg PRODUCT_VERSION="${PRODUCT_VERSION}" \
  --build-arg BUILD_NUMBER="${BUILD_NUMBER}" \
  --build-arg SOURCE_BUILD_NUMBER="${SOURCE_BUILD_NUMBER}" \
  --build-arg BUILD_JOBS="${BUILD_JOBS}" \
  --build-arg SOURCE_HASH_POSTFIX="${SOURCE_HASH_POSTFIX}" \
  --build-arg SOURCE_REPOSITORIES_JSON="${source_repositories_json}" \
  -f docker/local-documentserver/Dockerfile \
  -t "${IMAGE_NAME}:${IMAGE_TAG}" \
  "${output_args[@]}" \
  "$@" \
  .
