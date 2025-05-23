local targets = {
	TIMER_SPLIT_FRAMES_DISPLAY = {}, -- Split data for displayed run
	TIMER_SPLIT_FRAMES_ACTIVE = {}, -- Split data for active run
	TIMER_SPLIT_FRAMES_PB = {}, -- Split data for PB run
	TIMER_FRAME_COUNT = 0, -- The current framecount of the game
	RUN_NUMBER = 0, -- What run number we are on
	RUN_ID_DISPLAY = nil, -- What run ID is currently being displayed
	RUN_ID_ACTIVE = nil, -- What the run ID is for the current, active, run
	RUN_IN_PROGRESS = false, -- True when in an active run
	RUN_RESULT = 0x0, -- Displayed result status
	CHARACTER_DATA = {},
	IN_DISPLAY_MENU = nil,
	DISPLAY_MODE = 0x4,
	BROKEN = 0,
	IGNORE_TARGET_RESET = false,
}

local log = require("log")
local memory = require("memory")
local melee = require("melee")
local lsqlite3 = require("lsqlite3")
local splits = require("splits")

local graphics = love.graphics

local FRAME_FONT = graphics.newFont("fonts/melee-bold.otf", 14)
local SPLIT_SEC = FRAME_FONT
local SPLIT_MS = graphics.newFont("fonts/melee-bold.otf", 9)
local TOTAL_SEC = graphics.newFont("fonts/melee-bold.otf", 32)
local TOTAL_MS = graphics.newFont("fonts/melee-bold.otf", 20)

local TARGET = graphics.newImage("textures/target.png")

local DPAD_GATE = graphics.newImage("textures/buttons/d-pad-gate-filled.png")

local L_PRESSED = graphics.newImage("textures/buttons/l-pressed.png")
local R_PRESSED = graphics.newImage("textures/buttons/r-pressed.png")

local RESULT_NONE		= 0x0	-- Set at the start
local RESULT_FAILURE	= 0x4	-- Fell off the stage
local RESULT_COMPLETE	= 0x6	-- Successfully hit all targets
local RESULT_LRAS		= 0x7	-- Quit using L+R+A+Start
local RESULT_RESET		= 0x8	-- Reset using Z

local RESULT_TEXT = {
	[RESULT_NONE] = "NO RESULT",
	[RESULT_FAILURE] = "FAILURE",
	[RESULT_COMPLETE] = "COMPLETE",
	[RESULT_LRAS] = "QUIT",
	[RESULT_RESET] = "RESET",
}

function targets.getResultText(result)
	return RESULT_TEXT[result] or "Unknown result"
end

local MODE_PREV = 0x0
local MODE_NEXT = 0x1
local MODE_PB = 0x2
local MODE_PREV_PB = 0x3
local MODE_LAST = 0x4
local MODE_LAST_COMPLETE = 0x5

local function getMeleeTimestamp(frame)
	--local minutes = 0
	local seconds = 0
	local decimal = math.floor((frame%60)*99/59)/100

	if frame >= 0 then
		seconds = math.floor(frame/60)
		--minutes = math.floor(seconds/60)
		--seconds = seconds % 60
		seconds = seconds + decimal
	else
		seconds = math.ceil(frame/60)
		--minutes = math.ceil(seconds/60)
		--seconds = seconds % 60
		seconds = seconds - (1-decimal)
	end

	return seconds
end

local timedb = lsqlite3.open(string.format("%s/time.db", love.filesystem.getSaveDirectory()))

timedb:exec([[CREATE TABLE IF NOT EXISTS runs (
	run			INTEGER PRIMARY KEY AUTOINCREMENT,
	character	INTEGER, -- character that was used
	tframe		INTEGER, -- #frames the timer spent active
	gframe		INTEGER, -- #frames in total (including before timer start)
	targets		INTEGER, -- #targets that were hit
	result		INTEGER	 -- result status at the end (complete, failure, retry, etc)
);]])

