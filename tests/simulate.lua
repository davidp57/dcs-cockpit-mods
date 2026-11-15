-- Off-game check of the hook and of the cycles device, with plain Lua 5.1 and stubs for the
-- DCS functions they use. Run by tests/run.ps1, which assembles the cockpit folder.
--
-- Usage: lua tests/simulate.lua <cockpit folder> <AH-64D Cockpit/Scripts folder> [nolfs]
--   <cockpit folder>: holds COCKPIT_MODS/ and COCKPIT_CYCLES/ as installed in DCS.
--   nolfs: make lfs unavailable, as it may be in device_init.lua.

local cockpit, aircraft_scripts, mode = arg[1], arg[2], arg[3]
assert(cockpit and aircraft_scripts, "usage: lua simulate.lua <cockpit folder> <AH-64D scripts> [nolfs]")

local failures = 0
local function check(condition, message)
	if condition then
		print("ok   "..message)
	else
		failures = failures + 1
		print("FAIL "..message)
	end
end

local logged = {}
log = {INFO = "INFO", ERROR = "ERROR", write = function(source, level, message)
	logged[#logged + 1] = level.." "..source..": "..message
	print("     log "..level.." "..source..": "..message)
end}

LockOn_Options = {common_script_path = cockpit, script_path = aircraft_scripts}

-- 1. The hook, as run from device_init.lua.
if mode == "nolfs" then
	package.loaded.lfs = nil
	lfs = nil
	local real_require = require
	require = function(name)
		if name == "lfs" then error("module 'lfs' not found") end
		return real_require(name)
	end
end
creators = {}
dofile(cockpit.."COCKPIT_MODS/_loader.lua")
check(creators[251] ~= nil, "hook declared the cycles device 251")
check(creators[251] and creators[251][1] == "avLuaDevice", "device 251 is an avLuaDevice")
local listed_with_lfs = false
for _, line in ipairs(logged) do
	if line:find("folder listed with lfs", 1, true) then listed_with_lfs = true end
end
check(listed_with_lfs == (mode ~= "nolfs"), "lfs used only when available")

-- 2. The cycles device, with fake cockpit devices that record every press.
local pressed = {}
local fake_devices = {}
function GetDevice(id)
	if not fake_devices[id] then
		fake_devices[id] = {
			performClickableAction = function(self, command, value)
				pressed[#pressed + 1] = {device = id, command = command, value = value, method = "click"}
			end,
			SetCommand = function(self, command, value)
				pressed[#pressed + 1] = {device = id, command = command, value = value, method = "command"}
			end,
		}
	end
	return fake_devices[id]
end
local listened = {}
function GetSelf() return {listen_command = function(self, command) listened[command] = true end} end
local update_step
function make_default_activity(step) update_step = step end
local messages = {}
function print_message_to_user(text) messages[#messages + 1] = text end

dofile(creators[251][2])
post_initialize()
check(listened[3001] and listened[3101] and listened[3016] and listened[3116], "slots 1-16 down and up commands listened")
check(update_step and update_step > 0, "update step set")

local function tick(seconds)
	for _ = 1, math.floor(seconds / update_step + 0.5) do
		update()
	end
end

local function presses_down()
	local list = {}
	for _, p in ipairs(pressed) do
		if p.value == 1 then list[#list + 1] = p.command end
	end
	return list
end

-- Commands of the MPDs, from the aircraft's own files.
dofile(aircraft_scripts.."devices.lua")
dofile(aircraft_scripts.."command_defs.lua")
local FCR, WPN, TSD, VID = mpd_commands.FCR, mpd_commands.WPN, mpd_commands.TSD, mpd_commands.VID
-- ENG and ASE through the menu: M (B1), then B2 or L3.
local M, ENG, ASE = mpd_commands.B1, mpd_commands.B2, mpd_commands.L3

-- Slots of config/AH-64D.lua: 1-7 left MPD, 8-14 right MPD; in each, no hold, then hold
-- FCR, WPN, TSD, VID, ENG, ASE.
local LEFT, LEFT_HOLD_FCR, LEFT_HOLD_TSD, LEFT_HOLD_VID, LEFT_HOLD_ENG, LEFT_HOLD_ASE, RIGHT = 1, 2, 4, 5, 6, 7, 8

-- Each helper ends with time enough for a whole sequence and its releases.
local function short_press(slot)
	SetCommand(3000 + slot, 1); tick(0.1); SetCommand(3100 + slot, 1); tick(0.4)
end
local function long_press(slot)
	SetCommand(3000 + slot, 1); tick(0.7); SetCommand(3100 + slot, 1); tick(0.4)
end
local function same(seq, expected)
	if #seq ~= #expected then return false end
	for i = 1, #seq do if seq[i] ~= expected[i] then return false end end
	return true
end

-- Without a long press, the page changes as soon as the key is pressed.
SetCommand(3000 + LEFT, 1)
check(same(presses_down(), {FCR}), "no-hold command presses at once, before the release")
SetCommand(3100 + LEFT, 1); tick(0.4)
for _ = 1, 6 do short_press(LEFT) end
check(same(presses_down(), {FCR, WPN, TSD, VID, M, ENG, M, ASE, FCR}),
	"left MPD cycles FCR, WPN, TSD, VID, ENG (M, B2), ASE (M, L3), FCR")
check(pressed[1].device == devices.MFD_PLT_LEFT and pressed[1].method == "click", "presses go to the pilot's left MPD as clicks")
local downs, ups = 0, 0
for _, p in ipairs(pressed) do
	if p.value == 1 then downs = downs + 1 else ups = ups + 1 end
end
check(downs == ups, "each press is released")

-- A sequence: M pressed, released, then the page key, then released.
pressed = {}
long_press(LEFT_HOLD_ENG)
local order = {}
for _, p in ipairs(pressed) do order[#order + 1] = p.command..":"..p.value end
check(same(order, {M..":1", M..":0", ENG..":1", ENG..":0"}), "hold ENG: M pressed and released before B2")
short_press(LEFT)
check(same(presses_down(), {M, ENG, M, ASE}), "hold ENG, the cycle follows: next short press gives ASE")

pressed = {}
SetCommand(3000 + LEFT_HOLD_ASE, 1); tick(0.6) -- M at the long press (0.5 s)
check(same(presses_down(), {M}), "sequence: the page key waits sequence_step after M")
tick(0.2)                                      -- page key at 0.7 s
check(same(presses_down(), {M, ASE}), "sequence: the page key goes after sequence_step")
SetCommand(3100 + LEFT_HOLD_ASE, 1); tick(0.4)
short_press(LEFT)
check(same(presses_down(), {M, ASE, FCR}), "hold ASE, the cycle follows: next short press gives FCR")

-- A new step on the same MPD waits for the end of a sequence: a second M on the open menu
-- would give DMS.
short_press(LEFT); short_press(LEFT); short_press(LEFT) -- WPN, TSD, VID
pressed = {}
SetCommand(3000 + LEFT, 1); SetCommand(3100 + LEFT, 1) -- ENG: M now, B2 at 0.2 s
SetCommand(3000 + LEFT, 1); SetCommand(3100 + LEFT, 1) -- ASE: waits
tick(0.3)
check(same(presses_down(), {M, ENG}), "a new step on the same MPD waits while a sequence runs")
tick(0.5)
check(same(presses_down(), {M, ENG, M, ASE}), "then runs whole, once the sequence is over")
local order = {}
for _, p in ipairs(pressed) do order[#order + 1] = p.command..":"..p.value end
check(same(order, {M..":1", M..":0", ENG..":1", ENG..":0", M..":1", M..":0", ASE..":1", ASE..":0"}),
	"each button released before the next")

-- A step on the other MPD does not.
pressed = {}
short_press(LEFT) -- FCR
short_press(LEFT); short_press(LEFT); short_press(LEFT) -- WPN, TSD, VID
pressed = {}
SetCommand(3000 + LEFT, 1); SetCommand(3100 + LEFT, 1) -- ENG on the left MPD
SetCommand(3000 + RIGHT, 1); SetCommand(3100 + RIGHT, 1) -- FCR on the right MPD
tick(0.4)
check(same(presses_down(), {M, FCR, ENG}), "a step on the other MPD lets the sequence finish")
short_press(RIGHT) -- WPN, back in step for the right MPD checks

pressed = {}
short_press(LEFT_HOLD_TSD) -- ASE: the seven left commands share the cycle
check(same(presses_down(), {M, ASE}), "commands of one MPD share the cycle position")

pressed = {}
long_press(LEFT_HOLD_TSD)  -- TSD, and the cycle follows
short_press(LEFT)          -- VID
check(same(presses_down(), {TSD, VID}), "hold TSD goes to TSD, next short press gives VID")

pressed = {}
long_press(LEFT_HOLD_FCR)  -- FCR
short_press(LEFT_HOLD_VID) -- WPN
long_press(LEFT_HOLD_VID)  -- VID
short_press(LEFT)          -- ENG
check(same(presses_down(), {FCR, WPN, VID, M, ENG}), "hold FCR and hold VID, the cycle follows each")

pressed = {}
SetCommand(3000 + LEFT_HOLD_FCR, 1); tick(0.6)
check(same(presses_down(), {FCR}), "long action runs while still held")
SetCommand(3100 + LEFT_HOLD_FCR, 1); tick(0.4)
check(#presses_down() == 1, "releasing after a long press does nothing more")

pressed = {}
SetCommand(3000 + LEFT_HOLD_FCR, 1); tick(0.1)             -- its release gets lost
SetCommand(3000 + LEFT_HOLD_FCR, 1); tick(0.1); SetCommand(3100 + LEFT_HOLD_FCR, 1); tick(0.4)
check(same(presses_down(), {WPN}), "a press after a lost release counts as a new short press")

pressed = {}
short_press(RIGHT); short_press(RIGHT)
check(same(presses_down(), {TSD, VID}), "right MPD keeps its own cycle")
check(pressed[1].device == devices.MFD_PLT_RIGHT, "presses go to the pilot's right MPD")
pressed = {}
long_press(13)
check(same(presses_down(), {M, ENG}) and pressed[1].device == devices.MFD_PLT_RIGHT, "slot 13 is right MPD, hold ENG")
pressed = {}
long_press(14)
check(same(presses_down(), {M, ASE}) and pressed[1].device == devices.MFD_PLT_RIGHT, "slot 14 is right MPD, hold ASE")

-- Gunner: slots 21-27 left MPD, 28-34 right MPD, on the gunner's MPDs.
pressed = {}
short_press(21); short_press(21)
check(same(presses_down(), {FCR, WPN}) and pressed[1].device == devices.MFD_CPG_LEFT, "gunner left MPD cycles on the gunner's left MPD")
pressed = {}
long_press(26)
check(same(presses_down(), {M, ENG}) and pressed[1].device == devices.MFD_CPG_LEFT, "gunner left MPD, hold ENG (slot 26)")
pressed = {}
long_press(32)
check(same(presses_down(), {VID}) and pressed[1].device == devices.MFD_CPG_RIGHT, "gunner right MPD, hold VID (slot 32)")
pressed = {}
long_press(34)
check(same(presses_down(), {M, ASE}) and pressed[1].device == devices.MFD_CPG_RIGHT, "gunner right MPD, hold ASE (slot 34)")
pressed = {}
short_press(LEFT)
check(pressed[1].device == devices.MFD_PLT_LEFT, "the pilot's commands still press the pilot's MPD")
check(listened[3040] and listened[3140], "slots up to 40 listened")

pressed = {}
SetCommand(3015, 1); SetCommand(3115, 1); tick(0.4)
check(#pressed == 0, "unused slot 15 presses nothing")
long_press(11)
check(same(presses_down(), {TSD}) and pressed[1].device == devices.MFD_PLT_RIGHT, "slot 11 is still right MPD, hold TSD (bindings kept)")

check(#messages == 0, "no message on screen (show_messages = false)")

print(failures == 0 and "ALL OK" or (failures.." FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
