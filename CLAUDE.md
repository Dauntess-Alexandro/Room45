# Room45 — project instructions

## Working with the user
- The user is a **complete beginner at coding**. Do not assume any programming knowledge.
- **Do the work yourself, end to end.** Don't hand the user code to paste, terminal commands to run, or multi-step manual procedures unless a step physically requires their GUI (e.g. clicking inside the Godot/Blender editor, downloading a file). When a manual step is unavoidable, give one short, explicit click-by-click instruction.
- Explain what you did in plain language, briefly. Avoid jargon; when a technical term is unavoidable, gloss it in one phrase.
- Prefer making the change and verifying it over describing how the user could do it.

## Godot / Blender tasks — use the MCP servers
Both are configured in `.mcp.json` and load at session start.

- **Godot tasks** → use the **`godot`** MCP server (run project, read debugger output, scenes/nodes). Works via CLI; nothing to open. Godot binary: `C:\tools\godot`.
- **Blender tasks** → use the **`blender`** MCP server (inspect/edit meshes, run Python in Blender, parse `.glb`). **Requires Blender to be open** with the BlenderMCP addon connected on **port 9876** (N-panel → BlenderMCP → "Connect to MCP server"). If a `blender` call fails with "Could not connect to Blender", tell the user to open Blender and connect on port 9876 — do not silently fall back.

Prefer these MCP tools over editing `.tscn`/`.gd`/`.glb` blind. Note: the `godot` server (Coding-Solo) can run/debug and create scenes but does NOT finely edit existing scenes — for in-place edits to `main.tscn` etc. still edit the file, then use `godot` to run and check for errors.

## What this project is
**Room45 — a VotV-style game** (atmospheric / Voices-of-the-Void-style first-person). Godot **4.6**, Forward+ renderer, 1920×1080.
- Main scene: `res://main.tscn`. Autoloads: `DisplaySettings` (`display_settings.gd`), `GameClock` (`game_clock.gd`).

## How to run / verify
Use the `godot` MCP `run_project` on `C:/Room45`, then `get_debug_output` to read errors/prints. Always verify a change by actually running it, not just by reasoning about the code.

## Key files (where things live)
- `main.tscn` — the whole level (rooms, lights, furniture, interactables). Most scene edits happen here.
- `player.gd` / `player.tscn` — first-person player (movement input is in `project.godot` `[input]`).
- `interactable.gd` — interaction system (look-at prompts, toggles). Light switches are `Interactables/*` nodes driven by this. `kind`/`prompt_text`/`switch_*` exported vars configure each one.
- `rostik_chat.gd` + `computer_terminal.gd` — in-game CRT terminal with an LLM chat with the friend "Ростик" (Groq; key in `groq_key.txt`).
- `game_clock.gd` / `clock_hands.gd` / `clock_tick.gd` — in-game time + wall-clock visuals. `sun_controller.gd` — day/night sun.
- `living_room_part.gd`, `furniture.gd` — room/furniture helpers. `pause_menu.gd` / `pause_menu.tscn` — pause UI.

## Asset pipeline
- 3D models live in `models/*.glb` (imported by Godot). Source/raw assets in `_raw/`.
- `tools/*.py` are **Blender / mesh build scripts** run headless (Blender 5.1 at `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`): e.g. `build_door_frame_mesh.py`, `texture_petard.py`, `build_atlas.py`, `slice_assets.py`, `process_portrait.py`. Run/debug these via the `blender` MCP or headless Blender, not by guessing.
- Known gotcha: `models/light_switch.glb` is a **single merged mesh** (no separate lever node, no animation) — the switch is faked by rotating the whole model under a `ButtonPivot`. A clean lever animation needs a model with a separate lever node.