timedb:exec([[CREATE TABLE IF NOT EXISTS splits (
	run			INTEGER NOT NULL,   -- the RUN_ID that this split is tied to
	split_index	INTEGER NOT NULL,   -- the index of the split
	tframe		INTEGER,            -- #frames the timer spent to achieve this split
	gframe		INTEGER,            -- #frames in total spent to achieve this split (including before timer start)
	time		INTEGER,            -- #frames spent between last split and this split
	UNIQUE(run,split_index)         -- we should never have duplicate splits in a given run
);]])

function targets.getFrame()
	return memory.frame
end

local TIMER_START_FRAME = -124

function targets.getTimerFrame()
	return memory.frame+TIMER_START_FRAME
end

function targets.getCharacter()
	return memory.player[1].select.character
end

function targets.getActivePort()
	return memory.menu.player_one_port+1
end

function targets.isBTTMode()
	return memory.menu.major == MENU_TARGET_TEST
end

function targets.isInBTTMatch()
	return targets.isBTTMode() and memory.menu.minor == MENU_TARGET_TEST_INGAME
end

function targets.isInBTTCSS()
	return targets.isBTTMode() and memory.menu.minor == MENU_TARGET_TEST_CSS
end

function targets.isPaused()
	return memory.match.paused
end

function targets.updateCDATA(character, name, data)
	if not targets.CHARACTER_DATA[character] then
		targets.CHARACTER_DATA[character] = {}
	end
	targets.CHARACTER_DATA[character][name] = data
end

function targets.getCDATA(character, name)
	if targets.CHARACTER_DATA[character] then
		return targets.CHARACTER_DATA[character][name]
	end
end

function targets.updateCharRunNumber(character, id)
	local stmt = timedb:prepare("SELECT COUNT(*) FROM runs WHERE character=? AND run<=?")
	stmt:bind_values(character, id)
	stmt:step()
	targets.RUN_NUMBER = stmt[0] or 0
	stmt:finalize()
end

function targets.getBestTime(character)
	local stmt = timedb:prepare("SELECT tframe FROM runs WHERE character=? AND gframe IS NOT NULL AND result=6 ORDER BY gframe ASC LIMIT 1;")
	stmt:bind_values(character)

	stmt:step()
	targets.updateCDATA(character, "BestTime", stmt[0])

	stmt:finalize()
	return data
end

function targets.getLastRunID(character)
	local stmt = timedb:prepare("SELECT run FROM runs WHERE character=? ORDER BY run DESC LIMIT 1;")
	stmt:bind_values(character)
	stmt:step()
	local lid = stmt[0]
	stmt:finalize()
	return lid
end

function targets.getPrevCompletedRunID(character, id)
	local stmt = timedb:prepare("SELECT run FROM runs WHERE character=? AND result=6 AND run<? ORDER BY run DESC LIMIT 1;")
	stmt:bind_values(character, id)
	stmt:step()
	local lid = stmt[0]
	stmt:finalize()
	return lid
end

function targets.getPrevRunID(character, id)
	local stmt = timedb:prepare("SELECT run FROM runs WHERE character=? AND run<? ORDER BY run DESC LIMIT 1;")
	stmt:bind_values(character, id)
	stmt:step()
	local pid = stmt[0]
	stmt:finalize()
	return pid
end

function targets.getNextRunID(character, id)
	local stmt = timedb:prepare("SELECT run FROM runs WHERE character=? AND run>? ORDER BY run ASC LIMIT 1;")
	stmt:bind_values(character, id)
	stmt:step()
	local nid = stmt[0]
	stmt:finalize()
	return nid
end

function targets.getPersonalBestRunID(character)
	local stmt = timedb:prepare("SELECT run FROM runs WHERE character=? AND result=6 ORDER BY gframe LIMIT 1;")
	stmt:bind_values(character)
	stmt:step()
	local pbid = stmt[0]
	stmt:finalize()
	return pbid
end

