-- Split one region of the screen between two Finder windows.
--
-- This replaces the two near-identical horizontal and vertical scripts: the
-- layout is "pick a region, then cut it in half along one axis", and only the
-- axis differs. `orientation` is "horizontal" for a side-by-side split and
-- "vertical" for a stacked one.

use framework "AppKit"
use scripting additions

on run argv
	set orientationName to my envText("orientation", "horizontal")
	set positionName to my envText("dual_pane_window_position", "fill")
	set sidebarMode to my envText("sidebars", "single")
	set sidebarPixels to my envNumber("sidebar_width", 200)
	set sidesReversed to my envFlag("reverse")
	set primaryView to my envText("view_type_primary", "list")
	set secondaryView to my envText("view_type_secondary", "list")

	set {regionLeft, regionTop, regionWidth, regionHeight} to my regionForPosition(positionName, my activeUsableRect())

	-- Finder will not shrink a window below its sidebar plus ~324pt of content
	-- (measured: a window asked for 100pt came back 316pt; with a 192pt
	-- sidebar, 516pt). sidebar_width can be configured up to 500 while a
	-- region can be far narrower, so cap the sidebar to what the panes can
	-- actually hold -- otherwise Finder clamps the bounds itself and the
	-- panes overlap. The horizontal single case is the tightest: the leading
	-- pane is regionWidth/2 + sidebar/2 and must fit sidebar + 324.
	set maxSidebar to regionWidth - 324
	if orientationName is not "vertical" then
		if sidebarMode is "double" then
			set maxSidebar to (regionWidth / 2) - 324
		else if sidebarMode is "single" then
			set maxSidebar to regionWidth - 648
		end if
	end if
	if sidebarPixels > maxSidebar then set sidebarPixels to maxSidebar
	if sidebarPixels < 0 then set sidebarPixels to 0

	-- With a sidebar on one pane only, the two file lists come out the same width
	-- only if the divider moves by half the sidebar's width.
	set dividerShift to 0
	if sidebarMode is "single" and orientationName is not "vertical" then
		set dividerShift to sidebarPixels / 2
		-- Belt and braces past the sidebar cap above: keep the trailing
		-- (sidebar-less) pane at or above the 316pt floor.
		set maxShift to (regionWidth / 2) - 316
		if dividerShift > maxShift then set dividerShift to maxShift
		if dividerShift < 0 then set dividerShift to 0
	end if

	if orientationName is "vertical" then
		set leadingRect to {regionLeft, regionTop, regionWidth, regionHeight / 2}
		set trailingRect to {regionLeft, regionTop + regionHeight / 2, regionWidth, regionHeight / 2}
	else
		set leadingRect to {regionLeft, regionTop, regionWidth / 2 + dividerShift, regionHeight}
		set trailingRect to {regionLeft + regionWidth / 2 + dividerShift, regionTop, regionWidth / 2 - dividerShift, regionHeight}
	end if

	if sidebarMode is "double" then
		set {leadingSidebar, trailingSidebar} to {sidebarPixels, sidebarPixels}
	else if sidebarMode is "none" then
		set {leadingSidebar, trailingSidebar} to {0, 0}
	else
		set {leadingSidebar, trailingSidebar} to {sidebarPixels, 0}
	end if

	tell application "Finder"
		if (count of Finder windows) is 0 then
			set homeAlias to my homeFolderAlias()
			if homeAlias is missing value then
				my reportBadHomeFolder()
				return
			end if
			make new Finder window to homeAlias
			my pauseFor("wait_in_seconds", 0.1)
		end if
		set primaryWindow to front Finder window
		try
			set secondaryWindow to make new Finder window to (my secondaryTargetFor(primaryWindow))
		on error
			-- The secondary target could not be opened (e.g. the primary window
			-- shows a transient search in "same" mode); fall back to the home
			-- folder rather than erroring out mid-layout.
			set secondaryWindow to make new Finder window to (my homeFolderAlias())
		end try
		my pauseFor("wait_in_seconds", 0.1)
	end tell

	-- "Reverse" swaps which side the primary folder lands on; the sidebar stays
	-- with the leading pane either way.
	if sidesReversed then
		set {primaryRect, secondaryRect} to {trailingRect, leadingRect}
		set {primarySidebar, secondarySidebar} to {trailingSidebar, leadingSidebar}
	else
		set {primaryRect, secondaryRect} to {leadingRect, trailingRect}
		set {primarySidebar, secondarySidebar} to {leadingSidebar, trailingSidebar}
	end if

	-- Chrome before geometry. Finder refuses to make a window narrower than its
	-- sidebar plus a minimum content area, so a pane that still carries a wide
	-- sidebar from a previous run silently comes out too wide if the bounds are
	-- set first. Setting the sidebar (0 included) up front removes that floor.
	my applyChrome(secondaryWindow, secondaryView, secondarySidebar)
	my pauseFor("wait_in_seconds", 0.1)
	my applyChrome(primaryWindow, primaryView, primarySidebar)
	my pauseFor("wait_in_seconds", 0.1)

	tell application "Finder"
		set bounds of secondaryWindow to my boundsOfRect(secondaryRect)
		set bounds of primaryWindow to my boundsOfRect(primaryRect)
		activate
	end tell
end run

--#include lib/env.applescript
--#include lib/screen.applescript
--#include lib/finder.applescript
