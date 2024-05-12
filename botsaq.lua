-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.
Logs = Logs or {}

colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

function addLog(msg, text)
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

function findWeakerOpponents()
    local me = LatestGameState.Players[ao.id]
    local weakerOpponents = {}

    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id and state.energy < me.energy then
            table.insert(weakerOpponents, {
                id = target,
                x = state.x,
                y = state.y,
                energy = state.energy
            })
        end
    end

    return weakerOpponents
end

function findStrongerOpponents()
    local me = LatestGameState.Players[ao.id]
    local strongerOpponents = {}

    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id and state.energy > me.energy then
            table.insert(strongerOpponents, {
                id = target,
                x = state.x,
                y = state.y,
                energy = state.energy
            })
        end
    end

    return strongerOpponents
end

function findApproachDirection()
    local me = LatestGameState.Players[ao.id]
    local approachDirection = { x = 0, y = 0 }

    local weakerOpponents = findWeakerOpponents()
    if #weakerOpponents > 0 then
        local target = weakerOpponents[1]
        local approachVector = { x = target.x - me.x, y = target.y - me.y }
        approachDirection.x = approachVector.x
        approachDirection.y = approachVector.y
    end

    return approachDirection
end

function findAvoidDirection()
    local me = LatestGameState.Players[ao.id]
    local avoidDirection = { x = 0, y = 0 }

    local strongerOpponents = findStrongerOpponents()
    if #strongerOpponents > 0 then
        for _, opponent in ipairs(strongerOpponents) do
            local avoidVector = { x = me.x - opponent.x, y = me.y - opponent.y }
            avoidDirection.x = avoidDirection.x + avoidVector.x
            avoidDirection.y = avoidDirection.y + avoidVector.y
        end
    end

    return avoidDirection
end

function isPlayerInAttackRange(player)
    local me = LatestGameState.Players[ao.id]
    return math.abs(me.x - player.x) <= 1 and math.abs(me.y - player.y) <= 1
end

function decideNextAction()
    local me = LatestGameState.Players[ao.id]
    local approachDirection = findApproachDirection()
    local avoidDirection = findAvoidDirection()

    if #findWeakerOpponents() > 0 then
        -- Attack weaker opponents with 30% energy
        local target = findWeakerOpponents()[1]
        print(colors.red .. "Attacking weaker opponent with ID: " .. target.id .. " with 30% energy." .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, TargetPlayer = target.id, AttackEnergy = tostring(math.floor(me.energy * 0.3)) })
    else
        -- Get away from stronger opponents
        print(colors.blue .. "Getting away from stronger opponents." .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = avoidDirection })
    end

    InAction = false
end

-- Handler to update the game state upon receiving game state information.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
    end
)

-- Handler to decide the next best action.
Handlers.add(
    "decideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        if LatestGameState.GameMode ~= "Playing" then
            print("Game not started.")
            InAction = false
            return
        end
        print("Deciding next action.")
        decideNextAction()
        ao.send({ Target = ao.id, Action = "Tick" })
    end
)

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        if msg.Event == "Started-Waiting-Period" then
            ao.send({ Target = ao.id, Action = "AutoPay" })
        elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
            InAction = true
            ao.send({ Target = Game, Action = "GetGameState" })
        elseif InAction then
            print("Previous action still in progress. Skipping.")
        end
        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Handler to trigger game state updates.
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        if not InAction then
            InAction = true
            print(colors.gray .. "Getting game state..." .. colors.reset)
            ao.send({ Target = Game, Action = "GetGameState" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
    "AutoPay",
    Handlers.utils.hasMatchingTag("Action", "AutoPay"),
    function(msg)
        print("Auto-paying confirmation fees.")
        ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
    end
)
