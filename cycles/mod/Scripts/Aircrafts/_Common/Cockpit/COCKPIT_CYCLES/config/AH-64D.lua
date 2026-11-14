-- Cockpit cycles, AH-64D: page cycles of the two MPDs, for both seats.
-- Run by device.lua, inside the cycles device. Returns the settings and the slots.
--
-- Each MPD has five commands, all stepping through the same page cycle on a short press:
--   FCR > WPN > TSD > VID > A/C > FCR... (every page with its own button, except COM)
-- They differ only by what a long press does: nothing (the page then changes as soon as the
-- key is pressed), or go straight to FCR, WPN, TSD or VID. The pilot picks one of them in
-- Options > Controls; the commands of an MPD share their cycle position.
-- Slots, in the order of the Custom_Keybinds commands (dcs-community-keybinds):
--   1-5 left MPD, 8-12 right MPD; in each: no hold, then hold FCR, WPN, TSD, VID.

dofile(LockOn_Options.script_path.."devices.lua")      -- devices.*
dofile(LockOn_Options.script_path.."command_defs.lua") -- mpd_commands.*

-- Which equipment receives the button presses: not settled yet, to be tried in game.
-- Change TARGET, run install.ps1 -Part Cycles again and restart the mission.
--   PLT:   the pilot's MPDs, pressed as a mouse click would (performClickableAction).
--          Presses the pilot's MPDs whatever the seat.
--   CPG:   the same on the gunner's MPDs.
--   INPUT: the equipment ED's own "Left/Right MPD Pushbutton" bindings use
--          (MFD_INPUT_LEFT/RIGHT), sent as those bindings send it (SetCommand). It may follow
--          the seat in use, so one setting would serve both seats.
local TARGET = "PLT"

local MPDS = {
	PLT = {
		left  = {device = devices.MFD_PLT_LEFT,  method = "click", name = "pilot left MPD"},
		right = {device = devices.MFD_PLT_RIGHT, method = "click", name = "pilot right MPD"},
	},
	CPG = {
		left  = {device = devices.MFD_CPG_LEFT,  method = "click", name = "gunner left MPD"},
		right = {device = devices.MFD_CPG_RIGHT, method = "click", name = "gunner right MPD"},
	},
	INPUT = {
		left  = {device = devices.MFD_INPUT_LEFT,  method = "command", name = "left MPD input"},
		right = {device = devices.MFD_INPUT_RIGHT, method = "command", name = "right MPD input"},
	},
}

-- Page buttons of an MPD.
local PAGES = {
	FCR = mpd_commands.FCR,
	WPN = mpd_commands.WPN,
	TSD = mpd_commands.TSD,
	VID = mpd_commands.VID,
	["A/C"] = mpd_commands.AC,
}

-- Short press, both MPDs.
local CYCLE = {"FCR", "WPN", "TSD", "VID", "A/C"}

-- Long press, in the order of the commands.
local HOLD = {"FCR", "WPN", "TSD", "VID"}

local slots = {}

-- Adds the slots of one MPD, from slot number first.
local function add_mpd(side, first)
	local mpd = MPDS[TARGET][side]
	local buttons = {}
	for name, command in pairs(PAGES) do
		buttons[name] = {device = mpd.device, command = command, method = mpd.method, label = mpd.name.." "..name}
	end
	-- One action table for all the slots of the MPD: they share the cycle position.
	local cycle = {}
	for _, name in ipairs(CYCLE) do
		cycle[#cycle + 1] = buttons[name]
	end
	local next_page = {cycle = cycle}
	slots[first] = {short = next_page}
	for i, name in ipairs(HOLD) do
		slots[first + i] = {short = next_page, long = {press = buttons[name]}}
	end
end

-- Slot numbers are the command numbers DCS keeps the pilots' bindings under: never renumber.
-- 6-7 and 13-14 were long presses on COM and A/C, dropped on 2026-11-14.
add_mpd("left", 1)
add_mpd("right", 8)

return {
	description = "target "..TARGET,
	long_press = 0.5,
	-- On screen while trying it out; set to false once settled.
	show_messages = true,
	slots = slots,
}
