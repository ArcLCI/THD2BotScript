local M = {}
local serial = 0
local states = setmetatable({}, {__mode = 'k'})

-- 原生插件只暂停自动整理；换槽、背包冷却、物品使用仍由现有生命周期控制。
-- 每次续租1.5秒，原生端另有30秒硬上限；插件缺失/关闭时保持原有行为。
function M.Touch(bot, request)
	if bot == nil or bot ~= GetBot() or request == nil then return false end
	if not bot:IsAlive() then M.Release(bot, request); return false end
	local state = states[bot]
	if state == nil or state.request ~= request then
		if state ~= nil then M.Release(bot, state.request) end
		serial = serial + 1
		state = {request = request, token = serial}
		states[bot] = state
	end
	local bridge = _G.__THDBackpackLeaseR1
	local result = 0
	if type(bridge) == 'function' then
		local ok, value = pcall(bridge, 1.5, state.token)
		result = ok and value or -1
	end
	local status = type(bridge) ~= 'function' and 'unavailable'
		or (result == 1 and 'protected' or (result == 0 and 'disabled' or 'rejected'))
	if state.status ~= status then
		print('[THD][BackpackGuard] run=BACKPACK-GUARD-20261001-R1 status=' .. status .. ' token=' .. tostring(state.token))
		state.status = status
	end
	return result == 1
end

function M.Release(bot, request)
	local state = states[bot]
	if state == nil or (request ~= nil and state.request ~= request) then return end
	local bridge = _G.__THDBackpackLeaseR1
	if bot == GetBot() and type(bridge) == 'function' then pcall(bridge, 0, state.token) end
	states[bot] = nil
end

return M
