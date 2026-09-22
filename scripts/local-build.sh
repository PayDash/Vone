#!/usr/bin/env bash
#
# Vone (DynamicIsland)
# Copyright (C) 2024-2026 Vone Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# Builds Vone locally and signs it the same way every time.
#
# Why this exists: an ad-hoc signed build (`CODE_SIGN_IDENTITY="-"`) has a code
# identity derived from the binary's own hash, so every rebuild is a different
# app as far as macOS is concerned. Accessibility / Full Disk Access / Screen
# Recording grants are keyed to that identity, and so are Keychain item ACLs, so
# a new build re-prompts for all of them. Signing with one stable certificate
# fixes both.
#
# Create the identity once (see the message this script prints if it is missing).
# Pass --ad-hoc to build without it, --no-launch to only build.
#
# Note: a self-signed signature still cannot carry the restricted
# `com.apple.security.mach-services` entitlement, so the extension XPC service
# stays disabled in local builds (roadmap §9.5). Only a real Apple certificate
# (Apple Development / Developer ID) restores it.

set -euo pipefail

IDENTITY="${VONE_SIGN_IDENTITY:-Vone Local Dev}"
CONFIGURATION="${VONE_CONFIGURATION:-Debug}"
SCHEME="DynamicIsland"
PROJECT="DynamicIsland.xcodeproj"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="$ROOT/build/vone-adhoc.entitlements"

LAUNCH=1
for argument in "$@"; do
    case "$argument" in
        --no-launch) LAUNCH=0 ;;
        --ad-hoc) IDENTITY="-" ;;
        -h|--help)
            sed -n '17,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $argument" >&2; exit 2 ;;
    esac
done

cd "$ROOT"

if [[ "$IDENTITY" != "-" ]] && ! security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\""; then
    cat >&2 <<EOF
No "$IDENTITY" code-signing identity in the login keychain.

Without it this script would fall back to a build that re-asks for every
permission on each run, so create one once:

  WORK=\$(mktemp -d) && umask 077 && cd "\$WORK"
  OPENSSL=\$(command -v /opt/homebrew/opt/openssl@3/bin/openssl || command -v openssl)
  "\$OPENSSL" req -new -newkey rsa:2048 -nodes -x509 -days 3650 \\
    -keyout key.pem -out cert.pem -subj "/CN=$IDENTITY" \\
    -addext "extendedKeyUsage=critical,codeSigning" \\
    -addext "keyUsage=critical,digitalSignature" \\
    -addext "basicConstraints=critical,CA:false"
  "\$OPENSSL" pkcs12 -export -legacy -out identity.p12 -inkey key.pem -in cert.pem -passout pass:vonelocal
  security import identity.p12 -k "\$HOME/Library/Keychains/login.keychain-db" -P vonelocal \\
    -T /usr/bin/codesign -T /usr/bin/security
  security add-trusted-cert -r trustRoot -p codeSign -k "\$HOME/Library/Keychains/login.keychain-db" cert.pem
  cd / && rm -rf "\$WORK"

(The macOS importer needs a legacy-encoded PKCS#12, which is what -legacy is for.)

Or run this script with --ad-hoc to accept the re-prompting.
EOF
    exit 1
fi

echo "==> Building $SCHEME ($CONFIGURATION) signed with: $IDENTITY"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' build \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    > /tmp/vone-local-build.log 2>&1 || {
        echo "Build failed. Last errors:" >&2
        grep -E "error:" /tmp/vone-local-build.log >&2 | head -20 || tail -20 /tmp/vone-local-build.log >&2
        exit 1
    }
echo "    build succeeded (full log: /tmp/vone-local-build.log)"

# Anchored on the whole key: a suffix match also catches
# PRECOMPS_INCLUDE_HEADERS_FROM_BUILT_PRODUCTS_DIR = YES.
SHOW_SETTINGS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null)"
PRODUCTS_DIR="$(sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' <<< "$SHOW_SETTINGS" | head -1)"
FULL_PRODUCT_NAME="$(sed -n 's/^ *FULL_PRODUCT_NAME = //p' <<< "$SHOW_SETTINGS" | head -1)"

APP="$PRODUCTS_DIR/$FULL_PRODUCT_NAME"
[[ -d "$APP" ]] || { echo "Built app not found at $APP" >&2; exit 1; }
echo "==> App: $APP"

# The entitlement file carries $(PRODUCT_BUNDLE_IDENTIFIER), which codesign does
# not expand for us.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
EXPANDED="$(mktemp -t vone-entitlements)"
sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" "$ENTITLEMENTS" > "$EXPANDED"

# Re-signed here rather than through CODE_SIGN_ENTITLEMENTS because a relative
# path in that setting is resolved against every target's own SRCROOT, which
# breaks each Swift package in the dependency graph.
echo "==> Re-signing with $ENTITLEMENTS"
codesign --force --sign "$IDENTITY" --entitlements "$EXPANDED" "$APP"
rm -f "$EXPANDED"

codesign --verify --strict "$APP" && echo "    signature verified"
echo "    identity:   $(codesign -dvv "$APP" 2>&1 | awk -F'=' '/^Authority/{print $2; exit}')"
echo "    requirement: $(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"

if [[ "$LAUNCH" == "1" ]]; then
    pkill -f "$FULL_PRODUCT_NAME/Contents/MacOS/" 2>/dev/null || true
    sleep 1
    open "$APP"
    echo "==> Launched"
fi
