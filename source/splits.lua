local ACTION_STATES = {
    JUMP_SQUAT = 0x18,
    DOUBLE_JUMP = 0x1B,
    FIREBALL_LAND = 0x157,
    FIREBALL = 0x158,
}

return {
    {
        attribute = "player.1.entity.action_state",
        description = "Jump squat",
        condition = function (state)
            return state.actionState == ACTION_STATES.JUMP_SQUAT and math.abs(state.yPos - -20) < 1
        end,
    },
    {
        attribute = "player.1.entity.action_state",
        description = "Elevator 1 jump squat",
        condition = function (state)
            return state.actionState == ACTION_STATES.JUMP_SQUAT and math.abs(state.xPos - -77) < 11 and math.abs(state.yPos - 28) < 12
        end,
    },
    {
        attribute = "player.1.entity.action_state",
        description = "Elevator 2 jump squat",
        condition = function (state)
            return state.actionState == ACTION_STATES.JUMP_SQUAT and math.abs(state.xPos - -77) < 11 and math.abs(state.yPos - 63) < 15
        end,
    },
    {
        attribute = "player.1.entity.action_state",
        description = "DJ",
        condition = function (state)
            return state.actionState == ACTION_STATES.DOUBLE_JUMP and math.abs(state.xPos - -77) < 11 and state.yPos > 70
        end,
    },
    {
        attribute = "player.1.entity.action_state",
        description = "Fireball T7",
        condition = function (state)
            return state.actionState == ACTION_STATES.FIREBALL and math.abs(state.xPos - -75) < 13 and state.yPos > 80
        end,
    },
    {
        attribute = "player.1.entity.action_state",
        description = "Fireball T8",
        condition = function (state)
            return state.actionState == ACTION_STATES.FIREBALL and math.abs(state.xPos - -75) < 13 and math.abs(state.yPos - 72) < 10
        end,
    },
    {
        attribute = "player.1.entity.action_state",
        description = "Land",
        condition = function (state)
            return state.actionState == ACTION_STATES.FIREBALL_LAND and math.abs(state.xPos - -75) < 13
        end,
    },
    {
        attribute = "player.1.entity.action_state",
        description = "Slipoff",
        condition = function (state)
            return state.actionState == ACTION_STATES.FIREBALL and math.abs(state.xPos - -75) < 13 and math.abs(state.yPos - 37) < 15
        end,
    },
    {
        attribute = "player.1.entity.self_induced_velocity_y",
        description = "Fastfall",
        condition = function (state)
            return math.abs(state.yVelocity - -2.3) < 0.1 and math.abs(state.xPos - -75) < 13 and math.abs(state.yPos - 34) < 15
        end,
    },
    {
        attribute = "stage.targets",
        description = "T9",
        condition = function (state)
            return state.targetsLeft == 1
        end,
    },
    {
        attribute = "stage.targets",
        description = "T10",
        condition = function (state)
            return state.targetsLeft == 0
        end,
    },
}