# CADDIY

Scan, clean up and edit 3D models, built for kids. Mascot: Caddiy.

- `mac/` native SwiftUI Mac app (build with `./build_app.sh --bundle`)
- `bench/` Python mesh cleanup and edit helpers
- `webapp/` FastAPI helper
- `guidance/` scan guidance

Put `ANTHROPIC_API_KEY=...` in a `.env` file (not committed) so plain-language edits work.

Plans: [design](docs/scene-plan-ux.md), [technical](docs/scene-plan-technical.md)
