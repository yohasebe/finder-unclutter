use scripting additions

on run argv
	tell application "System Events" to launch application "System Events"
	my pauseFor("delay_system_events_launch", 0.2)
	tell application "System Events" to key code (my envNumber("show_desktop_keycode", 103))
	my pauseFor("delay_window_operation", 0.2)
end run

--#include lib/env.applescript
