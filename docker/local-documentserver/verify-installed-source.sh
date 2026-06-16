#!/bin/sh
set -eu

build_info_dir="/usr/share/onlyoffice/documentserver-local-build"
doc_root="/var/www/onlyoffice/documentserver"
expected_version="$(cat "${build_info_dir}/local-version")"
actual_version="$(dpkg-query -W -f='${Version}' onlyoffice-documentserver)"
manifest="${build_info_dir}/source-manifest.json"
checksums="${build_info_dir}/source-checksums.sha256"
official_package_record="${build_info_dir}/official-package-before-purge.txt"
official_file_list="${build_info_dir}/official-package-file-list-before-purge.txt"
product_version="$(python3 -c 'import json; print(json.load(open("'"${manifest}"'"))["product_version"])')"
source_build_number="$(python3 -c 'import json; print(json.load(open("'"${manifest}"'"))["source_build_number"])')"
about_version="${product_version}.${source_build_number}"

if [ "${actual_version}" != "${expected_version}" ]; then
  echo "unexpected onlyoffice-documentserver version: ${actual_version}, expected ${expected_version}" >&2
  exit 1
fi

owned_path="${doc_root}/server/DocService/docservice"
if ! dpkg-query -S "${owned_path}" | grep -q '^onlyoffice-documentserver:'; then
  echo "package ownership check failed for ${owned_path}" >&2
  exit 1
fi

require_file() {
  if [ ! -f "$1" ]; then
    echo "required file is missing: $1" >&2
    exit 1
  fi
}

require_owned_path() {
  if ! dpkg-query -S "$1" | grep -q '^onlyoffice-documentserver:'; then
    echo "package ownership check failed for $1" >&2
    exit 1
  fi
}

require_checksum_path() {
  rel="$1"
  if ! awk -v path="${rel}" '{
    line = $0
    sub(/^[^ ]+  /, "", line)
    if (line == path) found = 1
  } END { exit found ? 0 : 1 }' "${checksums}"; then
    echo "checksum manifest is missing path: ${rel}" >&2
    exit 1
  fi
}

require_any_checksum_path() {
  for rel in "$@"; do
    if awk -v path="${rel}" '{
      line = $0
      sub(/^[^ ]+  /, "", line)
      if (line == path) found = 1
    } END { exit found ? 0 : 1 }' "${checksums}"; then
      return 0
    fi
  done
  echo "checksum manifest is missing all expected API paths: $*" >&2
  exit 1
}

require_manifest_text() {
  if ! grep -F -q "$1" "${manifest}"; then
    echo "source manifest is missing expected text: $1" >&2
    exit 1
  fi
}

require_installed_api_text() {
  text="$1"
  if [ -f "${doc_root}/web-apps/apps/api/documents/api.js" ] && \
     grep -F -q "${text}" "${doc_root}/web-apps/apps/api/documents/api.js"; then
    return 0
  fi
  if [ -f "${doc_root}/web-apps/apps/api/documents/api.js.tpl" ] && \
     grep -F -q "${text}" "${doc_root}/web-apps/apps/api/documents/api.js.tpl"; then
    return 0
  fi

  echo "installed API is missing expected text: ${text}" >&2
  exit 1
}

require_installed_docservice_text() {
  text="$1"
  if grep -a -F -q "${text}" "${doc_root}/server/DocService/docservice"; then
    return 0
  fi

  echo "installed docservice is missing expected text: ${text}" >&2
  exit 1
}

require_about_text() {
  text="$1"
  file="${doc_root}/web-apps/apps/common/main/lib/view/About.js"
  if [ -f "${file}" ] && grep -F -q "${text}" "${file}"; then
    return 0
  fi

  echo "installed About.js is missing expected text: ${text}" >&2
  exit 1
}

require_config_text() {
  file="$1"
  text="$2"
  if grep -F -q "${text}" "${file}"; then
    return 0
  fi

  echo "config ${file} is missing expected text: ${text}" >&2
  exit 1
}

require_file "${manifest}"
require_file "${checksums}"
require_file "${official_package_record}"
require_file "${official_file_list}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

absolute_checksums="${tmp_dir}/source-checksums.absolute.sha256"
awk -v prefix="${doc_root}/" '{
  expected = $1
  sub(/^[^ ]+  /, "")
  print expected "  " prefix $0
}' "${checksums}" > "${absolute_checksums}"
if ! sha256sum -c "${absolute_checksums}" >"${tmp_dir}/source-checksums.verify" 2>&1; then
  cat "${tmp_dir}/source-checksums.verify" >&2
  exit 1
fi

require_checksum_path "server/DocService/docservice"
require_checksum_path "server/FileConverter/converter"
require_checksum_path "server/Metrics/metrics"
require_checksum_path "server/FileConverter/bin/x2t"
require_checksum_path "sdkjs/common/device_scale.js"
require_checksum_path "sdkjs/word/sdk-all-min.js"
require_checksum_path "sdkjs/cell/sdk-all-min.js"
require_checksum_path "sdkjs/slide/sdk-all-min.js"
require_any_checksum_path \
  "web-apps/apps/api/documents/api.js" \
  "web-apps/apps/api/documents/api.js.tpl"

