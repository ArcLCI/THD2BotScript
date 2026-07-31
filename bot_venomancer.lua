local J = require(GetScriptDirectory() .. "/THDFuncLib/thd_func")
local YuukaUnits = require(GetScriptDirectory() .. "/THDFuncLib/yuuka_units")

require(GetScriptDirectory() .. "/bot_generic")

local FLOWER_NAME = "ability_yuuka_flower"
local NIGHT_INVISIBLE = "modifier_thdots_yuukaex_flower_onnight_invisable"

local function IsValidTarget(target)
	return target ~= nil
		and not target:IsNull()
		and target:IsAlive()
		and target:CanBeSeen()
		and not target:IsInvulnerable()
end

local function GetOwnerHeroTarget(ownerBot, flower)
	local target = J.GetProperTarget(ownerBot)
	if IsValidTarget(target)
	and target:IsHero()
	and not J.IsSuspiciousIllusion(target)
	and GetUnitToUnitDistance(flower, target) <= flower:GetAttackRange()
	then
		return target
	end

	if J.IsGoingOnSomeone(ownerBot) or J.IsRetreating(ownerBot) or J.IsDefending(ownerBot) then
		for _, enemy in pairs(CachedGetNearbyHeroes(flower, flower:GetAttackRange(), true, BOT_MODE_NONE)) do
			if IsValidTarget(enemy) and enemy:IsHero() and not J.IsSuspiciousIllusion(enemy) then return enemy end
		end
	end
	return nil
end

local function FlowerThink(ownerBot, flower)
	local heroTarget = GetOwnerHeroTarget(ownerBot, flower)
	if heroTarget ~= nil then
		J.ActionAttackUnit(flower, "yuuka_flower_hero", heroTarget, false, 0.45)
		return
	end

	local isNightHidden = flower:HasModifier(NIGHT_INVISIBLE)
	local isPermanent = YuukaUnits.IsPermanentFlower(flower)
	if isNightHidden and isPermanent ~= false then
		-- 永久花夜间优先充当不可见视野节点，不为小兵或建筑主动暴露三秒。
		return
	end

	local desire, target = ConsiderAttack(flower)
	if desire > BOT_ACTION_DESIRE_NONE and IsValidTarget(target)
	and GetUnitToUnitDistance(flower, target) <= flower:GetAttackRange()
	then
		J.ActionAttackUnit(flower, "yuuka_flower_attack", target, false, 0.45)
	end
end

function MinionThink(hMinionUnit)
	if hMinionUnit == nil or hMinionUnit:IsNull() or not hMinionUnit:IsAlive() then return end
	local ownerBot = GetBot()
	if hMinionUnit:GetUnitName() == FLOWER_NAME then
		FlowerThink(ownerBot, hMinionUnit)
		return
	end

	if hMinionUnit:IsIllusion() then
		-- 大招分身只交给一次幻象控制，避免随后再进入通用恶魔控制覆盖命令。
		THD2MinionThink(hMinionUnit)
		return
	end

	THD2DemonThink(hMinionUnit)
end
