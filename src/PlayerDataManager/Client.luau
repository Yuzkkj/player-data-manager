local Players = game:GetService("Players")

local Replica = require(script.Parent.Shared.Replica)
local Signal = require(script.Parent.Shared.Signal)

local localPlayer = Players.LocalPlayer

type CacheData = {
	Replica: typeof(Replica.New()),
	ValueChangedSignals: { [string]: Signal.Signal<any, any>? },
	ValueInsertedSignals: { [string]: Signal.Signal<any, any?>? },
	ValueRemovedSignals: { [string]: Signal.Signal<any, any>? },
}

local PlayerDataManager = {
	PlayerAdded = Signal.new() :: Signal.Signal<Player>,
	_cache = {} :: { [Player]: CacheData },
}

local function getCacheData(self: PlayerDataManager, player: Player): CacheData
	local playerCacheData = self._cache[player]

	if not playerCacheData and player ~= localPlayer then
		error(`No cache data founded for player: {player.Name}`)
	else
		repeat
			task.wait(1)
			playerCacheData = self._cache[player]
		until playerCacheData

		return playerCacheData
	end
end

local function start(self: PlayerDataManager): ()
	Replica.OnNew("PlayerData", function(replica)
		local player = replica.Tags.Player
		self._cache[player] = {
			Replica = replica,
			ValueChangedSignals = {},
			ValueInsertedSignals = {},
			ValueRemovedSignals = {},
		}

		if player ~= localPlayer then
			self.PlayerAdded:Fire(player)
		end

		replica:OnChange(function(action, path, value, index)
			local concatedPath = table.concat(path, "/")

			if action == "TableInsert" then
				local valueInsertedSignal = getCacheData(self, player).ValueInsertedSignals[concatedPath]
				if valueInsertedSignal then
					valueInsertedSignal:Fire(value, index or nil)
				end
			elseif action == "TableRemove" then
				local valueRemovedSignal = getCacheData(self, player).ValueRemovedSignals[concatedPath]
				if valueRemovedSignal then
					valueRemovedSignal:Fire(value, index)
				end
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._cache[player] = nil
	end)

	Replica.RequestData()
end

-- Returns the value from a player's profile data at the given path.
function PlayerDataManager.Get(self: PlayerDataManager, player: Player, path: { string }): any
	local pointer = getCacheData(self, player).Replica.Data

	for _, key in ipairs(path) do
		pointer = pointer[key]
	end

	return pointer
end
-- Returns a Signal that fires when the value at the given path is changed.
function PlayerDataManager.GetValueChangedSignal(
	self: PlayerDataManager,
	player: Player,
	path: { string }
): Signal.Signal<any, any>
	local playerCacheData = getCacheData(self, player)
	local concatedPath = table.concat(path, "/")

	local valueChangedSignal = playerCacheData.ValueChangedSignals[concatedPath]
	if valueChangedSignal then
		return valueChangedSignal
	else
		valueChangedSignal = Signal.new()
		playerCacheData.ValueChangedSignals[concatedPath] = valueChangedSignal

		playerCacheData.Replica:OnSet(path, function(newValue, oldValue)
			valueChangedSignal:Fire(newValue, oldValue)
		end)

		return valueChangedSignal
	end
end
-- Returns a Signal that fires when a value is inserted into the table at the given path.
function PlayerDataManager.GetValueInsertedSignal(self: PlayerDataManager, player: Player, path: { string })
	local playerCacheData = getCacheData(self, player)
	local concatedPath = table.concat(path, "/")

	local valueInsertedSignal = playerCacheData.ValueInsertedSignals[concatedPath]
	if valueInsertedSignal then
		return valueInsertedSignal
	else
		valueInsertedSignal = Signal.new()
		playerCacheData.ValueInsertedSignals[concatedPath] = valueInsertedSignal

		return valueInsertedSignal
	end
end
-- Returns a Signal that fires when a value is removed from the table at the given path.
function PlayerDataManager.GetValueRemovedSignal(self: PlayerDataManager, player: Player, path: { string })
	local playerCacheData = getCacheData(self, player)
	local concatedPath = table.concat(path, "/")

	local valueRemovedSignal = playerCacheData.ValueRemovedSignals[concatedPath]
	if valueRemovedSignal then
		return valueRemovedSignal
	else
		valueRemovedSignal = Signal.new()
		playerCacheData.ValueRemovedSignals[concatedPath] = valueRemovedSignal

		return valueRemovedSignal
	end
end

start(PlayerDataManager)

type PlayerDataManager = typeof(PlayerDataManager)

return PlayerDataManager :: PlayerDataManager
