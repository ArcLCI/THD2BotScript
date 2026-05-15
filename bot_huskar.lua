local J = require(GetScriptDirectory() ..  "/THDFuncLib/thd_func")
require(GetScriptDirectory() ..  "/bot_generic")

----------------------------------------------------------------------------------------------------

local nNextMoveTime = 0
local BOX_MOVE_INTERVAL = 0.65
local BOX_LOCATION_BUCKET = 260

local function GetLocationKey(vLoc, bucket)
    if vLoc == nil then return 'nil' end
    if bucket == nil then bucket = BOX_LOCATION_BUCKET end
    local x = math.floor(vLoc.x / bucket + 0.5) * bucket
    local y = math.floor(vLoc.y / bucket + 0.5) * bucket
    return tostring(x) .. ':' .. tostring(y)
end

local function ShouldMoveBox(hMinionUnit, vLoc)
    local key = GetLocationKey(vLoc, BOX_LOCATION_BUCKET)
    if hMinionUnit.thdLastBoxMoveKey == key and DotaTime() < (hMinionUnit.thdNextBoxMoveTime or 0) then
        return false
    end

    hMinionUnit.thdLastBoxMoveKey = key
    hMinionUnit.thdNextBoxMoveTime = DotaTime() + BOX_MOVE_INTERVAL
    return true
end

function MinionThink( hMinionUnit )

	if hMinionUnit:IsIllusion() then
        THD2MinionThink( hMinionUnit )
    end

	if hMinionUnit:GetUnitName() == "npc_thdots_unit_minoriko02_box" then
        local ownerBot = GetBot()
        local nMoveRange = 1200
        local nRadius = 500
        local locationBox = CachedFindAoELocation( ownerBot, 1, false, true, hMinionUnit:GetLocation(), nMoveRange, nRadius, 0, 0 )
        if locationBox ~= nil and locationBox.targetloc ~= nil
        and DotaTime() >= nNextMoveTime
        and ShouldMoveBox(hMinionUnit, locationBox.targetloc)
        then
            J.ActionMoveToLocation(hMinionUnit, 'minoriko_box_move', locationBox.targetloc, BOX_MOVE_INTERVAL, BOX_LOCATION_BUCKET)
            nNextMoveTime = DotaTime() + BOX_MOVE_INTERVAL
        end
    end

end