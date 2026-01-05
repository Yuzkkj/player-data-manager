PlayerDataManager handles data saving and replication.
# Basic example
## Server-side
```luau
local PlayerDataManager = require(game.ReplicatedStorage.Packages.PlayerDataManager)

PlayerDataManager:SetTemplate({
    Coins = 0,
})

game.Players.PlayerAdded:Connect(function(player)
    task.spawn(function()
        while true do
            PlayerDataManager:Increment(player, { "Coins" }, math.random(5, 10))
            task.wait(1)
        end
    end)
end)
```
## Client-side
```luau
local PlayerDataManager = require(game.ReplicatedStorage.Packages.PlayerDataManager)
local player = game.Players.LocalPlayer

PlayerDataManager:GetValueChangedSignal(player, { "Coins" }):Connect(function(newValue, oldValue)
    print(`You got {newValue - oldValue} coins!`)
end)
```