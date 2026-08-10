# Blindfold test harnesses

Headless regression tests: each file loads the real mod modules via a tiny
`ba_require` loader, stubs the game globals it touches, and exits nonzero on
failure. No LÖVE or Balatro needed — any plain Lua 5.1+ interpreter works
(they are routinely run under Lua 5.4; beware its `tostring(1e15)` and
`tonumber("inf")` differences from LuaJIT when writing number checks).

Run everything from the repo root:

    scripts\run_tests.ps1

or one suite by hand (the optional argument is the repo root, default `.`):

    lua tests\edge_test.lua

| File | Covers |
| --- | --- |
| `check_loc.lua` | every locale mirrors `loc/en.lua`'s key tree with matching `{placeholders}` |
| `edge_test.lua` | dispatcher navigation: silent edges, real moves speak, Home/End confirm |
| `refresh_test.lua` | `refresh_identity`: same-screen rebuilds re-announce the kept cursor |
| `table_test.lua` | the poker-hands 2D table (full-row primary, header crossings, column walks) |
| `blinds_test.lua` | the run-info blinds row (panel readouts, reward gate, fallback drop) |
| `rebind_test.lua` | rebind capture (modifier combos, bare modifiers) and binding conflicts |
| `click_order_test.lua` | click-order play/discard reordering + the "selection N" announcement |
| `desc_test.lua` | custom card bodies: Misprint churn+range, Blueprint/Brainstorm compat |
| `status_test.lua` | Ctrl+letter status readouts incl. shop reroll cost and naneinf parity |
| `fmt_test.lua` | scoring verbosity styles, popup normalization, HUD number parity |
| `events_test.lua` | run-event dispatcher: group toggles, always-on history, history cap |
