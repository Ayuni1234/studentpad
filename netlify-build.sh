#!/usr/bin/env bash
set -euo pipefail

# Netlify's standard build image does not include Flutter. Resolve the current
# stable Linux SDK from Flutter's official release manifest and cache it between
# deploys so Git-based continuous deployment works on a clean build worker.
cache_root="${NETLIFY_CACHE_DIR:-${HOME}/.cache}/studentpad"
manifest="${cache_root}/releases_linux.json"
mkdir -p "$cache_root"
curl --fail --silent --show-error --location \
  "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" \
  --output "$manifest"

release="$(node -e '
  const fs = require("node:fs");
  const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const stable = data.releases.find((item) => item.channel === "stable");
  if (!stable) throw new Error("Flutter stable release was not found");
  process.stdout.write(JSON.stringify(stable));
' "$manifest")"
flutter_version="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).version)' "$release")"
flutter_archive="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).archive)' "$release")"
flutter_sha256="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).sha256)' "$release")"
sdk_dir="${cache_root}/flutter-${flutter_version}"

if [[ ! -x "${sdk_dir}/bin/flutter" ]]; then
  temp_dir="$(mktemp -d "${cache_root}/flutter-install.XXXXXX")"
  trap 'rm -rf "$temp_dir"' EXIT
  archive_path="${temp_dir}/flutter.tar.xz"
  curl --fail --silent --show-error --location \
    "https://storage.googleapis.com/flutter_infra_release/releases/${flutter_archive}" \
    --output "$archive_path"
  echo "${flutter_sha256}  ${archive_path}" | sha256sum --check --status
  tar -xJf "$archive_path" -C "$temp_dir"
  rm -rf "$sdk_dir"
  mv "${temp_dir}/flutter" "$sdk_dir"
fi

export PATH="${sdk_dir}/bin:${PATH}"
export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true

flutter --version
flutter pub get
flutter build web --release \
  --dart-define="STUDENTPAD_PUBLIC_WEB_ORIGIN=${STUDENTPAD_PUBLIC_WEB_ORIGIN:-}"
