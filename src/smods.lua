-- smods.lua — the main file Steamodded's metadata (Blindfold.json) requires.
-- Blindfold is a Lovely mod: Lovely loads and boots it (lovely.toml), with
-- or without Steamodded. The JSON gives Steamodded's Mods menu a proper
-- name, author, version and description; this file adds the Config button,
-- which shows Blindfold's settings (the same tab as Options -> Blindfold).
-- Resolved when opened, so it doesn't matter that Blindfold boots later.
local mod = SMODS and SMODS.current_mod
if mod then
    mod.config_tab = function()
        local BF = _G.Blindfold
        if BF and BF.settings_tab then return BF.settings_tab("mods") end
        return { n = G.UIT.ROOT, config = { colour = G.C.CLEAR }, nodes = {} }
    end
end