function targets.getPreviousPersonalBestRunID(character, id)
	local stmt = timedb:prepare("SELECT run FROM runs WHERE character=? AND result=6 AND run<? ORDER BY gframe LIMIT 1;")
	stmt:bind_values(character, id)
	stmt:step()
	local pbid = stmt[0]
	stmt:finalize()
	return pbid
end

function targets.getRunData(runid)
	local data = {
		tframe = 0,
		broken = 0,
		splits = {},
	}

	if not runid then return data end

	local stmt = timedb:prepare([[
SELECT run, split_index, tframe
FROM splits
WHERE run = ?
ORDER BY split_index;]])
	stmt:bind_values(runid)

	for row in stmt:nrows() do
		data.splits[row.split_index] = row.tframe
		data.broken = row.target
		data.tframe = row.tframe
	end

	stmt:finalize()

	return data
end

function targets.getRunResult(runid)
	local stmt = timedb:prepare([[
SELECT result
FROM runs
WHERE run = ?;]])
	stmt:bind_values(runid)

	stmt:step()
	local result = stmt[0]
	stmt:finalize()

	return result or RESULT_NONE
end

function targets.displayReset()
	targets.TIMER_SPLIT_FRAMES_DISPLAY = {}
	targets.TIMER_SPLIT_FRAMES_ACTIVE = {}
	targets.TIMER_SPLIT_FRAMES_PB = {}
	targets.RUN_ID_DISPLAY = 0
	targets.RUN_ID_ACTIVE = 0
	targets.RUN_NUMBER = 0
end

function targets.displayRun(runid)
	targets.RUN_ID_DISPLAY = runid

	local data = targets.getRunData(runid)

	targets.TIMER_SPLIT_FRAMES_DISPLAY = data.splits
	targets.RUN_RESULT = targets.getRunResult(runid)

	if targets.RUN_ID_DISPLAY == targets.RUN_ID_ACTIVE then
		targets.BROKEN = 10 - memory.stage.targets
	else
		targets.BROKEN = data.broken
	end

	targets.TIMER_FRAME_COUNT = data.tframe
end

function targets.displayLastRun(character)
	local lastid = targets.getLastRunID(character)
	if not lastid then return end
	targets.displayRun(lastid)
	targets.updateCharRunNumber(character, lastid)
end

function targets.displayPrevRun(character)
	local previd = targets.getPrevRunID(character, targets.RUN_ID_DISPLAY)
	if not previd then return end
	targets.displayRun(previd)
	targets.updateCharRunNumber(character, previd)
end

function targets.displayPrevCompletedRun(character)
	local previd = targets.getPrevCompletedRunID(character, targets.RUN_ID_DISPLAY)
	if not previd then return end
	targets.displayRun(previd)
	targets.updateCharRunNumber(character, previd)
end

function targets.displayNextRun(character)
	local nextid = targets.getNextRunID(character, targets.RUN_ID_DISPLAY)
	if not nextid then return end
	targets.displayRun(nextid)
	targets.updateCharRunNumber(character, nextid)
end

function targets.displayPersonalBestRun(character)
	local pbid = targets.getPersonalBestRunID(character, targets.RUN_ID_DISPLAY)
	if not pbid then return end
	targets.displayRun(pbid)
	targets.updateCharRunNumber(character, pbid)
end

function targets.displayPreviousPersonalBestRun(character)
	local pbid = targets.getPreviousPersonalBestRunID(character, targets.RUN_ID_DISPLAY)
	if not pbid then return end
	targets.displayRun(pbid)
	targets.updateCharRunNumber(character, pbid)
end

function targets.loadPreviousPersonalBestRun(character)
	local pbid = targets.getPreviousPersonalBestRunID(character, targets.RUN_ID_DISPLAY)
	targets.TIMER_SPLIT_FRAMES_PB = targets.getRunData(pbid).splits
end

