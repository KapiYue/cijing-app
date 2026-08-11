#!/bin/sh

set -eu

# Xcode Cloud reuses the same CURRENT_PROJECT_VERSION on every run, so each
# archive would upload as build 1 and App Store Connect rejects the duplicate.
# CI_BUILD_NUMBER is the per-workflow counter Xcode Cloud increments for us.

script_directory=$(CDPATH= cd "$(dirname "$0")" && pwd)
repository_path=${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd "$script_directory/../.." && pwd)}
project_file="$repository_path/client/CiJing.xcodeproj/project.pbxproj"

if [ -z "${CI_BUILD_NUMBER:-}" ]; then
    echo "ci_pre_xcodebuild.sh: CI_BUILD_NUMBER is unset, keeping the checked-in build number."
    exit 0
fi

case "$CI_BUILD_NUMBER" in
    ''|*[!0-9]*)
        echo "error: CI_BUILD_NUMBER must be a positive integer." >&2
        exit 1
        ;;
esac

if [ ! -f "$project_file" ]; then
    echo "error: cannot find $project_file" >&2
    exit 1
fi

/usr/bin/sed -i '' -e "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;/g" "$project_file"

echo "ci_pre_xcodebuild.sh: CURRENT_PROJECT_VERSION set to $CI_BUILD_NUMBER"
/usr/bin/grep -c "CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;" "$project_file"
