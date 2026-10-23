#!/bin/sh
# Checks setup diagnostics with fake Apple tools; does not install or change anything on this Mac.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d /tmp/clap-setup-test.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT HUP INT TERM
mkdir -p "$SCRATCH/bin"
export CLAP_TEST_DEV="$SCRATCH/CommandLineTools"
export CLAP_TEST_MISE_LOG="$SCRATCH/mise-log"
mkdir -p "$CLAP_TEST_DEV/usr/bin" "$CLAP_TEST_DEV/usr/lib/swift/host/plugins/testing"
mkdir -p "$CLAP_TEST_DEV/SDKs/MacOSX26.5.sdk" "$CLAP_TEST_DEV/SDKs/MacOSX27.0.sdk"
touch "$CLAP_TEST_DEV/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
cat > "$SCRATCH/bin/xcode-select" <<'EOF'
#!/bin/sh
[ "${CLAP_TEST_NO_DEV:-0}" = 0 ] || exit 1
echo "$CLAP_TEST_DEV"
EOF
cat > "$SCRATCH/bin/xcrun" <<'EOF'
#!/bin/sh
case "$*" in
  "--find swift") echo "$CLAP_TEST_DEV/usr/bin/swift" ;;
  "--sdk macosx --show-sdk-path") echo "$CLAP_TEST_DEV/SDKs/MacOSX27.0.sdk" ;;
  *--show-sdk-version)
    case "$2" in *26.5*) echo 26.5 ;; *) echo 27.0 ;; esac ;;
  *) exit 1 ;;
esac
EOF
cat > "$CLAP_TEST_DEV/usr/bin/swift" <<'EOF'
#!/bin/sh
echo "Apple Swift version ${CLAP_TEST_SWIFT_VERSION:-6.4} (test)"
EOF
cat > "$SCRATCH/bin/swift" <<'EOF'
#!/bin/sh
echo "The Swift on PATH must not be used" >&2
exit 42
EOF
cat > "$SCRATCH/bin/mise" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CLAP_TEST_MISE_LOG"
case "$*" in
  "which python") echo "$CLAP_TEST_DEV/usr/bin/python" ;;
  "which uv") echo "$CLAP_TEST_DEV/usr/bin/uv" ;;
  *) echo "mise test" ;;
esac
EOF
cat > "$CLAP_TEST_DEV/usr/bin/python" <<'EOF'
#!/bin/sh
echo "3.12.9"
EOF
cat > "$CLAP_TEST_DEV/usr/bin/uv" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CLAP_TEST_MISE_LOG"
EOF
chmod +x "$SCRATCH/bin/"* "$CLAP_TEST_DEV/usr/bin/"*
export PATH="$SCRATCH/bin:$PATH"
unset SDKROOT DEVELOPER_DIR TOOLCHAINS

expectFailure() {
    if "$@" > "$SCRATCH/output" 2>&1; then
        echo "Expected setup to reject: $*" >&2
        exit 1
    fi
}
contains() {
    if ! /usr/bin/grep -F "$1" "$SCRATCH/output" >/dev/null; then
        cat "$SCRATCH/output" >&2
        echo "Expected diagnostic: $1" >&2
        exit 1
    fi
}

"$ROOT/scripts/setup.sh" --check > "$SCRATCH/output" 2>&1
contains "MacOSX26.5.sdk"
contains "Apple Swift version 6.4"
[ ! -e "$CLAP_TEST_MISE_LOG" ] || { echo "--check must not install tools" >&2; exit 1; }
SDKROOT="$CLAP_TEST_DEV/SDKs/MacOSX26.5.sdk" "$ROOT/scripts/setup.sh" --check > "$SCRATCH/output" 2>&1
contains "MacOSX26.5.sdk"

expectFailure env CLAP_TEST_NO_DEV=1 "$ROOT/scripts/setup.sh" --check
contains "xcode-select --install"
expectFailure env CLAP_TEST_SWIFT_VERSION=5.9 "$ROOT/scripts/setup.sh" --check
contains "Swift 6"
expectFailure env SDKROOT="$SCRATCH/missing.sdk" "$ROOT/scripts/setup.sh" --check
contains "SDKROOT"

rmdir "$CLAP_TEST_DEV/SDKs/MacOSX26.5.sdk"
expectFailure "$ROOT/scripts/setup.sh" --check
contains "macOS 26 SDK"
mkdir -p "$CLAP_TEST_DEV/SDKs/MacOSX26.5.sdk"

mv "$CLAP_TEST_DEV/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib" "$SCRATCH/plugin"
expectFailure "$ROOT/scripts/setup.sh" --check
contains "Testing"
mv "$SCRATCH/plugin" "$CLAP_TEST_DEV/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

mkdir -p "$SCRATCH/Xcode.app/Contents"
mv "$CLAP_TEST_DEV" "$SCRATCH/Xcode.app/Contents/Developer"
export CLAP_TEST_DEV="$SCRATCH/Xcode.app/Contents/Developer"
DEVELOPER_DIR="$SCRATCH/Xcode.app" "$ROOT/scripts/setup.sh" --check > "$SCRATCH/output" 2>&1
contains "MacOSX27.0.sdk"
contains "$CLAP_TEST_DEV"

"$ROOT/scripts/setup.sh" > "$SCRATCH/output" 2>&1
contains "Ready."
cp "$CLAP_TEST_MISE_LOG" "$SCRATCH/output"
contains "install uv python"
contains "which python"

echo "Setup diagnostics passed."
