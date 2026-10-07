#!/bin/sh
# Shared toolchain setup (source this file).
#
# With only the Command Line Tools installed (no Xcode), the default macOS 27 SDK
# declares SwiftUI property wrappers as macros whose compiler plugin ships only with
# Xcode. The macOS 26 SDK does not, so we build against it when Xcode is absent.
# Builds with a full Xcode installation use the default SDK.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$SDKROOT" ]; then
  case "$(xcode-select -p 2>/dev/null)" in
    */CommandLineTools)
      for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk; do
        [ -d "$sdk" ] && [ ! -L "$sdk" ] && export SDKROOT="$sdk" && break
      done ;;
  esac
fi
SWIFT_BIN_DIR="$(dirname "$(command -v swift)")"
TESTING_PLUGINS="$SWIFT_BIN_DIR/../lib/swift/host/plugins/testing"
