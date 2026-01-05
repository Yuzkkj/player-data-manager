local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ProfileStore = require(script.Parent.Shared.ProfileStore)

local Replica = require(script.Parent.Shared.Replica)
local Signal = require(script.Parent.Shared.Signal)

local TOKEN = Replica.Token("PlayerData")

local playerStore: typeof(ProfileStore.New(...))

local PlayerDataManager = {
	PlayerAdded = Signal.new() :: Signal.Signal<Player>,
	_dataStoreKey = "PlayerStore",
	_template = nil,
	_profiles = {} :: { [Player]: ProfileStore.Profile<any> },
	_replicas = {} :: { [Player]: typeof(Replica.New()) },
	_valueChangedSignals = {} :: { [Player]: { [string]: Signal.Signal<any, any> } },
	_valueInsertedSignals = {} :: { [Player]: { [string]: Signal.Signal<any, any?> } },
	_valueRemovedSignals = {} :: { [Player]: { [string]: Signal.Signal<any, any> } },
}

local function removeData(self: PlayerDataManager, player: Player): ()
	self._profiles[player] = nil

	local playerReplica = self._replicas[player]
	if playerReplica then
		playerReplica:Destroy()
		self._replicas[player] = nil
	end

	self._valueChangedSignals[player] = nil
	self._valueInsertedSignals[player] = nil
	self._valueRemovedSignals[player] = nil

	player:Kick("Profile session ended. Please rejoin")
end

local function getProfile(self: PlayerDataManager, player: Player): ProfileStore.Profile<any>
	local profile = self._profiles[player]
	if not profile then
		error(`No profile founded for player: {player.Name}`)
	end

	return profile
end

local function start(self: PlayerDataManager): ()
	playerStore = ProfileStore.New(self._dataStoreKey, self._template)

	local function onPlayerAdded(player: Player): ()
		self._valueChangedSignals[player] = {}
		self._valueInsertedSignals[player] = {}
		self._valueRemovedSignals[player] = {}

		local playerProfile = playerStore:StartSessionAsync(tostring(player.UserId), {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})

		if not playerProfile then
			player:Kick("Profile load failed. Please rejoin")
		end

		playerProfile:AddUserId(player.UserId)
		playerProfile:Reconcile()

		playerProfile.OnSessionEnd:Connect(function()
			removeData(self, player)
		end)

		if player.Parent ~= Players then
			playerProfile:EndSession()
		end

		self._profiles[player] = playerProfile

		local playerReplica = Replica.New({
			Token = TOKEN,
			Data = playerProfile.Data,
			Tags = { Player = player },
		})

		playerReplica:Replicate()

		self._replicas[player] = playerReplica

		self.PlayerAdded:Fire(player)
	end

	for _, player in pairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)

	if not RunService:IsStudio() then
		game:BindToClose(function()
			for _, player in pairs(Players:GetPlayers()) do
				local profile = getProfile(self, player)
				profile:EndSession()
			end
		end)
	end
end
-- Sets the default data structure used when creating a profile.
function PlayerDataManager.SetTemplate(self: PlayerDataManager, template: { [any]: any }): ()
	self._template = template
	start(self)
end
-- Sets the Data Store key used for saving and loading player profile data.
function PlayerDataManager.SetDataStoreKey(self: PlayerDataManager, key: string): ()
	self._dataStoreKey = key
end
-- Returns the value from a player's profile data at the given path.
function PlayerDataManager.Get(self: PlayerDataManager, player: Player, path: { string }): any
	local pointer = getProfile(self, player).Data
	for _, key in ipairs(path) do
		pointer = pointer[key]
	end

	return pointer
