#!/bin/zsh
# Start the web app. The key comes from the env file next to this script and is never printed.
cd "$(dirname "$0")/webapp" && uv run --env-file ../.env uvicorn app:app --port 8000