function targets.displayPossibleBestRun(character)
	local stmt = timedb:prepare([[
SELECT min(splits.time) as time
FROM runs
INNER JOIN splits on splits.run = runs.run
WHERE runs.character=? AND runs.result=6
GROUP BY splits.split_index
ORDER BY splits.split_index]])
	stmt:bind_values(character)

	targets.TIMER_SPLIT_FRAMES_DISPLAY = {}
	targets.RUN_NUMBER = 0

	local tframe = 0

	for row in stmt:nrows() do
		tframe = tframe + row.time
		table.insert(targets.TIMER_SPLIT_FRAMES_DISPLAY, tframe)
	end

	stmt:finalize()
end

function targets.getSumOfBest(character)
	local stmt = timedb:prepare([[
SELECT SUM(time) FROM (
	SELECT min(splits.time) AS time
	FROM runs
	INNER JOIN splits on splits.run = runs.run
	WHERE runs.character=? AND runs.result=6
	GROUP BY splits.split_index
	ORDER BY splits.split_index
)]])
	stmt:bind_values(character)

	stmt:step()
	targets.updateCDATA(character, "SumOfBestTime", stmt[0])

	stmt:finalize()
	return data
end

function targets.setDisplayMode(mode)
	targets.DISPLAY_MODE = mode
	targets.updateDisplayMode()
end

function targets.updateDisplayMode()
	local character = targets.getCharacter()
	local mode = targets.DISPLAY_MODE
	if mode == MODE_PREV then
		targets.displayPrevRun(character)
	elseif mode == MODE_NEXT then
		targets.displayNextRun(character)
	elseif mode == MODE_PB then
		targets.displayPersonalBestRun(character)
	elseif mode == MODE_PREV_PB then
		targets.displayPreviousPersonalBestRun(character)
	elseif mode == MODE_LAST then
		targets.displayLastRun(character)
	elseif mode == MODE_LAST_COMPLETE then
		targets.displayPrevCompletedRun(character)
	end
	targets.loadPreviousPersonalBestRun(character)
end

function targets.updateCharacterStats()
	local character = targets.getCharacter()
	targets.updateCharRunNumber(character)
	targets.getBestTime(character)
	--targets.getSumOfBest(character)
	targets.updateDisplayMode()
end

function targets.createRun()
	local character = targets.getCharacter()
	local stmt = timedb:prepare("INSERT INTO runs (character) VALUES (?);")
	stmt:bind_values(character)
	stmt:step()
	stmt:finalize()
	targets.RUN_ID_ACTIVE = timedb:last_insert_rowid()
	targets.RUN_ID_DISPLAY = targets.RUN_ID_ACTIVE
	targets.updateCharRunNumber(character, targets.RUN_ID_ACTIVE)
	return targets.RUN_ID_ACTIVE
end

function targets.saveSplit(split_index, frames)
	targets.newRun()
	targets.TIMER_SPLIT_FRAMES_ACTIVE[split_index] = frames
	local timespent = (targets.TIMER_SPLIT_FRAMES_ACTIVE[split_index] or 0) - (targets.TIMER_SPLIT_FRAMES_ACTIVE[split_index-1] or 0)
	local stmt = timedb:prepare("INSERT INTO splits (run, split_index, tframe, gframe, time) VALUES (?,?,?,?,?);")
	stmt:bind_values(targets.RUN_ID_ACTIVE, split_index, targets.getTimerFrame(), memory.frame, timespent)
	stmt:step()
	stmt:finalize()
	if split_index >= table.getn(splits) then
		-- We force the RESULT_COMPLETE here instead of a match.result hook.
		-- match.result gets called a frame after we hit the target, messing up our run time
		targets.endRun(RESULT_COMPLETE)
	end
end

function targets.saveResults(result)
	local stmt = timedb:prepare("UPDATE runs SET tframe=?, gframe=?, targets=?, result=? WHERE run=?;")
	stmt:bind_values(targets.getTimerFrame(), memory.frame, 10 - memory.stage.targets, result or memory.match.result, targets.RUN_ID_ACTIVE)
	stmt:step()
	stmt:finalize()
end

