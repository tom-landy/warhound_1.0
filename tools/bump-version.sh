#!/bin/sh
# Bumps the app version by one step (0.10 -> 0.11) for the iPhone and watch apps,
# and sets the build number to match (11). Run before each update:
#   tools/bump-version.sh
set -e
cd "$(dirname "$0")/.."
P=Orbit.xcodeproj/project.pbxproj
current=$(grep -m1 -o 'MARKETING_VERSION = 0\.[0-9]*;' "$P" | grep -o '0\.[0-9]*')
minor=${current#0.}
next=$((minor + 1))
sed -i.bak "s/MARKETING_VERSION = 0\.$minor;/MARKETING_VERSION = 0.$next;/g; s/CURRENT_PROJECT_VERSION = $minor;/CURRENT_PROJECT_VERSION = $next;/g" "$P"
rm -f "$P.bak"
echo "0.$minor -> 0.$next"
