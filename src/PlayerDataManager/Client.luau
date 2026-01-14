local Players = game:GetService("Players")

local Promise = require(script.Parent.Shared.Promise)
local Replica = require(script.Parent.Shared.Replica)
local Signal = require(script.Parent.Shared.Signal)
local Janitor = require(script.Parent.Shared.Janitor)

local Types = require(script.Parent.Shared.Types)
local utils = require(script.Parent.Shared.Utils)

local dataLoaded = Signal.new() :: Signal.Signal<Player>

type CacheData = {
	_janitor: Janitor.Janitor,
	Replica: typeof(Replica.New()),
	ValueChangedSignals: Types.ValueChangedSignals,
	ValueInsertedSignals: Types.ValueInsertedSignals,
	ValueRemovedSignals: Types.ValueRemovedSignals,
}

local PlayerDataManager = {
	_cache = {} :: { [Player]: CacheData },
}

local function getCacheData(self: PlayerDataManager, player: Player): CacheData?
	if self._cache[player] then
		return self._cache[player]
	end

	local dataPromise = Promise.new(function(resolve, _, onCancel)
		local connection
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

	local success, result = dataPromise:timeout(15):await()

	if success then
		return result
	else
		warn(`Failed to get {player.Name} cache data: {result}`)
		return nil
	end
end

local function start(self: PlayerDataManager): ()
	local function setupReplica(replica)
		local player = replica.Tags.Player
		if not player then
			return
		end

		self._cache[player] = {
			_janitor = Janitor.new(),
			Replica = replica,
			ValueChangedSignals = {},
			ValueInsertedSignals = {},
			ValueRemovedSignals = {},
		}

		dataLoaded:Fire(player)

		replica:OnChange(function(action, path, value, index)
			local playerCacheData = getCacheData(self, player)
			if not playerCacheData then
				return
			end

			if action == "Set" then
				local signal: Types.ValueChangedSignal = utils.getSignalNode(playerCacheData.ValueChangedSignals, path)
				if signal then
					signal:Fire(value, index)
				end
			elseif action == "TableInsert" then
				local signal: Types.ValueInsertedSignal =
					utils.getSignalNode(playerCacheData.ValueInsertedSignals, path)
				if signal then
					signal:Fire(value, index or nil)
				end

				local signalTable = utils.getSignalNode(playerCacheData.ValueChangedSignals, path)
				if signalTable then
					if index then
						table.insert(signalTable, index, false)
					else
						table.insert(signalTable, false)
					end
				end
			elseif action == "TableRemove" then
				local signal: Types.ValueRemovedSignal = utils.getSignalNode(playerCacheData.ValueChangedSignals, path)
				if signal then
					signal:Fire(value, index)
				end

				local signalTable = utils.getSignalNode(playerCacheData.ValueChangedSignals, path)
				if signalTable then
					table.remove(signalTable, index)
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
		local playerCacheData = self._cache[player]
		if not playerCacheData then
			return
		end

		local janitor = playerCacheData._janitor
		if janitor then
			janitor:Destroy()
			playerCacheData._janitor = nil
		end

		self._cache[player] = nil
	end)

	Replica.RequestData()
end

-- Returns the value from a player's profile data at the given path.
function PlayerDataManager.Get(self: PlayerDataManager, player: Player, path: { string | number }): any
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
	path: { string | number }
): Types.ValueChangedSignal
	local playerCacheData = getCacheData(self, player)

	local pointer, key = utils.CreateSignalNode(playerCacheData.ValueChangedSignals, path)

	local valueChangedSignal = pointer[key]
	if valueChangedSignal then
		return valueChangedSignal
	else
		valueChangedSignal = Signal.new()
		playerCacheData._janitor:Add(valueChangedSignal, "DisconnectAll")

		pointer[key] = valueChangedSignal

		return valueChangedSignal
	end
end
-- Returns a Signal that fires when a value is inserted into the table at the given path.
function PlayerDataManager.GetValueInsertedSignal(
	self: PlayerDataManager,
	player: Player,
	path: { string | number }
): Types.ValueInsertedSignal
	local playerCacheData = getCacheData(self, player)

	local pointer, key = utils.CreateSignalNode(playerCacheData.ValueInsertedSignals, path)

	local valueInsertedSignal = pointer[key]
	if valueInsertedSignal then
		return valueInsertedSignal
	else
		valueInsertedSignal = Signal.new()
		playerCacheData._janitor:Add(valueInsertedSignal, "DisconnectAll")

		pointer[key] = valueInsertedSignal

		return valueInsertedSignal
	end
end
-- Returns a Signal that fires when a value is removed from the table at the given path.
function PlayerDataManager.GetValueRemovedSignal(
	self: PlayerDataManager,
	player: Player,
	path: { string | number }
): Types.ValueRemovedSignal
	local playerCacheData = getCacheData(self, player)

	local pointer, key = utils.CreateSignalNode(playerCacheData.ValueRemovedSignals, path)

	local valueRemovedSignal = pointer[key]
	if valueRemovedSignal then
		return valueRemovedSignal
	else
		valueRemovedSignal = Signal.new()
		playerCacheData._janitor:Add(valueRemovedSignal, "DisconnectAll")

		pointer[key] = valueRemovedSignal

		return valueRemovedSignal
	end
end

start(PlayerDataManager)

type PlayerDataManager = typeof(PlayerDataManager)

return PlayerDataManager :: PlayerDataManager
