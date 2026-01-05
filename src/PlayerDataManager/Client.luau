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

local function getReplica(self: PlayerDataManager, player: Player): typeof(Replica.New())
	local replica = self._cache[player].Replica

	if not replica and player ~= localPlayer then
		error(`No replica founded for player: {player.Name}`)
	else
		repeat
			task.wait(1)
			replica = self._cache[player].Replica
		until replica

		return replica
	end
end

local function start(self: PlayerDataManager): ()
	Replica.OnNew("PlayerData", function(replica)
		local player = replica.Tags.Player
		local playerCacheData: CacheData = {
			Replica = replica,
			ValueChangedSignals = {},
			ValueInsertedSignals = {},
			ValueRemovedSignals = {},
		}

		self._cache[player] = playerCacheData

		if player ~= localPlayer then
			self.PlayerAdded:Fire(player)
		end

		replica:OnChange(function(action, path, value, index)
			local concatedPath = table.concat(path, "/")

			if action == "TableInsert" then
				local valueInsertedSignal = self._cache[player].ValueInsertedSignals[concatedPath]
				if valueInsertedSignal then
					valueInsertedSignal:Fire(value, index or nil)
				end
			elseif action == "TableRemove" then
				local valueRemovedSignal = self._cache[player].ValueRemovedSignals[concatedPath]
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
	local pointer = getReplica(self, player).Data

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
	local concatedPath = table.concat(path, "/")

	local valueChangedSignal = self._cache[player].ValueChangedSignals[concatedPath]
	if valueChangedSignal then
		return valueChangedSignal
	else
		valueChangedSignal = Signal.new()
		self._cache[player].ValueChangedSignals[concatedPath] = valueChangedSignal

		getReplica(self, player):OnSet(path, function(newValue, oldValue)
			valueChangedSignal:Fire(newValue, oldValue)
		end)

		return valueChangedSignal
	end
end
-- Returns a Signal that fires when a value is inserted into the table at the given path.
function PlayerDataManager.GetValueInsertedSignal(self: PlayerDataManager, player: Player, path: { string })
	local concatedPath = table.concat(path, "/")

	local valueInsertedSignal = self._cache[player].ValueInsertedSignals[concatedPath]
	if valueInsertedSignal then
		return valueInsertedSignal
	else
		valueInsertedSignal = Signal.new()
		self._cache[player].ValueInsertedSignals[concatedPath] = valueInsertedSignal

		return valueInsertedSignal
	end
end
-- Returns a Signal that fires when a value is removed from the table at the given path.
function PlayerDataManager.GetValueRemovedSignal(self: PlayerDataManager, player: Player, path: { string })
	local concatedPath = table.concat(path, "/")

	local valueRemovedSignal = self._cache[player].ValueRemovedSignals[concatedPath]
	if valueRemovedSignal then
		return valueRemovedSignal
	else
		valueRemovedSignal = Signal.new()
		self._cache[player].ValueRemovedSignals[concatedPath] = valueRemovedSignal

		return valueRemovedSignal
	end
end

start(PlayerDataManager)

type PlayerDataManager = typeof(PlayerDataManager)

return PlayerDataManager :: PlayerDataManager
