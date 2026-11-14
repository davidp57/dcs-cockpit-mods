-- Cockpit cycles, AH-64D: slots for both seats.
-- Run by device.lua, inside the cycles device. Returns the settings and the slots.
--
-- Slot 1, left MPD: a short press goes to the next page of FCR, WPN, TSD (then FCR again),
-- a long press goes back to FCR (the next short press then gives WPN).

dofile(LockOn_Options.script_path.."devices.lua")      -- devices.*
dofile(LockOn_Options.script_path.."command_defs.lua") -- mpd_commands.*

-- Which equipment receives the button presses: not settled yet, to be tried in game.
-- Change TARGET, run install.ps1 -Part Cycles again and restart the mission.
--   PLT:   the pilot's left MPD, pressed as a mouse click would (performClickableAction).
--          Presses the pilot's MPD whatever the seat.
--   CPG:   the same on the gunner's left MPD.
--   INPUT: the equipment ED's own "Left MPD Pushbutton" bindings use (MFD_INPUT_LEFT), sent
--          as those bindings send it (SetCommand). It may follow the seat in use, so one
--          setting would serve both seats.
local TARGET = "PLT"

local LEFT_MPD = {
	PLT   = {device = devices.MFD_PLT_LEFT,   method = "click",   name = "pilot left MPD"},
	CPG   = {device = devices.MFD_CPG_LEFT,   method = "click",   name = "gunner left MPD"},
	INPUT = {device = devices.MFD_INPUT_LEFT, method = "command", name = "left MPD input"},
}

local left = LEFT_MPD[TARGET]

local function left_mpd(command, label)
	return {device = left.device, command = command, method = left.method, label = left.name.." "..label}
end

local FCR = left_mpd(mpd_commands.FCR, "FCR")
local WPN = left_mpd(mpd_commands.WPN, "WPN")
local TSD = left_mpd(mpd_commands.TSD, "TSD")

return {
	description = "target "..TARGET.." ("..left.name..")",
	long_press = 0.5,
	-- On screen while trying it out; set to false once settled.
	show_messages = true,
	slots = {
		[1] = {
			short = {cycle = {FCR, WPN, TSD}},
			long  = {press = FCR},
		},
	},
}
