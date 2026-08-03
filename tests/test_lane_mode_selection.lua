local failures = 0

local function CheckEqual(actual, expected, message)
    if actual ~= expected then
        failures = failures + 1
        io.stderr:write(string.format('FAIL: %s (expected=%s actual=%s)\n', message, tostring(expected), tostring(actual)))
    end
end

LANE_TOP = 1
LANE_MID = 2
LANE_BOT = 3
TEAM_RADIANT = 2
TEAM_DIRE = 3
BOT_MODE_NONE = 0
BOT_MODE_PUSH_TOWER_TOP = 6
BOT_MODE_PUSH_TOWER_MID = 7
BOT_MODE_PUSH_TOWER_BOT = 8
BOT_MODE_DEFEND_TOWER_TOP = 11
BOT_MODE_DEFEND_TOWER_MID = 12
BOT_MODE_DEFEND_TOWER_BOT = 13
BOT_MODE_DESIRE_NONE = 0

local now = 0
function GameTime() return now end
function DotaTime() return now end
function GetScriptDirectory() return '.' end
function GetTeam() return TEAM_RADIANT end
function GetOpposingTeam() return TEAM_DIRE end
function GetTower() return nil end
function GetAncient()
    return {GetLocation = function() return {x = 0, y = 0, z = 0} end}
end
function GetGlyphCooldown() return 1 end

local J = {
    Utils = {
        DebugMode = false,
        GameStates = {},
        IsHumanPlayerInTeam = function() return true end,
    },
    Retreat = {
        HIGH = 2,
        CRITICAL = 3,
        GetState = function() return {severity = 0} end,
    },
}

local Timer = {
    GetOrComputeBotLane = function(_, _, _, _, computeFn)
        return computeFn()
    end,
}

package.preload['./THDFuncLib/thd_func'] = function() return J end
package.preload['./thd2_timer'] = function() return Timer end
package.preload['./thd2_scheduler'] = function() return {} end

local Defend = dofile('THDFuncLib/aba_defend.lua')
local defendBot = {}
function defendBot:GetTeam() return TEAM_RADIANT end
function defendBot:GetPlayerID() return 0 end

local laneOrders = {
    {LANE_TOP, LANE_MID, LANE_BOT},
    {LANE_BOT, LANE_MID, LANE_TOP},
    {LANE_MID, LANE_TOP, LANE_BOT},
}

for orderIndex, order in ipairs(laneOrders) do
    local calls = {}
    Defend.ComputeDefendDesire = function(_, lane)
        calls[lane] = (calls[lane] or 0) + 1
        return lane * 0.1
    end

    for _, lane in ipairs(order) do
        CheckEqual(Defend.GetDefendDesire(defendBot, lane), lane * 0.1, 'defend desire for order '..orderIndex..' lane '..lane)
    end
    CheckEqual(calls[LANE_TOP], 1, 'TOP must be evaluated once for order '..orderIndex)
    CheckEqual(calls[LANE_MID], 1, 'MID must be evaluated once for order '..orderIndex)
    CheckEqual(calls[LANE_BOT], 1, 'BOT must be evaluated once for order '..orderIndex)
end

local Push = dofile('THDFuncLib/aba_push.lua')
local pushBot = {activeMode = BOT_MODE_PUSH_TOWER_TOP}
function pushBot:GetActiveMode() return self.activeMode end
function pushBot:GetPlayerID() return 0 end

local selectionCalls = 0
Push.WhichLaneToPush = function()
    selectionCalls = selectionCalls + 1
    if selectionCalls == 1 then return LANE_TOP end
    return LANE_MID
end

now = 0
CheckEqual(Push.GetStablePushLane(pushBot, LANE_TOP), LANE_TOP, 'initial push selection')
now = 2
CheckEqual(Push.GetStablePushLane(pushBot, LANE_TOP), LANE_TOP, 'push selection remains stable inside fixed window')
CheckEqual(selectionCalls, 1, 'push selector is not recomputed inside fixed window')
now = 3.1
CheckEqual(Push.GetStablePushLane(pushBot, LANE_TOP), LANE_MID, 'active TOP mode must not renew an expired push lock')
CheckEqual(selectionCalls, 2, 'push selector recomputes after fixed window')

pushBot.StablePushLane = nil
local lane, reason = Push.SelectLaneByScores(pushBot, 100, 100, 100)
CheckEqual(lane, LANE_MID, 'equal push scores use neutral MID fallback')
CheckEqual(reason, 'tie_mid', 'equal push score reason')

pushBot.StablePushLane = LANE_TOP
lane, reason = Push.SelectLaneByScores(pushBot, 100, 90, 120)
CheckEqual(lane, LANE_TOP, 'small score improvement stays on previous lane')
CheckEqual(reason, 'hysteresis', 'small score improvement reason')

lane, reason = Push.SelectLaneByScores(pushBot, 100, 80, 120)
CheckEqual(lane, LANE_MID, 'material score improvement switches lane')
CheckEqual(reason, 'lowest_score', 'material score improvement reason')

if failures > 0 then
    os.exit(1)
end

print('lane mode selection tests passed')
