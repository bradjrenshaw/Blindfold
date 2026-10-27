# Blindfold — working notes

Screen-reader mod for Balatro (LÖVE / LuaJIT), Lovely-only. `src/` is the mod;
`scripts\deploy.ps1` links `%APPDATA%\Balatro\Mods\Blindfold` to it, so edits
are live on the next game start (or the next hot reload, below).

- Tests: `scripts\run_tests.ps1` (headless harnesses in `tests\`, plain Lua).
- Log: `%APPDATA%\Balatro\blindfold.log` (every spoken line, plus diagnostics).
- Vanilla game source for reference: `game_src\`.
- Steamodded (when installed for testing) lives at
  `%APPDATA%\Balatro\Mods\smods` (a git checkout of a release tag). Blindfold
  must keep working with and without it.

## Dev server + hot reload

`scripts\run_game.ps1` enables the dev server (marker file
`%APPDATA%\Balatro\blindfold_dev.enable`), launches the game through Steam and
blocks until it exits — run it in the background. `-NoLaunch` only drops the
marker; `-Disable` removes it. The server listens on `http://127.0.0.1:8772`:

| Route | |
| --- | --- |
| `GET /health` | liveness (answered off the main thread) |
| `POST /reload` | hot reload: re-run `core.lua` and the whole module tree from disk |
| `GET /speech?since=N` | spoken lines since cursor N; the reply starts with `cursor: M` |
| `GET /module` | generation number and hooked-function count |
| `POST /eval` | Lua in the body; returns an expression's value or what a chunk `print`s. `BA` = live Blindfold, `H` = host, `dump(v, depth)`; REPL globals persist |
| `GET /state` | stage, state, menu, active owned overlay, Steamodded present, and render health (BLACK = the game is drawing nothing) |
| `GET /overlay` | the active overlay's nodes, labels, cursor and links (the F8 dump) |
| `POST /key` | a LÖVE key name (`down`, `return`, `ctrl+s`), pressed through the game's Controller like the keyboard |
| `GET /screenshot` | saves the game's render canvas as a PNG and returns its path; works with the window minimized or unfocused (no CRT effect) |

Loop: edit `src\...`, `curl -X POST 127.0.0.1:8772/reload`, drive with
`/key`, read `/speech` and `/overlay`.

### Host vs generation
- **Host** (survives reloads; changes need a game restart): `host.lua`,
  `dev/server.lua`, `dev/server_thread.lua`, `speech.lua` (native speech
  library), and the `love.update` pump wrapper at the top of `core.lua`.
- **Generation** (everything else, including `dev/routes.lua`): re-run by
  `/reload` with a fresh `ba_require` cache.
- **Every wrap of a game function goes through `hook(tbl, key, function(orig)
  return function(...) ... end end)`** (host.lua). It wraps once with a
  permanent trampoline and re-points it per generation. Assigning over a game
  function directly would stack a new wrapper on every reload.
- Releases never ship `src/dev/` (both release scripts drop it); without it,
  or without the marker, there is no server.
