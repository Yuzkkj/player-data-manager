local Players = game:GetService("Players")

local Promise = require(script.Parent.Shared.Promise)
local Replica = require(script.Parent.Shared.Replica)
local Signal = require(script.Parent.Shared.Signal)

local dataLoaded = Signal.new() :: Signal.Signal<Player>

type CacheData = {
	Replica: typeof(Replica.New()),
	ValueChangedSignals: { [string]: Signal.Signal<any, any>? },
	ValueInsertedSignals: { [string]: Signal.Signal<any, any?>? },
	ValueRemovedSignals: { [string]: Signal.Signal<any, any>? },
}

local PlayerDataManager = {
	_cache = {} :: { [Player]: CacheData },
}

local function getCacheData(self: PlayerDataManager, player: Player): CacheData
	local playerCacheData = self._cache[player]
	if playerCacheData then
		return playerCacheData
	else
		Promise.new(function(resolve, _, onCancel)
			local connection: Signal.Connection
			connection = dataLoaded:Connect(function(loadedPlayer)
				if loadedPlayer == player then
					connection:Disconnect()
					resolve(self._cache[player])
				end
			end)

			onCancel(function()
				if connection then
					connection:Disconnect()
				end
			end)
		end)
			:timeout(10)
			:andThen(function(cacheData)
				playerCacheData = cacheData
			end)
			:catch(function(err)
				if Promise.Error.isKind(err, Promise.Error.Kind.TimedOut) then
					warn("Operation timed out")
				else
					warn("Operation encountered an error")
				end
			end)

		return playerCacheData
	end
end

local function start(self: PlayerDataManager): ()
	local function setupReplica(replica)
		local player = replica.Tags.Player
		self._cache[player] = {
			Replica = replica,
			ValueChangedSignals = {},
			ValueInsertedSignals = {},
			ValueRemovedSignals = {},
		}

		dataLoaded:Fire(player)

		replica:OnChange(function(action, path, value, index)
			local concatedPath = table.concat(path, "/")
			local playerCacheData = getCacheData(self, player)

			if action == "TableInsert" then
				local valueInsertedSignal = playerCacheData.ValueInsertedSignals[concatedPath]
				if valueInsertedSignal then
					valueInsertedSignal:Fire(value, index or nil)
				end
			elseif action == "TableRemove" then
				local valueRemovedSignal = playerCacheData.ValueRemovedSignals[concatedPath]
				if valueRemovedSignal then
					valueRemovedSignal:Fire(value, index)
				end
			end
		end)
	end

	local activeReplicas = Replica.Test().TokenReplicas["PlayerData"]
	if activeReplicas then
		for replica, _ in pairs(activeReplicas) do
			setupReplica(replica)
		end
	end

	Replica.OnNew("PlayerData", setupReplica)

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