function targets.isValidRun()
	return targets.RUN_IN_PROGRESS
end

function targets.isDisplayingActiveRun()
	return targets.RUN_ID_ACTIVE == targets.RUN_ID_DISPLAY
end

function targets.newRun()
	if targets.isInBTTMatch() and not targets.isValidRun() then
		targets.setDisplayMode(MODE_LAST)
		log.info("Started run #%d at game frame %d", targets.createRun(), memory.frame)
		targets.IGNORE_TARGET_RESET = true
		targets.IN_DISPLAY_MENU = nil
		targets.RUN_IN_PROGRESS = true
		targets.TIMER_SPLIT_FRAMES_ACTIVE = {}
		targets.TIMER_FRAME_COUNT = 0
		targets.BROKEN = 10 - memory.stage.targets
		targets.RUN_RESULT = RESULT_NONE
	end
end

function targets.quit()
	targets.endRun(RESULT_LRAS)
end

function targets.endRun(result)
	if targets.isValidRun() then
		targets.saveResults(result)
		targets.RUN_ID_ACTIVE = nil
		targets.RUN_IN_PROGRESS = false
		targets.RUN_RESULT = result
		log.info("Ended run #%d at frame %d - time %02.02f", targets.RUN_ID_DISPLAY, targets.getTimerFrame(), getMeleeTimestamp(targets.getTimerFrame()))
		targets.updateCharacterStats()
	end
end

memory.hook("player.1.select.character", "Targets - Update Count", function(character)
	if targets.isInBTTCSS() then
		targets.displayReset()
		targets.setDisplayMode(MODE_LAST)
	end
end)

memory.hook("stage.id", "Targets - Start run on new stage", function(id)
	if targets.isInBTTMatch() and melee.isBTTStage(id) then
		-- This only happens when we first load into a stage
		targets.newRun()
	end
end)

memory.hook("match.result", "Targets - Check start of game", function(result)
	if result == RESULT_NONE then
		-- RESULT_NONE = new match is ready to begin (after a reset)
		targets.newRun()
	else
		-- End the run if something triggered the end of the match
		targets.endRun(result)
	end
end)

function targets.setupSplits()
	local port = targets.getActivePort()
	for index, split in pairs(splits) do
		memory.hook(split.attribute, split.description, function (value)
			local game_state = {
				xPos = memory.player[port].position_x,
				yPos = memory.player[port].position_y,
				xVelocity = memory.player[port].entity.self_induced_velocity_x,
				yVelocity = memory.player[port].entity.self_induced_velocity_y,
				actionState = memory.player[port].entity.action_state,
				targetsLeft = memory.stage.targets,
				isFastfalling = memory.player[port].entity.is_fastfalling,
			}
			if not targets.TIMER_SPLIT_FRAMES_ACTIVE[index] and split.condition(game_state) then
				local time = targets.getTimerFrame()
				log.debug("Split %d: %s", index, time)
                targets.saveSplit(index, time)
			end
		end)
	end
end

local MENU_BUTTONS = {
	[0x1] = MODE_PREV,	-- LEFT
	[0x2] = MODE_NEXT,	-- RIGHT
	[0x4] = MODE_PREV_PB,	-- DOWN
	[0x8] = MODE_PB,	-- UP
	[0x20] = MODE_LAST, -- RIGHT TRIGGER
	[0x40] = MODE_LAST_COMPLETE, -- LEFT TRIGGER
}

local MENU_TEXT = graphics.newImage("textures/buttons/labels.png")

local DPAD_TEXTURES = {
	[0x1] = graphics.newImage("textures/buttons/d-pad-pressed-left.png"),
	[0x2] = graphics.newImage("textures/buttons/d-pad-pressed-right.png"),
	[0x4] = graphics.newImage("textures/buttons/d-pad-pressed-down.png"),
	[0x8] = graphics.newImage("textures/buttons/d-pad-pressed-up.png"),
}

