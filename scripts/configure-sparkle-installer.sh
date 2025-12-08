#!/bin/bash
# Configure Sparkle InstallerLauncher Service based on build configuration
# This script conditionally enables/disables the InstallerLauncher service
# to prevent Xcode attachment errors during Debug builds

set -e

# Path to the source Info.plist (use SRCROOT if available, otherwise relative)
if [ -n "${SRCROOT}" ]; then
    INFOPLIST_PATH="${SRCROOT}/ora/Info.plist"
else
    # Fallback: assume script is in scripts/ directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
    INFOPLIST_PATH="${PROJECT_ROOT}/ora/Info.plist"
fi

# Check if Info.plist exists
if [ ! -f "$INFOPLIST_PATH" ]; then
    echo "⚠️  Info.plist not found at $INFOPLIST_PATH"
    exit 1
fi

# Conditionally configure InstallerLauncher service
if [ "${CONFIGURATION}" = "Debug" ]; then
    echo "🔧 Disabling InstallerLauncher service for Debug build (prevents Xcode attachment errors)"
    /usr/libexec/PlistBuddy -c "Delete :SUEnableInstallerLauncherService" "$INFOPLIST_PATH" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :SUEnableInstallerLauncherService bool false" "$INFOPLIST_PATH" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :SUEnableInstallerLauncherService false" "$INFOPLIST_PATH"
else
    echo "🔧 Enabling InstallerLauncher service for Release build"
    /usr/libexec/PlistBuddy -c "Delete :SUEnableInstallerLauncherService" "$INFOPLIST_PATH" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :SUEnableInstallerLauncherService bool true" "$INFOPLIST_PATH" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :SUEnableInstallerLauncherService true" "$INFOPLIST_PATH"
fi

