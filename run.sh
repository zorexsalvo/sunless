#!/bin/zsh
set -e

PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"

SUNLESSRC="${HOME}/.sunlessrc"
if [[ -f "$SUNLESSRC" ]]; then
    set -a
    source "$SUNLESSRC"
    set +a
fi

if [[ ! -f sunless.png && ! -f sunny.png ]]; then
    echo "Error: No avatar image found. Place an image named sunless.png or sunny.png in this directory." >&2
    exit 1
fi

echo "Building Pet..."
swiftc *.swift -o Pet

if [[ -z "$PET_MOCK" && -z "$HERMES_API_URL" ]]; then
    echo "Warning: HERMES_API_URL is not set. The pet will show a setup message." >&2
    echo "         Set HERMES_API_KEY and HERMES_API_URL in ~/.sunlessrc to talk to Hermes." >&2
fi

if [[ -n "$PET_MOCK" ]]; then
    echo "Starting Pet in mock mode..."
else
    echo "Starting Pet..."
fi
./Pet
