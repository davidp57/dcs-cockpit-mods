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
local FCR, WPN, TSD, VID, AC = mpd_commands.FCR, mpd_commands.WPN, mpd_commands.TSD, mpd_commands.VID, mpd_commands.AC

-- Slots of config/AH-64D.lua: 1-5 left MPD, 8-12 right MPD; in each, no hold, then hold
-- FCR, WPN, TSD, VID.
local LEFT, LEFT_HOLD_FCR, LEFT_HOLD_TSD, LEFT_HOLD_VID, RIGHT = 1, 2, 4, 5, 8

local function short_press(slot)
	SetCommand(3000 + slot, 1); tick(0.1); SetCommand(3100 + slot, 1); tick(0.2)
end
local function long_press(slot)
	SetCommand(3000 + slot, 1); tick(0.7); SetCommand(3100 + slot, 1); tick(0.2)
end
local function same(seq, expected)
	if #seq ~= #expected then return false end
	for i = 1, #seq do if seq[i] ~= expected[i] then return false end end
	return true
end

-- Without a long press, the page changes as soon as the key is pressed.
SetCommand(3000 + LEFT, 1)
check(same(presses_down(), {FCR}), "no-hold command presses at once, before the release")
SetCommand(3100 + LEFT, 1); tick(0.2)
short_press(LEFT); short_press(LEFT); short_press(LEFT); short_press(LEFT); short_press(LEFT)
check(same(presses_down(), {FCR, WPN, TSD, VID, AC, FCR}), "left MPD cycles FCR, WPN, TSD, VID, A/C, FCR")
check(pressed[1].device == devices.MFD_PLT_LEFT and pressed[1].method == "click", "presses go to the pilot's left MPD as clicks")
local releases = 0
for _, p in ipairs(pressed) do if p.value == 0 then releases = releases + 1 end end
check(releases == 6, "each press is released")

pressed = {}
short_press(LEFT_HOLD_TSD) -- WPN: the five left commands share the cycle
check(same(presses_down(), {WPN}), "commands of one MPD share the cycle position")

pressed = {}
long_press(LEFT_HOLD_TSD)  -- TSD, and the cycle follows
short_press(LEFT)          -- VID
check(same(presses_down(), {TSD, VID}), "hold TSD goes to TSD, next short press gives VID")

pressed = {}
long_press(LEFT_HOLD_FCR)  -- FCR
short_press(LEFT_HOLD_VID) -- WPN
long_press(LEFT_HOLD_VID)  -- VID
short_press(LEFT)          -- A/C
check(same(presses_down(), {FCR, WPN, VID, AC}), "hold FCR and hold VID, the cycle follows each")

pressed = {}
SetCommand(3000 + LEFT_HOLD_FCR, 1); tick(0.6)
check(same(presses_down(), {FCR}), "long action runs while still held")
SetCommand(3100 + LEFT_HOLD_FCR, 1); tick(0.2)
check(#presses_down() == 1, "releasing after a long press does nothing more")

pressed = {}
SetCommand(3000 + LEFT_HOLD_FCR, 1); tick(0.1)             -- its release gets lost
SetCommand(3000 + LEFT_HOLD_FCR, 1); tick(0.1); SetCommand(3100 + LEFT_HOLD_FCR, 1); tick(0.2)
check(same(presses_down(), {WPN}), "a press after a lost release counts as a new short press")

pressed = {}
short_press(RIGHT); short_press(RIGHT)
check(same(presses_down(), {FCR, WPN}), "right MPD cycles FCR, WPN, on its own")
check(pressed[1].device == devices.MFD_PLT_RIGHT, "presses go to the pilot's right MPD")

-- Gunner: slots 21-25 left MPD, 28-32 right MPD, on the gunner's MPDs.
pressed = {}
short_press(21); short_press(21)
check(same(presses_down(), {FCR, WPN}) and pressed[1].device == devices.MFD_CPG_LEFT, "gunner left MPD cycles on the gunner's left MPD")
pressed = {}
long_press(32)
check(same(presses_down(), {VID}) and pressed[1].device == devices.MFD_CPG_RIGHT, "gunner right MPD, hold VID, on the gunner's right MPD")
pressed = {}
short_press(LEFT)
check(pressed[1].device == devices.MFD_PLT_LEFT, "the pilot's commands still press the pilot's MPD")
check(listened[3040] and listened[3140], "slots up to 40 listened")

pressed = {}
SetCommand(3006, 1); SetCommand(3106, 1); tick(0.2)
check(#pressed == 0, "dropped slot 6 presses nothing")
long_press(11)
check(same(presses_down(), {TSD}) and pressed[1].device == devices.MFD_PLT_RIGHT, "slot 11 is still right MPD, hold TSD (bindings kept)")

check(#messages == 0, "no message on screen (show_messages = false)")

print(failures == 0 and "ALL OK" or (failures.." FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
