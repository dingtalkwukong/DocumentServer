# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=onlyoffice/documentserver:9.4.0

FROM --platform=$TARGETPLATFORM ${BASE_IMAGE} AS official-package

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN <<'EOF'
set -eu
mkdir -p /official-package-meta
mapfile -t official_packages < <(dpkg-query -W -f='${binary:Package}\n' 'onlyoffice-documentserver*' 2>/dev/null | sort -u)
if [ "${#official_packages[@]}" -eq 0 ]; then
  echo "No official onlyoffice-documentserver package found in base image" >&2
  exit 1
fi
printf '%s\n' "${official_packages[@]}" > /official-package-meta/package-names
printf '%s\n' "${official_packages[0]}" > /official-package-meta/package-name
dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\t${Depends}\n' "${official_packages[@]}" > /official-package-meta/package-info
dpkg-query -W -f='${Version}\n' "${official_packages[0]}" > /official-package-meta/package-version
dpkg-query -W -f='${Architecture}\n' "${official_packages[0]}" > /official-package-meta/package-architecture
dpkg-query -W -f='${Depends}\n' "${official_packages[0]}" > /official-package-meta/package-depends
EOF

FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS build-base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    GIT_TERMINAL_PROMPT=0 \
    npm_config_fund=false \
    npm_config_audit=false

RUN <<'EOF'
set -eux
ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime
echo "${TZ}" > /etc/timezone
apt-get update
apt-get install -y --no-install-recommends \
  bash \
  build-essential \
  ca-certificates \
  curl \
  dpkg-dev \
  fakeroot \
  file \
  git \
  jq \
  make \
  nodejs \
  npm \
  python-is-python3 \
  python3 \
  rsync \
  sed \
  tar \
  xz-utils
