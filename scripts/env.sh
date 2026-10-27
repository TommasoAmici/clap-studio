#!/bin/sh
# Shared toolchain setup (source this file).
#
# With only the Command Line Tools installed (no Xcode), the default macOS 27 SDK
# declares SwiftUI property wrappers as macros whose compiler plugin ships only with
# Xcode. The macOS 26 SDK does not, so we build against it when Xcode is absent.
# Builds with a full Xcode installation use the default SDK.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Keep compiler caches with the build so restricted shells need no home-folder writes.
# SwiftPM compiles the manifest separately and needs its own cache override.
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/clang-module-cache}"
SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$ROOT/.build/manifest-module-cache}"
export CLANG_MODULE_CACHE_PATH SWIFTPM_MODULECACHE_OVERRIDE
DEV_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
if [ -z "$DEV_DIR" ]; then
  echo "Apple developer tools are missing. Run xcode-select --install, finish the installer, then run scripts/setup.sh." >&2
  exit 1
fi
case "$DEV_DIR" in *.app) DEV_DIR="$DEV_DIR/Contents/Developer" ;; esac
export DEVELOPER_DIR="$DEV_DIR"
SWIFT="$(xcrun --find swift 2>/dev/null)" || {
  echo "Swift could not be found in the selected Apple developer tools. Run scripts/setup.sh --check." >&2
  exit 1
}
if [ -z "$SDKROOT" ]; then
  case "$DEV_DIR" in
    */CommandLineTools)
      for sdk in "$DEV_DIR"/SDKs/MacOSX26*.sdk; do
        [ -d "$sdk" ] && [ ! -L "$sdk" ] && export SDKROOT="$sdk" && break
      done ;;
  esac
fi
SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export SDKROOT
if [ ! -d "$SDKROOT" ]; then
  echo "SDKROOT does not name an installed SDK: $SDKROOT. Unset SDKROOT and run scripts/setup.sh --check." >&2
  exit 1
fi
SDK_VERSION="$(xcrun --sdk "$SDKROOT" --show-sdk-version)"
case "$DEV_DIR" in
  */CommandLineTools)
    if [ "${SDK_VERSION%%.*}" -ge 27 ]; then
      echo "These Command Line Tools need a macOS 26 SDK for SwiftUI. Install Command Line Tools with that SDK, or select full Xcode. See README.md." >&2
      exit 1
    fi ;;
esac
TESTING_PLUGINS="$(dirname "$(dirname "$SWIFT")")/lib/swift/host/plugins/testing"
if [ ! -f "$TESTING_PLUGINS/libTestingMacros.dylib" ]; then
  echo "The selected Swift toolchain is missing its Testing macro plugin. Install Apple developer tools with Swift 6 or newer." >&2
  exit 1
fi
