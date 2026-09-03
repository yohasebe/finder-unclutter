-- Hide every application other than Finder, when the workflow is configured to.
--
-- There is no scriptable "hide others" command, and the menu item title is
-- localised and not carried in AppKit's MenuCommands table, so this goes through
-- the keyboard shortcut. (The previous version wrapped an entirely commented-out
-- `click menu item` in a `try` and put the keystroke in the `on error` branch --
-- the empty `try` never raised, so the keystroke never ran and the setting did
-- nothing at all.)

on hideOtherApplications()
	if not my envFlag("hide_others") then return
	tell application "System Events" to launch application "System Events"
	my pauseFor("delay_system_events_launch", 0.2)
	tell application "System Events"
		tell process "Finder" to set frontmost to true
		keystroke "h" using {option down, command down}
	end tell
	my pauseFor("delay_window_operation", 0.2)
end hideOtherApplications