memory.hook("controller.*.buttons.pressed", "Targets - Mode Switcher", function(port, pressed)
	-- Only allow split traversal when we are paused or in the menus
	if not melee.isInMenus() and not targets.isPaused() then return end

	if targets.IN_DISPLAY_MENU and pressed == 0x0 then
		targets.setDisplayMode(targets.IN_DISPLAY_MENU)
		targets.IN_DISPLAY_MENU = nil
	else
		for but, mode in pairs(MENU_BUTTONS) do
			if bit.band(pressed, but) == but then
				targets.IN_DISPLAY_MENU = mode
				break
			end
		end
	end
end)

local greyscale = graphics.newShader[[
extern number percent;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
	vec4 pixel = Texel(texture, texture_coords);
	float grey = 0.36 * pixel.r + 0.41 * pixel.g + 0.23 * pixel.b;
	pixel.r = pixel.r * percent + grey * (1.0 - percent);
	pixel.g = pixel.g * percent + grey * (1.0 - percent);
	pixel.b = pixel.b * percent + grey * (1.0 - percent);
	pixel.a = pixel.a * color.a;
	return pixel;
}
]]

function targets.resizeWindow()
	love.window.setMode(320, 88 + 36 * table.getn(splits))
end

function targets.drawSplits()
	local port = targets.getActivePort()
	local character = targets.getCharacter()

	graphics.setColor(200, 200, 200, 100)
	melee.drawSeries(port, 8, 64, 0, 320, 320)
	graphics.setColor(255, 255, 255, 255)
	melee.drawStock(port, 320 - 24 - 8, 8, 0, 24, 24)

	local runnum = string.format("#%d", targets.RUN_NUMBER or 0)

	local x = 320 - 24 - 12 - FRAME_FONT:getWidth(runnum)

	graphics.setFont(FRAME_FONT)
	graphics.setColor(0, 0, 0, 255)
	graphics.print(runnum, x, 14)
	graphics.setColor(255, 255, 255, 255)
	graphics.print(runnum, x, 13)

	local activeRun = targets.isValidRun() and targets.isDisplayingActiveRun()

	local frame = activeRun and targets.getTimerFrame() or (targets.TIMER_FRAME_COUNT or 0)

	graphics.setFont(FRAME_FONT)
	graphics.setColor(0, 0, 0, 255)
	graphics.print(frame, 4, 5)
	graphics.setColor(255, 255, 255, 255)
	graphics.print(frame, 4, 4)

	local seconds = getMeleeTimestamp(frame)
	local secstr = string.format("%02.02f", seconds)

	local secw = TOTAL_SEC:getWidth(secstr)

	graphics.setFont(TOTAL_SEC)
	graphics.setColor(0, 0, 0, 255)
	graphics.print(secstr, 160 - secw/2, 5)
	graphics.setColor(255, 255, 255, 255)
	graphics.print(secstr, 160 - secw/2, 4)

	local current = table.getn(targets.TIMER_SPLIT_FRAMES_ACTIVE) + 1

	for i=1,table.getn(splits) do
		if activeRun and current == i then
			graphics.setColor(0, 100, 0, 150)
		elseif i%2 == 1 then
			graphics.setColor(100, 100, 100, 150)
		else
			graphics.setColor(50, 50, 50, 150)
		end
		graphics.rectangle("fill", 0, 4 + (36*i), 320, 32)

		local y = 14 + (36*i)
		local numstr = string.format("%2d", i)

		graphics.setFont(SPLIT_SEC)
		graphics.setColor(0, 0, 0, 255)
		graphics.print(splits[i].description, 8, y)
		graphics.setColor(255, 255, 255, 255)
		graphics.print(splits[i].description, 8, y-1)

		if current == i then
			greyscale:send("percent", 0.25)
		elseif i > current then
			greyscale:send("percent", 0)
		else
			greyscale:send("percent", 1)
		end

		local t
		if activeRun and current == i then
			t = targets.getTimerFrame()
		elseif targets.isDisplayingActiveRun() then
			t = targets.TIMER_SPLIT_FRAMES_ACTIVE[i]
		else
			t = targets.TIMER_SPLIT_FRAMES_DISPLAY[i]
		end

		if t then
			local seconds = getMeleeTimestamp(t)

			local secstr = string.format("%7.02f", seconds, ms)

			local secw = SPLIT_SEC:getWidth(secstr)

			graphics.setFont(SPLIT_SEC)
			graphics.setColor(0, 0, 0, 255)
			graphics.print(secstr, 320 - 8 - secw, y)
			graphics.setColor(255, 255, 255, 255)
			graphics.print(secstr, 320 - 8 - secw, y-1)

			if targets.TIMER_SPLIT_FRAMES_PB[i] then
				local bt = targets.TIMER_SPLIT_FRAMES_PB[i]
				local dt = t - bt

				local seconds = getMeleeTimestamp(dt)
				local secstr = string.format("%+2.02f", seconds)

				local bsecw = SPLIT_SEC:getWidth(secstr)

				graphics.setFont(SPLIT_SEC)
				graphics.setColor(0, 0, 0, 255)
				graphics.print(secstr, 320 - 8 - secw - 8 - bsecw, y)

				if dt > 0 then
					graphics.setColor(225, 0, 0, 255)
				elseif dt == 0 then
					graphics.setColor(155, 155, 155, 255)
				elseif dt < 0 then
					graphics.setColor(0, 155, 40, 255)
				end
				graphics.print(secstr, 320 - 8 - secw - 8 - bsecw, y-1)
			end
		elseif i < current then
			-- This will only happen if we launch the program mid BTT run
			local secstr = "- -"
			local secw = SPLIT_SEC:getWidth(secstr)
			graphics.setFont(SPLIT_SEC)
			graphics.setColor(0, 0, 0, 255)
			graphics.print(secstr, 320 - 8 - secw, y)
			graphics.setColor(155, 155, 155, 255)
			graphics.print(secstr, 320 - 8 - secw, y-1)
		end
	end

	local besttime = targets.getCDATA(character, "BestTime") or 0

	local seconds = getMeleeTimestamp(besttime)
	local secstr = string.format("Personal Best: %.02f", seconds)

	local windowHeight = love.graphics.getHeight()

	graphics.setFont(SPLIT_SEC)
	graphics.setColor(0, 0, 0, 255)
	graphics.print(secstr, 4, windowHeight - 24)
	graphics.setColor(255, 255, 255, 255)
	graphics.print(secstr, 4, windowHeight - 23)

	local resStr = string.format("Result: %s", targets.getResultText(targets.RUN_RESULT))

	graphics.setFont(SPLIT_SEC)
	graphics.setColor(0, 0, 0, 255)
	graphics.print(resStr, 4, windowHeight - 46)
	graphics.setColor(255, 255, 255, 255)
	graphics.print(resStr, 4, windowHeight - 45)

	if targets.IN_DISPLAY_MENU ~= nil then
		graphics.setColor(0, 0, 0, 200)
		graphics.rectangle("fill", 0, 0, 320, windowHeight)

		graphics.setColor(255, 255, 255, 255)

		local controller = memory.controller[port].buttons
		graphics.easyDraw(MENU_TEXT, 320/2, windowHeight/2, 0, 320, windowHeight, 0.5, 0.5)

		if bit.band(controller.pressed, 0x40) == 0x40 then
			graphics.easyDraw(L_PRESSED, 0, 0, 0, 160, windowHeight / 4)
		end
		if bit.band(controller.pressed, 0x20) == 0x20 then
			graphics.easyDraw(R_PRESSED, 160, 0, 0, 160, windowHeight / 4)
		end

		for mask, tex in pairs(DPAD_TEXTURES) do
			if bit.band(controller.pressed, mask) == mask then
				graphics.easyDraw(tex, 320/2, windowHeight/2, 0, 128, 128, 0.5, 0.5)
			end
		end
	end
end

return targets