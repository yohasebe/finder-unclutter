-- Hide every application other than Finder, when the workflow is configured to.
--
-- This sets each visible application's `visible` to false through System
-- Events instead of pressing Option-Command-H. A keystroke goes to whichever
-- application is frontmost at that instant, so when Finder has not come to the
-- front yet it hides the wrong set of applications -- or, sent to an app that
-- binds the shortcut to something else, does something else entirely. Setting
-- `visible` does not depend on focus.

on hideOtherApplications()
	if not my envFlag("hide_others") then return
	try
		tell application "System Events"
			set visible of (every process whose visible is true and background only is false and bundle identifier is not "com.apple.finder") to false
		end tell
	end try
	my pauseFor("delay_window_operation", 0.2)
end hideOtherApplications
