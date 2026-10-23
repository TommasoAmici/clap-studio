#!/bin/sh
# Checks Apple tools and installs the pinned model-export tools.
#   scripts/setup.sh                check Swift/SDK; install uv and Python
#   scripts/setup.sh --check        check Swift/SDK only, without installing
#   scripts/setup.sh --model-tools  also prepare tools/.venv for CLAP export
set -e
CHECK=0
MODEL_TOOLS=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1 ;;
    --model-tools) MODEL_TOOLS=1 ;;
    --help)
      sed -n '2,5p' "$0"
      exit 0 ;;
    *) echo "Unknown option: $arg. Use --check or --model-tools." >&2; exit 2 ;;
  esac
done
if [ "$CHECK" = 1 ] && [ "$MODEL_TOOLS" = 1 ]; then
  echo "--check does not install model tools. Choose one option." >&2
  exit 2
fi
if [ "$(uname -s)" != Darwin ]; then
  echo "Clap Studio builds on macOS only." >&2
  exit 1
fi
. "$(dirname "$0")/env.sh"
cd "$ROOT"
SWIFT_VERSION="$("$SWIFT" --version)"
SWIFT_MAJOR="$(printf '%s\n' "$SWIFT_VERSION" | sed -n 's/.*Swift version \([0-9][0-9]*\).*/\1/p' | head -1)"
if [ -z "$SWIFT_MAJOR" ] || [ "$SWIFT_MAJOR" -lt 6 ]; then
  echo "Apple Swift 6 or newer is needed for the Swift Testing suite. Update the selected Apple developer tools." >&2
  exit 1
fi
printf 'Developer tools: %s\nSwift: %s\nSDK: %s (%s)\nTesting plugins: %s\n' \
  "$DEV_DIR" "$SWIFT_VERSION" "$SDKROOT" "$SDK_VERSION" "$TESTING_PLUGINS"
[ "$CHECK" = 0 ] || exit 0

if ! command -v mise >/dev/null 2>&1; then
  if [ -x "$HOME/.local/bin/mise" ]; then
    export PATH="$HOME/.local/bin:$PATH"
  elif command -v brew >/dev/null 2>&1; then
    brew install mise
  else
    echo "Install mise (https://mise.jdx.dev/getting-started.html), then run this script again. Swift builds and tests already work without it." >&2
    exit 1
  fi
fi
mise trust "$ROOT/mise.toml"
mise install uv python
MODEL_PYTHON_BIN="$(mise which python)"
MODEL_UV_BIN="$(mise which uv)"
MODEL_PYTHON="$("$MODEL_PYTHON_BIN" -c 'import platform; print(platform.python_version())')"
if [ "$MODEL_TOOLS" = 1 ]; then
  if [ -x tools/.venv/bin/python ]; then
    VENV_VERSION="$(tools/.venv/bin/python -c 'import platform; print(platform.python_version())')"
    if [ "$VENV_VERSION" != "$MODEL_PYTHON" ]; then
      echo "tools/.venv uses Python $VENV_VERSION; the model tools use $MODEL_PYTHON. Move that environment aside, then rerun --model-tools." >&2
      exit 1
    fi
  else
    "$MODEL_UV_BIN" venv --python "$MODEL_PYTHON_BIN" tools/.venv
  fi
  "$MODEL_UV_BIN" pip install --python tools/.venv/bin/python \
    --default-index https://pypi.org/simple -r tools/requirements.txt
fi
echo "Ready. Run scripts/build.sh, scripts/test.sh, or scripts/bundle.sh."
