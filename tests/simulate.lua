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
check(listened[3001] and listened[3101] and listened[3008] and listened[3108], "slots 1-8 down and up commands listened")
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

-- Commands of the pilot's left MPD, from the aircraft's own files.
dofile(aircraft_scripts.."devices.lua")
dofile(aircraft_scripts.."command_defs.lua")
local FCR, WPN, TSD = mpd_commands.FCR, mpd_commands.WPN, mpd_commands.TSD

local function short_press()
	SetCommand(3001, 1); tick(0.1); SetCommand(3101, 1); tick(0.2)
end
local function long_press()
	SetCommand(3001, 1); tick(0.7); SetCommand(3101, 1); tick(0.2)
end

short_press(); short_press(); short_press(); short_press()
local seq = presses_down()
check(#seq == 4 and seq[1] == FCR and seq[2] == WPN and seq[3] == TSD and seq[4] == FCR, "short presses cycle FCR, WPN, TSD, FCR")
check(pressed[1].device == devices.MFD_PLT_LEFT and pressed[1].method == "click", "presses go to the pilot's left MPD as clicks")
local releases = 0
for _, p in ipairs(pressed) do if p.value == 0 then releases = releases + 1 end end
check(releases == 4, "each press is released")

pressed = {}
short_press() -- WPN
long_press()  -- FCR, and the cycle follows
short_press() -- WPN
seq = presses_down()
check(#seq == 3 and seq[1] == WPN and seq[2] == FCR and seq[3] == WPN, "long press goes to FCR, next short press gives WPN")

pressed = {}
SetCommand(3001, 1); tick(0.6)
check(#presses_down() == 1 and presses_down()[1] == FCR, "long action runs while still held")
SetCommand(3101, 1); tick(0.2)
check(#presses_down() == 1, "releasing after a long press does nothing more")

pressed = {}
SetCommand(3001, 1); tick(0.1)             -- its release gets lost
SetCommand(3001, 1); tick(0.1); SetCommand(3101, 1); tick(0.2)
seq = presses_down()
check(#seq == 1 and seq[1] == WPN, "a press after a lost release counts as a new short press")

pressed = {}
SetCommand(3002, 1); SetCommand(3102, 1); tick(0.2)
check(#pressed == 0, "unconfigured slot 2 presses nothing")

check(#messages > 0, "messages shown on screen")

print(failures == 0 and "ALL OK" or (failures.." FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
