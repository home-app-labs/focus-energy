#!/bin/bash
# Builds the downloadable files for the version in VERSION:
#   dist/Focus-Energy.pkg   an installer that puts the app into /Applications
#   dist/Focus-Energy.zip   the bare app, for people who prefer to move it themselves, and for self-updates
#   dist/update.json        version, notes and the signature of the zip, read by installed copies
# Pass --publish to also tag the commit and create the GitHub release with both files attached.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
APP="build/Focus Energy.app"
DIST="dist"

UNIVERSAL=1 ./build.sh

rm -rf "$DIST"
mkdir -p "$DIST"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The installer payload: just the app, always installed to /Applications.
mkdir "$WORK/root"
cp -R "$APP" "$WORK/root/"
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
# Without this the installer would update a copy of the app found anywhere else on the disk.
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$WORK/component.plist"
pkgbuild --root "$WORK/root" --component-plist "$WORK/component.plist" \
    --identifier local.focusplus.pkg --version "$VERSION" --install-location /Applications \
    --scripts scripts/pkg "$WORK/app.pkg" >/dev/null

cat > "$WORK/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Focus Energy</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_localSystem="true"/>
    <volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
    <choices-outline><line choice="default"/></choices-outline>
    <choice id="default" title="Focus Energy"><pkg-ref id="local.focusplus.pkg"/></choice>
    <pkg-ref id="local.focusplus.pkg" version="$VERSION">app.pkg</pkg-ref>
</installer-gui-script>
XML
mkdir "$WORK/resources"
cat > "$WORK/resources/welcome.html" <<HTML
<html><body style="font-family: -apple-system, sans-serif; font-size: 13px;">
<p><b>Focus Energy $VERSION</b></p>
<p>A focus timer that also looks after your breaks.</p>
<p>This installer copies Focus Energy to your Applications folder and opens it. Nothing else is installed.</p>
<p>Free and open source: github.com/home-app-labs/focus-energy</p>
</body></html>
HTML
productbuild --distribution "$WORK/distribution.xml" --package-path "$WORK" \
    --resources "$WORK/resources" "$DIST/Focus-Energy.pkg" >/dev/null

ditto -c -k --keepParent "$APP" "$DIST/Focus-Energy.zip"

# update.json is what installed copies read to find and verify a new version.
# The zip is signed with the Home App Labs key in ~/.homeapplabs (see scripts/update-key.swift).
SIGNATURE="$(swift scripts/update-key.swift sign "$DIST/Focus-Energy.zip")"
python3 - "$VERSION" "$SIGNATURE" "$DIST" <<'PY'
import json, os, sys
version, signature, dist = sys.argv[1:4]
manifest = {
    "version": version,
    "notes": open(f"release-notes/{version}.md").read().split("**Install:**")[0].strip(),
    "url": f"https://github.com/home-app-labs/focus-energy/releases/download/v{version}/Focus-Energy.zip",
    "signature": signature,
    "size": os.path.getsize(f"{dist}/Focus-Energy.zip"),
}
json.dump(manifest, open(f"{dist}/update.json", "w"), indent=2)
PY

( cd "$DIST" && shasum -a 256 Focus-Energy.pkg Focus-Energy.zip > SHA256SUMS.txt )
# Leave one copy of the app on this Mac: the installed one. A second copy in build/ confuses Spotlight and the Dock.
rm -rf "$APP"
echo "Built version $VERSION:"
ls -lh "$DIST"

for arg in "$@"; do
    if [ "$arg" = "--publish" ]; then
        if [ -n "$(git status --porcelain)" ]; then echo "Commit your changes first." >&2; exit 1; fi
        git tag "v$VERSION"
        git push origin HEAD "v$VERSION"
        gh release create "v$VERSION" "$DIST/Focus-Energy.pkg" "$DIST/Focus-Energy.zip" "$DIST/update.json" "$DIST/SHA256SUMS.txt" \
            --title "Focus Energy $VERSION" --notes-file "release-notes/$VERSION.md"
    fi
done
