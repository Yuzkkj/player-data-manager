local Players = game:GetService("Players")

local Replica = require(script.Parent.Shared.Replica)
local Signal = require(script.Parent.Shared.Signal)

local localPlayer = Players.LocalPlayer

local PlayerDataManager = {
	PlayerAdded = Signal.new() :: Signal.Signal<Player>,
	_replicas = {} :: { [Player]: typeof(Replica.New()) },
	_valueChangedSignals = {} :: { [Player]: { [string]: Signal.Signal<any, any> } },
	_valueInsertedSignals = {} :: { [Player]: { [string]: Signal.Signal<any, any?> } },
	_valueRemovedSignals = {} :: { [Player]: { [string]: Signal.Signal<any, any> } },
}

local function getReplica(self: PlayerDataManager, player: Player): typeof(Replica.New())
	local replica = self._replicas[player]

	if not replica and player ~= localPlayer then
		error(`No replica founded for player: {player.Name}`)
	else
		repeat
			task.wait(1)
			replica = self._replicas[player]
		until replica

		return replica
	end
end

local function start(self: PlayerDataManager): ()
	Replica.OnNew("PlayerData", function(replica)
		local player = replica.Tags.Player
		self._replicas[player] = replica

		local valueChangedSignals = self._valueChangedSignals[player]
		if valueChangedSignals then
			for concatedPath, valueChangedSignal in pairs(valueChangedSignals) do
				local path = string.split(concatedPath, "/")
				replica:OnSet(path, function(newValue, oldValue)
					valueChangedSignal:Fire(newValue, oldValue)
				end)
			end
		end

		if player ~= localPlayer then
			self.PlayerAdded:Fire(player)
		end

		replica:OnChange(function(action, path, value, index)
			local concatedPath = table.concat(path, "/")

			if action == "TableInsert" then
				local valueInsertedSignal = self._valueInsertedSignals[player]
					and self._valueInsertedSignals[player][concatedPath]
				if valueInsertedSignal then
					valueInsertedSignal:Fire(value, index or nil)
				end
			elseif action == "TableRemove" then
				local valueRemovedSignal = self._valueRemovedSignals[player]
					and self._valueRemovedSignals[player][concatedPath]
				if valueRemovedSignal then
					valueRemovedSignal:Fire(value, index)
				end
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._replicas[player] = nil
		self._valueChangedSignals[player] = nil
		self._valueInsertedSignals[player] = nil
		self._valueRemovedSignals[player] = nil
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
	local targetPlayer = player or localPlayer
	local concatedPath = table.concat(path, "/")

	local playerSignals = self._valueChangedSignals[targetPlayer]
	if not playerSignals then
		playerSignals = {}
		self._valueChangedSignals[targetPlayer] = playerSignals
	end

	local valueChangedSignal = playerSignals[concatedPath]
	if valueChangedSignal then
		return valueChangedSignal
	else
		valueChangedSignal = Signal.new()
		playerSignals[concatedPath] = valueChangedSignal

		local replica = self._replicas[targetPlayer]
		if replica then
			replica:OnSet(path, function(newValue, oldValue)
				valueChangedSignal:Fire(newValue, oldValue)
			end)
		end

		return valueChangedSignal
	end
end
-- Returns a Signal that fires when a value is inserted into the table at the given path.
function PlayerDataManager.GetValueInsertedSignal(self: PlayerDataManager, player: Player, path: { string })
	local targetPlayer = player or localPlayer
	local concatedPath = table.concat(path, "/")

	local playerSignals = self._valueInsertedSignals[targetPlayer]
	if not playerSignals then
		playerSignals = {}
		self._valueInsertedSignals[targetPlayer] = playerSignals
	end

	local valueInsertedSignal = playerSignals[concatedPath]
	if valueInsertedSignal then
		return valueInsertedSignal
	else
		valueInsertedSignal = Signal.new()
		playerSignals[concatedPath] = valueInsertedSignal

		return valueInsertedSignal
	end
end
-- Returns a Signal that fires when a value is removed from the table at the given path.
function PlayerDataManager.GetValueRemovedSignal(self: PlayerDataManager, player: Player, path: { string })
	local targetPlayer = player or localPlayer
	local concatedPath = table.concat(path, "/")

	local playerSignals = self._valueRemovedSignals[targetPlayer]
	if not playerSignals then
		playerSignals = {}
		self._valueRemovedSignals[targetPlayer] = playerSignals
	end

	local valueRemovedSignal = playerSignals[concatedPath]
	if valueRemovedSignal then
		return valueRemovedSignal
	else
		valueRemovedSignal = Signal.new()
		playerSignals[concatedPath] = valueRemovedSignal

		return valueRemovedSignal
	end
end

start(PlayerDataManager)

type PlayerDataManager = typeof(PlayerDataManager)

return PlayerDataManager :: PlayerDataManager
