local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ProfileStore = require(script.Parent.Shared.ProfileStore)

local Replica = require(script.Parent.Shared.Replica)
local Signal = require(script.Parent.Shared.Signal)

local TOKEN = Replica.Token("PlayerData")

local playerStore: typeof(ProfileStore.New(...))

type CacheData = {
	Profile: ProfileStore.Profile<any>,
	Replica: typeof(Replica.New()),
	ValueChangedSignals: { [string]: Signal.Signal<any, any>? },
	ValueInsertedSignals: { [string]: Signal.Signal<any, any?>? },
	ValueRemovedSignals: { [string]: Signal.Signal<any, any>? },
}

local PlayerDataManager = {
	PlayerAdded = Signal.new() :: Signal.Signal<Player>,
	_dataStoreKey = "PlayerStore",
	_template = nil,
	_cache = {} :: { [Player]: CacheData },
}

local function removeData(self: PlayerDataManager, player: Player): ()
	local playerCacheData = self._cache[player]
	if not playerCacheData then
		return
	end

	local playerReplica = playerCacheData.Replica
	if playerReplica then
		playerReplica:Destroy()
	end

	self._cache[player] = nil

	player:Kick("Profile session ended. Please rejoin")
end

local function getCacheData(self: PlayerDataManager, player: Player): CacheData
	local cacheData = self._cache[player]
	if not cacheData then
		error(`No cache data founded for player {player.Name}`)
	end

	return cacheData
end

local function start(self: PlayerDataManager): ()
	playerStore = ProfileStore.New(self._dataStoreKey, self._template)

	local function onPlayerAdded(player: Player): ()
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

		local playerReplica = Replica.New({
			Token = TOKEN,
			Data = playerProfile.Data,
			Tags = { Player = player },
		})

		playerReplica:Replicate()

		self._cache[player] = {
			Profile = playerProfile,
			Replica = playerReplica,
			ValueChangedSignals = {},
			ValueInsertedSignals = {},
			ValueRemovedSignals = {},
		}

		self.PlayerAdded:Fire(player)
	end

	for _, player in pairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)

	if RunService:IsStudio() then
		return
	end

	game:BindToClose(function()
		for _, player in pairs(Players:GetPlayers()) do
			getCacheData(self, player).Profile:EndSession()
		end
	end)
end
-- Sets the default data structure used when creating a profile.
function PlayerDataManager.SetTemplate(self: PlayerDataManager, template: { [any]: any }): ()
	if type(template) ~= "table" then
		error("Template must be a table")
	end

	self._template = template
	start(self)
end
-- Sets the Data Store key used for saving and loading player profile data.
function PlayerDataManager.SetDataStoreKey(self: PlayerDataManager, key: string): ()
	self._dataStoreKey = key
end
-- Returns the value from a player's profile data at the given path.
function PlayerDataManager.Get(self: PlayerDataManager, player: Player, path: { string }): any
	local pointer = getCacheData(self, player).Profile.Data
	for _, key in ipairs(path) do
		pointer = pointer[key]
	end

	return pointer
end
-- Sets the value in a player's profile data at the given path.
function PlayerDataManager.Set(self: PlayerDataManager, player: Player, path: { string }, value: any): ()
	local playerCacheData = getCacheData(self, player)
	local concatedPath = table.concat(path, "/")

	local oldValue = self:Get(player, path)
	if not oldValue then
		error(`No value found in path "{concatedPath}"`)
	end

	local pointer = playerCacheData.Profile.Data
	for i = 1, #path - 1 do
		pointer = pointer[path[i]]
	end

	pointer[path[#path]] = value
	playerCacheData.Replica:Set(path, value)

	local valueChangedSignal = playerCacheData.ValueChangedSignals[concatedPath]
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
	local playerCacheData = getCacheData(self, player)
	local concatedPath = table.concat(path, "/")

	local valueChangedSignal = playerCacheData.ValueChangedSignals[concatedPath]
	if valueChangedSignal then
		return valueChangedSignal
	else
		valueChangedSignal = Signal.new()

		playerCacheData.ValueChangedSignals[concatedPath] = valueChangedSignal

		return valueChangedSignal
	end
end
-- Inserts the given value into a player's profile table at the given path, and index, if provided.
function PlayerDataManager.Insert(
	self: PlayerDataManager,
	player: Player,
	path: { string },
	value: any,
	index: number?
): ()
	local playerCacheData = getCacheData(self, player)
	local pointer = playerCacheData.Profile.Data
	for _, key in ipairs(path) do
		pointer = pointer[key]
	end

	if index then
		table.insert(pointer, index, value)
	else
		table.insert(pointer, value)
	end

	playerCacheData.Replica:TableInsert(path, value, index or nil)

	local concatedPath = table.concat(path, "/")
	local valueInsertedSignal = playerCacheData.ValueInsertedSignals[concatedPath]
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
-- Removes an element from a table at the given path by index.
function PlayerDataManager.Remove(self: PlayerDataManager, player: Player, path: { string }, index: number): ()
	local playerCacheData = getCacheData(self, player)
	local pointer = playerCacheData.Profile.Data
	for _, key in ipairs(path) do
		pointer = pointer[key]
	end

	local concatedPath = table.concat(path, "/")

	local valueRemoved = table.remove(pointer, index)
	if not valueRemoved then
		error(`No index "{index}" at path "{concatedPath}"`)
	end

	playerCacheData.Replica:TableRemove(path, index)

	local valueRemovedSignal = playerCacheData.ValueRemovedSignals[concatedPath]
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
-- Increment the value at the given path, by the given amount.
function PlayerDataManager.Increment(self: PlayerDataManager, player: Player, path: { string }, increment: number): ()
	local oldValue = self:Get(player, path)
	local newValue = oldValue + increment

	self:Set(player, path, newValue)
end

type PlayerDataManager = typeof(PlayerDataManager)

return PlayerDataManager :: PlayerDataManager
