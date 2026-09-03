-- Place the front Finder window in one region of the screen it already lives on.

use framework "AppKit"
use scripting additions

on run argv
	set positionName to my envText("single_pane_window_position", "fill")
	set viewName to my envText("view_type_primary", "list")
	set sidebarPixels to my envNumber("sidebar_width", 200)
	if my envText("sidebars", "single") is "none" then set sidebarPixels to 0

	-- Read the screen before opening anything, so an existing window's display
	-- decides the layout rather than wherever Finder drops a brand new window.
	set targetRect to my regionForPosition(positionName, my activeUsableRect())

	tell application "Finder"
		activate
		if (count of Finder windows) is 0 then
			set homeAlias to my homeFolderAlias()
			if homeAlias is missing value then
				my reportBadHomeFolder()
				return
			end if
			make new Finder window to homeAlias
			my pauseFor("wait_in_seconds", 0.1)
		end if
		set theWindow to front Finder window
	end tell

	-- Chrome first: Finder will not shrink a window below its sidebar plus a
	-- minimum content area, so the sidebar has to be settled before the bounds.
	my applyChrome(theWindow, viewName, sidebarPixels)
	tell application "Finder" to set bounds of theWindow to my boundsOfRect(targetRect)
end run

--#include lib/env.applescript
--#include lib/screen.applescript
--#include lib/finder.applescript
