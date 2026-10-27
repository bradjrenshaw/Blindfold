-- ui/states.lua — G.STATE groupings shared by the overlays and screen keys.
-- Steamodded adds its own states: every booster opens in
-- SMODS_BOOSTER_OPENED (vanilla packs included) instead of the five vanilla
-- pack states, and redeeming a voucher passes through SMODS_REDEEM_VOUCHER.
-- Both are nil without Steamodded, so these checks reduce to vanilla's.
local M = {}

-- A booster pack is open (by state).
function M.is_pack(st)
    local S = G and G.STATES
    if not S or st == nil then return false end
    return st == S.TAROT_PACK or st == S.SPECTRAL_PACK or st == S.STANDARD_PACK
        or st == S.BUFFOON_PACK or st == S.PLANET_PACK
        or (S.SMODS_BOOSTER_OPENED ~= nil and st == S.SMODS_BOOSTER_OPENED)
end

-- Steamodded's transient voucher-redeem state (the shop comes back after).
function M.is_voucher_redeem(st)
    local S = G and G.STATES
    return S ~= nil and S.SMODS_REDEEM_VOUCHER ~= nil and st == S.SMODS_REDEEM_VOUCHER
end

return M