npm install -g grunt-cli @yao-pkg/pkg@6.11.0
rm -rf /var/lib/apt/lists/*
EOF

FROM build-base AS web-apps-build

ARG LOCAL_VERSION=9.4.0-local.1
ARG PRODUCT_VERSION=9.4.0
ARG SOURCE_HASH_POSTFIX=local-source-build

WORKDIR /workspace/source
COPY sdkjs /workspace/source/sdkjs
COPY web-apps /workspace/source/web-apps

RUN <<'EOF'
set -eux
export NODE_ENV=production
export PRODUCT_VERSION="${PRODUCT_VERSION}"
export BUILD_NUMBER="${LOCAL_VERSION}"
export PUBLISHER_NAME="Ascensio System SIA"
export PUBLISHER_URL="https://www.onlyoffice.com/"

cd /workspace/source/web-apps/translation
python3 ./merge_and_check.py

cd /workspace/source/web-apps/build
npm install
grunt --force --verbose

api="/workspace/source/web-apps/deploy/web-apps/apps/api/documents/api.js"
if [ -f "${api}" ]; then
  mv "${api}" "${api}.tpl"
  sed -i \
    -e "s|\\(_dc=\\)0|\\1${LOCAL_VERSION}|g" \
    -e "s|{{PRODUCT_VERSION}}|${PRODUCT_VERSION}|g" \
    "${api}.tpl"
fi

mkdir -p /workspace/web-apps-output
cp -a /workspace/source/web-apps/deploy/web-apps /workspace/web-apps-output/web-apps
cp -a /workspace/source/web-apps/deploy/sdkjs /workspace/web-apps-output/sdkjs
EOF

FROM build-base AS server-build

ARG TARGETARCH
ARG PRODUCT_VERSION=9.4.0
ARG SOURCE_BUILD_NUMBER=1
ARG BUILD_JOBS=

WORKDIR /workspace/source
COPY server /workspace/source/server

RUN <<'EOF'
set -eux
case "${TARGETARCH}" in
  amd64) pkg_target="node20-linux" ;;
  arm64) pkg_target="node20-linux-arm64" ;;
  *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac

build_jobs="${BUILD_JOBS:-$(nproc)}"
export MAKEFLAGS="-j${build_jobs}"
export npm_config_jobs="${build_jobs}"
export NODE_ENV=production
export PRODUCT_VERSION="${PRODUCT_VERSION}"
export BUILD_NUMBER="${SOURCE_BUILD_NUMBER}"
export PUBLISHER_NAME="Ascensio System SIA"
export PUBLISHER_URL="https://www.onlyoffice.com/"

cd /workspace/source/server
npm ci
npm run build
sed -i \
  -e "s|\(const buildVersion = \).*|\1'${PRODUCT_VERSION}';|" \
  -e "s|\(const buildNumber = \).*|\1${SOURCE_BUILD_NUMBER};|" \
  /workspace/source/server/Common/sources/commondefines.js
PRODUCT_VERSION="${PRODUCT_VERSION}" SOURCE_BUILD_NUMBER="${SOURCE_BUILD_NUMBER}" node -e "\
const fs = require('fs');\
const text = fs.readFileSync('./Common/sources/commondefines.js', 'utf8');\
const version = (text.match(/const buildVersion = '([^']+)'/) || [])[1];\
const build = (text.match(/const buildNumber = ([^;]+);/) || [])[1];\
if (version !== process.env.PRODUCT_VERSION || String(build) !== process.env.SOURCE_BUILD_NUMBER) {\
  throw new Error('commondefines version mismatch: ' + version + '.' + build);\
}"

if [ "${TARGETARCH}" = "arm64" ] && [ -d /workspace/source/server/DocService/node_modules/sharp ]; then
  export npm_config_platform=linux
  export npm_config_arch=arm64
  export npm_config_libc=glibc
  cd /workspace/source/server/DocService/node_modules/sharp
  node install/libvips || true
  npm exec -- prebuild-install --platform linux --arch arm64 --libc glibc || true
  cd /workspace/source/server
fi

mkdir -p /workspace/server-output
pkg ./DocService -t "${pkg_target}" -o /workspace/server-output/docservice
pkg ./FileConverter -t "${pkg_target}" -o /workspace/server-output/converter
pkg ./Metrics -t "${pkg_target}" -o /workspace/server-output/metrics
chmod 0755 /workspace/server-output/docservice /workspace/server-output/converter /workspace/server-output/metrics
file /workspace/server-output/docservice /workspace/server-output/converter /workspace/server-output/metrics
EOF

FROM build-base AS source-package

ARG BASE_IMAGE
ARG BUILDPLATFORM
ARG TARGETARCH
ARG TARGETPLATFORM
ARG LOCAL_VERSION=9.4.0-local.1
ARG PRODUCT_VERSION=9.4.0
ARG BUILD_NUMBER=local.1
ARG SOURCE_BUILD_NUMBER=1
ARG SOURCE_HASH_POSTFIX=local-source-build
ARG SOURCE_REPOSITORIES_JSON=[]

COPY --from=official-package /official-package-meta/ /workspace/official-package-meta/
COPY --from=official-package /var/www/onlyoffice/documentserver /workspace/package-root/var/www/onlyoffice/documentserver
COPY --from=official-package /etc/onlyoffice/documentserver /workspace/package-root/etc/onlyoffice/documentserver
COPY --from=official-package /etc/logrotate.d/ds.conf /workspace/package-root/etc/logrotate.d/ds.conf
COPY --from=official-package /etc/nginx/conf.d/ds.conf /workspace/package-root/etc/nginx/conf.d/ds.conf
COPY --from=official-package /etc/nginx/includes /workspace/package-root/etc/nginx/includes
COPY --from=official-package /etc/sudoers.d/documentserver /workspace/package-root/etc/sudoers.d/documentserver
COPY --from=official-package /etc/supervisor/conf.d /workspace/package-root/etc/supervisor/conf.d
COPY --from=official-package /usr/bin/documentserver-*.sh /workspace/package-root/usr/bin/
COPY --from=official-package /usr/lib/systemd/system/ds-*.service /workspace/package-root/usr/lib/systemd/system/
COPY --from=official-package /usr/share/doc/onlyoffice-documentserver /workspace/package-root/usr/share/doc/onlyoffice-documentserver
COPY --from=web-apps-build /workspace/web-apps-output/web-apps /workspace/local-build/web-apps
COPY --from=web-apps-build /workspace/web-apps-output/sdkjs /workspace/local-build/sdkjs
COPY --from=server-build /workspace/server-output/ /workspace/local-build/server/
COPY server/Common/config/default.json /workspace/local-config/default.json
COPY server/Common/config/production-linux.json /workspace/local-config/production-linux.json

RUN <<'EOF'
set -eu
case "${TARGETARCH}" in
  amd64|arm64) deb_arch="${TARGETARCH}" ;;
  *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac

doc_root="/workspace/package-root/var/www/onlyoffice/documentserver"
rm -rf "${doc_root}/web-apps"
cp -a /workspace/local-build/web-apps "${doc_root}/web-apps"
mkdir -p "${doc_root}/sdkjs"
cp -a /workspace/local-build/sdkjs/. "${doc_root}/sdkjs/"
install -m 0755 /workspace/local-build/server/docservice "${doc_root}/server/DocService/docservice"
install -m 0755 /workspace/local-build/server/converter "${doc_root}/server/FileConverter/converter"
install -m 0755 /workspace/local-build/server/metrics "${doc_root}/server/Metrics/metrics"

native_pdf_cache="$(jq -c '.services.CoAuthoring.server.nativePdfCache' /workspace/local-config/default.json)"
native_pdf_cache_production="$(jq -c '.services.CoAuthoring.server.nativePdfCache' /workspace/local-config/production-linux.json)"
jq --argjson nativePdfCache "${native_pdf_cache}" \
  '.services.CoAuthoring.server.nativePdfCache = $nativePdfCache' \
  /workspace/package-root/etc/onlyoffice/documentserver/default.json \
  > /tmp/default.json
mv /tmp/default.json /workspace/package-root/etc/onlyoffice/documentserver/default.json
jq --argjson nativePdfCache "${native_pdf_cache}" \
   --argjson productionNativePdfCache "${native_pdf_cache_production}" \
  '.services.CoAuthoring.server.nativePdfCache = ($nativePdfCache * $productionNativePdfCache)' \
  /workspace/package-root/etc/onlyoffice/documentserver/production-linux.json \
  > /tmp/production-linux.json
mv /tmp/production-linux.json /workspace/package-root/etc/onlyoffice/documentserver/production-linux.json

rm -rf \
  /workspace/package-root/var/www/onlyoffice/documentserver-example \
  /workspace/package-root/etc/onlyoffice/documentserver-example \
  /workspace/package-root/etc/nginx/includes/ds-example.conf \
  /workspace/package-root/etc/supervisor/conf.d/ds-example.conf \
  /workspace/package-root/usr/lib/systemd/system/ds-example.service

if getent passwd ds >/dev/null 2>&1; then
  chown -R ds:ds /workspace/package-root/var/www/onlyoffice/documentserver
fi

mkdir -p /workspace/package-root/DEBIAN /workspace/build-artifacts
depends="$(cat /workspace/official-package-meta/package-depends)"
installed_size="$(du -sk /workspace/package-root | awk '{print $1}')"
cat > /workspace/package-root/DEBIAN/control <<CONTROL
Package: onlyoffice-documentserver
Version: ${LOCAL_VERSION}
Section: web
Priority: optional
Architecture: ${deb_arch}
Maintainer: Ascensio System SIA <support@onlyoffice.com>
Depends: ${depends}
Installed-Size: ${installed_size}
Description: Online editors for text docs, spreadsheets, presentations, PDFs, and PDF forms.
 Local package assembled from onlyoffice/documentserver base binaries with server and web-apps rebuilt from the current source tree.
CONTROL

cat > /workspace/package-root/DEBIAN/postinst <<'POSTINST'
#!/bin/sh
set -e
if ! getent group ds >/dev/null 2>&1; then
  addgroup --system ds >/dev/null
fi
if ! getent passwd ds >/dev/null 2>&1; then
  adduser --system --home /var/www/onlyoffice/documentserver --no-create-home --ingroup ds ds >/dev/null
fi
mkdir -p \
  /var/www/onlyoffice/documentserver/fonts \
  /var/log/onlyoffice/documentserver \
  /var/lib/onlyoffice/documentserver/App_Data \
  /var/lib/onlyoffice/documentserver/App_Data/pdf-native-cache
chown -R ds:ds /var/www/onlyoffice/documentserver /var/lib/onlyoffice/documentserver || true
exit 0
POSTINST
chmod 0755 /workspace/package-root/DEBIAN/postinst

{
  printf '%s\n' \
    "server/DocService/docservice" \
    "server/FileConverter/converter" \
    "server/Metrics/metrics"
  find "${doc_root}/web-apps" -type f | sed "s|^${doc_root}/||" | sort
  (cd /workspace/local-build && find sdkjs -type f | sort)
} > /tmp/rebuilt-checksum-paths

cat > /tmp/reused-checksum-paths <<'PATHS'
server/FileConverter/bin/x2t
sdkjs/word/sdk-all-min.js
sdkjs/cell/sdk-all-min.js
sdkjs/slide/sdk-all-min.js
sdkjs/visio/sdk-all.js
sdkjs/visio/sdk-all-min.js
PATHS

while IFS= read -r rel; do
  if [ ! -f "${doc_root}/${rel}" ]; then
    echo "Required reused base file is missing from package root: ${rel}" >&2
    exit 1
  fi
done < /tmp/reused-checksum-paths

(
  cd "${doc_root}"
  cat /tmp/rebuilt-checksum-paths /tmp/reused-checksum-paths | awk 'NF && !seen[$0]++' | while IFS= read -r rel; do
    sha256sum "${rel}"
  done
) > /workspace/build-artifacts/source-checksums.sha256

dpkg-deb --build --root-owner-group /workspace/package-root "/workspace/build-artifacts/onlyoffice-documentserver_${LOCAL_VERSION}_${deb_arch}.deb"
sha256sum "/workspace/build-artifacts/onlyoffice-documentserver_${LOCAL_VERSION}_${deb_arch}.deb" > /tmp/local-deb.sha256

printf '%s\n' "${SOURCE_REPOSITORIES_JSON}" | jq -c . > /tmp/source-repositories.json
jq -Rn '[inputs | capture("^(?<sha256>[0-9a-f]{64})  (?<path>.*)$") | {path, sha256}]' \
  < /workspace/build-artifacts/source-checksums.sha256 \
  > /tmp/source-checksums.json
jq -Rn '[inputs | select(length > 0)]' < /tmp/rebuilt-checksum-paths > /tmp/rebuilt-checksum-paths.json
jq -Rn '[inputs | select(length > 0)]' < /tmp/reused-checksum-paths > /tmp/reused-checksum-paths.json
deb_sha="$(cut -d' ' -f1 /tmp/local-deb.sha256)"
official_package="$(cat /workspace/official-package-meta/package-name)"
official_version="$(cat /workspace/official-package-meta/package-version)"
official_arch="$(cat /workspace/official-package-meta/package-architecture)"

jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg target_platform "${TARGETPLATFORM}" \
  --arg target_arch "${TARGETARCH}" \
  --arg build_platform "${BUILDPLATFORM}" \
  --arg product_version "${PRODUCT_VERSION}" \
  --arg build_number "${BUILD_NUMBER}" \
  --arg source_build_number "${SOURCE_BUILD_NUMBER}" \
  --arg local_version "${LOCAL_VERSION}" \
  --arg source_hash_postfix "${SOURCE_HASH_POSTFIX}" \
  --arg base_image "${BASE_IMAGE}" \
  --arg official_package "${official_package}" \
  --arg official_version "${official_version}" \
  --arg official_arch "${official_arch}" \
  --arg deb_file "onlyoffice-documentserver_${LOCAL_VERSION}_${deb_arch}.deb" \
  --arg deb_arch "${deb_arch}" \
  --arg deb_sha256 "${deb_sha}" \
  --slurpfile repositories /tmp/source-repositories.json \
  --slurpfile checksums /tmp/source-checksums.json \
  --slurpfile rebuilt_checksum_paths /tmp/rebuilt-checksum-paths.json \
  --slurpfile reused_checksum_paths /tmp/reused-checksum-paths.json \
  '{generated_at:$generated_at,target_platform:$target_platform,target_arch:$target_arch,build_platform:$build_platform,base_image:$base_image,product_version:$product_version,build_number:$build_number,source_build_number:$source_build_number,local_version:$local_version,source_hash_postfix:$source_hash_postfix,official_package:{name:$official_package,version:$official_version,architecture:$official_arch},deb:{file:$deb_file,architecture:$deb_arch,sha256:$deb_sha256},checksums:$checksums[0],repositories:$repositories[0],local_build:{rebuilt_paths:["server","web-apps","sdkjs"],rebuilt_checksum_paths:$rebuilt_checksum_paths[0],reused_from_base:["core","core-fonts","dictionaries","document-formats","document-templates","sdkjs-plugins","FileConverter/bin native binaries","server/tools"],reused_from_base_verified:$reused_checksum_paths[0],packaging:"dpkg-deb from official package root plus local server/web-apps/sdkjs outputs"}}' \
  > /workspace/build-artifacts/source-manifest.json
EOF

FROM scratch AS source-package-artifacts

COPY --from=source-package /workspace/build-artifacts/ /

FROM --platform=$TARGETPLATFORM ${BASE_IMAGE} AS runtime

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH
ARG LOCAL_VERSION=9.4.0-local.1

ENV LOCAL_DOCUMENTSERVER_VERSION=${LOCAL_VERSION} \
    DS_DOCKER_INSTALLATION=true \
    DS_PLUGIN_INSTALLATION=false

COPY --from=source-package /workspace/build-artifacts/ /tmp/local-documentserver-build/
COPY docker/local-documentserver/verify-installed-source.sh /usr/local/bin/verify-installed-source.sh

RUN <<'EOF'
set -eux
build_info_dir="/usr/share/onlyoffice/documentserver-local-build"
mkdir -p "${build_info_dir}"
cp /tmp/local-documentserver-build/source-manifest.json "${build_info_dir}/source-manifest.json"
cp /tmp/local-documentserver-build/source-checksums.sha256 "${build_info_dir}/source-checksums.sha256"
echo "${LOCAL_VERSION}" > "${build_info_dir}/local-version"

mapfile -t official_packages < <(dpkg-query -W -f='${binary:Package}\n' 'onlyoffice-documentserver*' 2>/dev/null | sort -u)
if [ "${#official_packages[@]}" -eq 0 ]; then
  echo "No official onlyoffice-documentserver package found in base image" >&2
  exit 1
fi

dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\t${Depends}\n' "${official_packages[@]}" \
  > "${build_info_dir}/official-package-before-purge.txt"
: > "${build_info_dir}/official-package-file-list-before-purge.txt"
for pkg in "${official_packages[@]}"; do
  { echo "## ${pkg}"; dpkg-query -L "${pkg}"; } >> "${build_info_dir}/official-package-file-list-before-purge.txt"
done

generated_config_backup_dir="$(mktemp -d)"
backup_generated_path() {
  local path="$1"
  if [ -e "${path}" ] || [ -L "${path}" ]; then
    mkdir -p "${generated_config_backup_dir}$(dirname "${path}")"
    cp -a "${path}" "${generated_config_backup_dir}${path}"
  fi
}
restore_generated_path() {
  local path="$1"
  if [ -e "${generated_config_backup_dir}${path}" ] || [ -L "${generated_config_backup_dir}${path}" ]; then
    mkdir -p "$(dirname "${path}")"
    rm -rf "${path}"
    cp -a "${generated_config_backup_dir}${path}" "${path}"
  fi
}
for path in \
  /etc/onlyoffice/documentserver/local.json \
  /etc/onlyoffice/documentserver/nginx/ds.conf \
  /etc/nginx/conf.d/ds.conf; do
  backup_generated_path "${path}"
done

maintainer_backup_dir="$(mktemp -d)"
for cmd in /usr/bin/systemctl /usr/sbin/service; do
  if [ -e "${cmd}" ] || [ -L "${cmd}" ]; then
    mkdir -p "${maintainer_backup_dir}$(dirname "${cmd}")"
    mv "${cmd}" "${maintainer_backup_dir}${cmd}"
    printf '#!/bin/sh\nexit 0\n' > "${cmd}"
    chmod 0755 "${cmd}"
  fi
done

apt-get purge -y "${official_packages[@]}"
rm -rf \
  /var/www/onlyoffice/documentserver \
  /var/www/onlyoffice/documentserver-example \
  /etc/onlyoffice/documentserver \
  /etc/onlyoffice/documentserver-example \
  /etc/supervisor/conf.d/ds-example.conf \
  /usr/lib/systemd/system/ds-example.service

apt-get install -y --no-install-recommends "/tmp/local-documentserver-build/onlyoffice-documentserver_${LOCAL_VERSION}_${TARGETARCH}.deb"

for path in \
  /etc/onlyoffice/documentserver/local.json \
  /etc/onlyoffice/documentserver/nginx/ds.conf \
  /etc/nginx/conf.d/ds.conf; do
  restore_generated_path "${path}"
done
rm -rf "${generated_config_backup_dir}"

for cmd in /usr/bin/systemctl /usr/sbin/service; do
  if [ -e "${maintainer_backup_dir}${cmd}" ] || [ -L "${maintainer_backup_dir}${cmd}" ]; then
    mv -f "${maintainer_backup_dir}${cmd}" "${cmd}"
  fi
done
rm -rf "${maintainer_backup_dir}"
rm -rf /var/lib/apt/lists/*
rm -rf \
  /var/www/onlyoffice/documentserver-example \
  /etc/onlyoffice/documentserver-example \
  /etc/nginx/includes/ds-example.conf \
  /etc/supervisor/conf.d/ds-example.conf \
  /usr/lib/systemd/system/ds-example.service

if [ -f /etc/supervisor/conf.d/ds.conf ]; then
  sed -i -e 's/,example//g' -e 's/example,//g' /etc/supervisor/conf.d/ds.conf
fi

chmod +x /usr/local/bin/verify-installed-source.sh
/usr/local/bin/verify-installed-source.sh
rm -rf /tmp/local-documentserver-build
EOF
