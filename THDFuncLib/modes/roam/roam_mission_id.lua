local MissionID = {}

function MissionID.EstimateDotaStart(dotaNow, gameNow, pingTime)
	dotaNow = tonumber(dotaNow) or 0
	gameNow = tonumber(gameNow) or dotaNow
	pingTime = tonumber(pingTime) or gameNow
	return dotaNow - math.max(0, gameNow - pingTime)
end

function MissionID.Build(leaderID, targetID, dotaStartTime)
	local roundedTime = math.floor((tonumber(dotaStartTime) or 0) + 0.5)
	return string.format('%s-%s-%d', tostring(leaderID), tostring(targetID), roundedTime)
end

return MissionID