require_owned_path "${doc_root}/server/FileConverter/converter"
require_owned_path "${doc_root}/server/Metrics/metrics"
require_owned_path "${doc_root}/server/FileConverter/bin/x2t"
require_owned_path "${doc_root}/sdkjs/common/device_scale.js"
require_owned_path "${doc_root}/sdkjs/word/sdk-all-min.js"
require_owned_path "${doc_root}/sdkjs/cell/sdk-all-min.js"
require_owned_path "${doc_root}/sdkjs/slide/sdk-all-min.js"

if ! grep -q '^onlyoffice-documentserver[[:space:]]' "${official_package_record}"; then
  echo "official package record does not include onlyoffice-documentserver" >&2
  exit 1
fi
official_version="$(awk '$1 == "onlyoffice-documentserver" { print $2; exit }' "${official_package_record}")"
if [ "${official_version}" = "${expected_version}" ]; then
  echo "official package record unexpectedly matches the local version" >&2
  exit 1
fi
if ! grep -F -q '/var/www/onlyoffice/documentserver/server/FileConverter/bin/x2t' "${official_file_list}"; then
  echo "official package file list does not include expected base binaries" >&2
  exit 1
fi

require_manifest_text '"rebuilt_paths"'
require_manifest_text '"server"'
require_manifest_text '"web-apps"'
require_manifest_text '"reused_from_base_verified"'
require_manifest_text '"server/FileConverter/bin/x2t"'
require_manifest_text '"sdkjs/common/device_scale.js"'
require_manifest_text '"sdkjs/word/sdk-all-min.js"'

require_installed_api_text "function shouldUseNativePdfPreview(config)"
require_installed_api_text "config.document && config.document.isForm !== true"
require_installed_api_text "function getPreviewTraceElapsedMs(config)"
require_installed_api_text "previewElapsedMs: getPreviewTraceElapsedMs(config)"
require_installed_api_text "iframe.setAttribute(\"data-onlyoffice-native-pdf-preview\", \"true\");"
require_installed_api_text "function registerNativePdfCache(config, iframe, sourceUrl)"
require_installed_api_text "downloadfile-cache/register/"
require_installed_api_text "native-pdf-cache-hit-url"
require_installed_api_text "native-pdf-cache-fallback"
require_installed_api_text "return '${product_version}';"
require_about_text "this.txtVersionNum = '${about_version}';"

if grep -F -q "return '${expected_version}';" "${doc_root}/web-apps/apps/api/documents/api.js" 2>/dev/null || \
   grep -F -q "return '${expected_version}';" "${doc_root}/web-apps/apps/api/documents/api.js.tpl" 2>/dev/null; then
  echo "installed API version unexpectedly uses local package version: ${expected_version}" >&2
  exit 1
fi

if grep -F -q "this.txtVersionNum = '${expected_version}" "${doc_root}/web-apps/apps/common/main/lib/view/About.js"; then
  echo "installed About version unexpectedly uses local package version: ${expected_version}" >&2
  exit 1
fi

require_installed_docservice_text "/downloadfile-cache/register/:cacheDocId"
require_installed_docservice_text "/downloadfile-cache/:cacheKey.pdf"
require_installed_docservice_text "services.CoAuthoring.server.nativePdfCache"

require_config_text /etc/onlyoffice/documentserver/default.json '"nativePdfCache"'
require_config_text /etc/onlyoffice/documentserver/default.json '"cacheControl": "private, max-age=7200"'
require_config_text /etc/onlyoffice/documentserver/production-linux.json '"nativePdfCache"'
require_config_text /etc/onlyoffice/documentserver/production-linux.json '/var/lib/onlyoffice/documentserver/App_Data/pdf-native-cache'
require_config_text /etc/onlyoffice/documentserver/local.json '"nativePdfCache"'
require_config_text /etc/onlyoffice/documentserver/local.json '/var/lib/onlyoffice/documentserver/App_Data/pdf-native-cache'

if ! grep -q '"rebuilt_paths"' "${manifest}" || \
   ! grep -q '"server"' "${manifest}" || \
   ! grep -q '"web-apps"' "${manifest}"; then
  echo "source manifest does not declare the expected rebuilt paths" >&2
  exit 1
fi

if [ ! -f /etc/onlyoffice/documentserver/local.json ] || \
   [ ! -e /etc/nginx/conf.d/ds.conf ] || \
   [ ! -f /etc/onlyoffice/documentserver/nginx/ds.conf ]; then
  echo "required official runtime configuration was not restored" >&2
  exit 1
fi

if [ -e /etc/supervisor/conf.d/ds-example.conf ] || \
   [ -e /etc/nginx/includes/ds-example.conf ] || \
   [ -e /var/www/onlyoffice/documentserver-example ] || \
   [ -e /etc/onlyoffice/documentserver-example ]; then
  echo "documentserver example app is still installed or enabled" >&2
  exit 1
fi

echo "verify-installed-source: OK"
