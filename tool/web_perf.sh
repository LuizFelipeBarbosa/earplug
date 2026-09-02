#!/usr/bin/env bash
# Phone testing: open http://<lan-ip>:8080/?perf=1 on a phone connected to the
# same Wi-Fi to see the in-app performance overlay.
# This LAN server uses plain HTTP, which is not a secure context. Geolocation and
# Clerk sign-in may not work; use the Netlify deploy preview for signed-in flows.
# With --lighthouse <url>, the script audits that already-deployed URL and exits
# without starting the blocking local server.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
cd "$repo_root"

lighthouse_url=""
flutter_args=()
while (($# > 0)); do
  case "$1" in
    --lighthouse)
      if (($# < 2)); then
        echo "error: --lighthouse requires a URL" >&2
        exit 2
      fi
      lighthouse_url="$2"
      shift 2
      ;;
    *)
      flutter_args+=("$1")
      shift
      ;;
  esac
done

build_command=(
  flutter build web
  --release
  --dart-define-from-file=config/dev.json
)
if ((${#flutter_args[@]} > 0)); then
  build_command+=("${flutter_args[@]}")
fi
"${build_command[@]}"

echo
echo "Bytes census"

main_js="build/web/main.dart.js"
if [[ -f "$main_js" ]]; then
  printf '  %-38s %s\n' "$main_js" "$(du -h "$main_js" | awk '{print $1}')"
else
  echo "  $main_js: not found"
fi

main_wasm="build/web/main.dart.wasm"
if [[ -f "$main_wasm" ]]; then
  printf '  %-38s %s\n' "$main_wasm" "$(du -h "$main_wasm" | awk '{print $1}')"
fi

fonts_dir="build/web/assets/assets/fonts"
if [[ -d "$fonts_dir" ]]; then
  printf '  %-38s %s\n' "$fonts_dir" "$(du -sh "$fonts_dir" | awk '{print $1}')"
fi

packages_dir="build/web/assets/packages"
if [[ -d "$packages_dir" ]]; then
  printf '  %-38s %s\n' "$packages_dir" "$(du -sh "$packages_dir" | awk '{print $1}')"
fi

if command -v brotli >/dev/null 2>&1; then
  if [[ -f "$main_js" ]]; then
    brotli_tmp="$(mktemp "${TMPDIR:-/tmp}/earplug-main.dart.js.XXXXXX")"
    brotli -q 11 -c "$main_js" >"$brotli_tmp"
    printf '  %-38s %s\n' "$main_js (brotli -q 11)" \
      "$(du -h "$brotli_tmp" | awk '{print $1}')"
    rm -f "$brotli_tmp"
  fi
else
  echo "  brotli is not installed; skipping compressed main.dart.js size"
fi

lan_ip=""
if command -v ipconfig >/dev/null 2>&1; then
  lan_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
fi
if [[ -z "$lan_ip" ]] && command -v hostname >/dev/null 2>&1; then
  lan_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
fi
lan_ip="${lan_ip:-0.0.0.0}"

echo
echo "Phone URL: http://$lan_ip:8080/?perf=1"

if [[ -n "$lighthouse_url" ]]; then
  npx --yes lighthouse "$lighthouse_url" \
    --form-factor=mobile \
    --throttling-method=simulate \
    --output=html \
    --output-path=build/lighthouse.html
  exit 0
fi

npx --yes serve -s build/web -l 8080
