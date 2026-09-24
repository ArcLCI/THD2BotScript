local BotProfile = {}

BotProfile.DAMAGE = "damage"
BotProfile.DAMAGE_SPELL = "damage_spell"
BotProfile.FRONTLINE = "frontline"
BotProfile.SUPPORT = "support"

local PROFILE_MARKER_ABILITY = "ability_thd2_bot_profile"
local profilesByLevel = {
	[1] = BotProfile.DAMAGE,
	[2] = BotProfile.FRONTLINE,
	[3] = BotProfile.SUPPORT,
}

-- Bot 侧只读取地图添加的隐藏能力等级，不依赖地图脚本中的注册表实现。
function BotProfile.GetProfile(bot)
	if bot == nil then return nil end
	local marker = bot:GetAbilityByName(PROFILE_MARKER_ABILITY)
	if marker == nil then return nil end
	if marker:GetLevel() == 2 then
		local unitName = bot.GetUnitName ~= nil and bot:GetUnitName() or nil
		-- 兼容旧法系标记2；新局法系辅助统一使用support标记3。
		if unitName == "npc_dota_hero_spectre" then return BotProfile.SUPPORT end
	end
	return profilesByLevel[marker:GetLevel()]
end

function BotProfile.GetProfileOrDefault(bot, defaultProfile)
	return BotProfile.GetProfile(bot) or defaultProfile or BotProfile.DAMAGE
end

function BotProfile.IsDamage(bot)
	return BotProfile.GetProfile(bot) == BotProfile.DAMAGE
end

function BotProfile.IsFrontline(bot)
	return BotProfile.GetProfile(bot) == BotProfile.FRONTLINE
end

function BotProfile.IsSupport(bot)
	return BotProfile.GetProfile(bot) == BotProfile.SUPPORT
end

function BotProfile.SelectByProfile(bot, valuesByProfile, defaultProfile)
	if type(valuesByProfile) ~= "table" then return nil, BotProfile.GetProfile(bot) end
	local profile = BotProfile.GetProfileOrDefault(bot, defaultProfile)
	return valuesByProfile[profile] or valuesByProfile[defaultProfile], profile
end

return BotProfile