end
-- Sets the value in a player's profile data at the given path.
function PlayerDataManager.Set(self: PlayerDataManager, player: Player, path: { string }, value: any): ()
	local concatedPath = table.concat(path, "/")

	local oldValue = self:Get(player, path)
	if not oldValue then
		error(`No value found in path "{concatedPath}"`)
	end

	local pointer = getProfile(self, player).Data
	for i = 1, #path - 1 do
		pointer = pointer[path[i]]
	end

	local playerReplica = self._replicas[player]

	pointer[path[#path]] = value
	playerReplica:Set(path, value)

	local valueChangedSignal = self._valueChangedSignals[player][concatedPath]
	if valueChangedSignal then
		valueChangedSignal:Fire(value, oldValue)
	end
end
-- Returns a Signal that fires when the value at the given path is changed.
function PlayerDataManager.GetValueChangedSignal(
	self: PlayerDataManager,
	player: Player,
	path: { string }
): Signal.Signal<any, any>
	local concatedPath = table.concat(path, "/")

	local valueChangedSignal = self._valueChangedSignals[player][concatedPath]
	if valueChangedSignal then
		return valueChangedSignal
	else
		valueChangedSignal = Signal.new()

		self._valueChangedSignals[player][concatedPath] = valueChangedSignal

		return valueChangedSignal
	end
end
-- Inserts the given value into a player's profile table at the given path, at the index, if provided.
function PlayerDataManager.Insert(
	self: PlayerDataManager,
	player: Player,
	path: { string },
	value: any,
	index: number?
): ()
	local pointer = getProfile(self, player).Data
	for _, key in ipairs(path) do
		pointer = pointer[key]
	end

	local playerReplica = self._replicas[player]

	if index ~= nil then
		table.insert(pointer, index, value)
	else
		table.insert(pointer, value)
	end

	playerReplica:TableInsert(path, value, index or nil)

	local concatedPath = table.concat(path, "/")
	local valueInsertedSignal = self._valueInsertedSignals[player][concatedPath]
	if valueInsertedSignal then
		valueInsertedSignal:Fire(value, index or nil)
	end
end
-- Returns a Signal that fires when a value is inserted into the table at the given path.
function PlayerDataManager.GetValueInsertedSignal(
	self: PlayerDataManager,
	player: Player,
	path: { string }
): Signal.Signal<any, any?>
	local concatedPath = table.concat(path, "/")

	local valueInsertedSignal = self._valueInsertedSignals[player][concatedPath]
	if valueInsertedSignal then
		return valueInsertedSignal
	else
		valueInsertedSignal = Signal.new()

		self._valueInsertedSignals[player][concatedPath] = valueInsertedSignal

		return valueInsertedSignal
	end
end
-- Removes an element from a table at the given path by index.
function PlayerDataManager.Remove(self: PlayerDataManager, player: Player, path: { string }, index: number): ()
	local pointer = getProfile(self, player).Data
	for _, key in ipairs(path) do
		pointer = pointer[key]
	end

	local concatedPath = table.concat(path, "/")

	local valueRemoved = table.remove(pointer, index)
	if not valueRemoved then
		error(`No index "{index}" at path "{concatedPath}"`)
	end

	local playerReplica = self._replicas[player]

	playerReplica:TableRemove(path, index)

	local valueRemovedSignal = self._valueRemovedSignals[player][concatedPath]
	if valueRemovedSignal then
		valueRemovedSignal:Fire(valueRemoved, index)
	end
end
-- Returns a Signal that fires when a value is removed from the table at the given path.
function PlayerDataManager.GetValueRemovedSignal(
	self: PlayerDataManager,
	player: Player,
	path: { string }
): Signal.Signal<any, any>
	local concatedPath = table.concat(path, "/")

	local valueRemovedSignal = self._valueRemovedSignals[player][concatedPath]
	if valueRemovedSignal then
		return valueRemovedSignal
	else
		valueRemovedSignal = Signal.new()

		self._valueRemovedSignals[player][concatedPath] = valueRemovedSignal

		return valueRemovedSignal
	end
end
-- Increment the value at the given path, by the given amount.
function PlayerDataManager.Increment(self: PlayerDataManager, player: Player, path: { string }, increment: number): ()
	local oldValue = self:Get(player, path)
	local newValue = oldValue + increment

	self:Set(player, path, newValue)
end

type PlayerDataManager = typeof(PlayerDataManager)

return PlayerDataManager :: PlayerDataManager
