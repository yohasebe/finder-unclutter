-- Collapse every open Finder window and tab into one window carrying one tab per
-- distinct folder.
--
-- Finder surfaces each tab as its own `Finder window` in AppleScript and offers
-- no way to ask which window a tab belongs to; background tabs even keep
-- reporting the bounds they had before their window was moved. System Events, by
-- contrast, sees only real windows, so the count it reports is what tells us
-- whether everything already lives in one window.
--
-- Tabs are built with Cmd-T plus `set target`, not with the Window menu's
-- "Merge All Windows". That item is unreliable: on macOS 26 Finder reports it as
-- disabled and ignores both `click` and AXPress even with several plain windows
-- open, and its title is localised, which is why the workflow used to demand
-- that Finder run in English. Cmd-T is a fixed shortcut in every language and
-- works regardless of the "Prefer tabs when opening documents" setting.

on mergeIntoTabs(dropSecondaryFolder)
	set fallbackPath to my envText("home_folder", "~")
	set frontPath to fallbackPath
	set orderedPaths to {}
	set duplicateSeen to false
	set excludedSeen to false

	tell application "Finder"
		set openWindows to every Finder window
		if (count of openWindows) is 0 then
			activate
			return
		end if

		set frontWindow to item 1 of openWindows
		try
			set frontPath to POSIX path of ((target of frontWindow) as alias)
		end try

		-- The dual pane opens the secondary folder in a window of its own, so
		-- keeping it as a tab of the primary window too is just clutter. Never
		-- exclude the primary folder itself, though: with folder_secondary =
		-- "same" the secondary IS the primary folder, and dropping it here
		-- would retarget the front tab to a folder the user did not choose.
		set excludedPath to ""
		if dropSecondaryFolder then
			try
				set candidatePath to POSIX path of ((my secondaryTargetFor(frontWindow)) as alias)
				if candidatePath is not frontPath then set excludedPath to candidatePath
			end try
		end if

		-- A window whose target will not coerce to an alias (a transient search
		-- result) contributes no path and is never closed by the rebuild:
		-- `set target` cannot recreate it. Saved Smart Folders (.savedSearch)
		-- DO coerce -- their path is the search file -- so they flow through
		-- orderedPaths like any folder and survive being rebuilt.
		repeat with aWindow in openWindows
			set aPath to ""
			try
				set aPath to POSIX path of ((target of aWindow) as alias)
			end try
			if aPath is not "" then
				if aPath is excludedPath then
					set excludedSeen to true
				else if aPath is in orderedPaths then
					set duplicateSeen to true
				else
					set end of orderedPaths to aPath
				end if
			end if
		end repeat

		if orderedPaths is {} then set orderedPaths to {frontPath}
		activate
	end tell

	-- One real browser window, no duplicate tabs and nothing to exclude:
	-- everything already lives in one window, so leave the user's tab order and
	-- scroll positions alone. `excludedSeen` matters because the dual pane is
	-- about to open that folder in its own window; without it the folder would
	-- stay as a tab of the primary pane as well, which is the clutter excluding
	-- it was meant to avoid.
	-- realWindowCount() is -1 when System Events cannot answer (no Accessibility
	-- permission); unverifiable means do not rebuild.
	set realCount to my realWindowCount()
	set needsRebuild to (realCount > 1) or duplicateSeen or excludedSeen

	if needsRebuild then my rebuildAsTabs(orderedPaths, excludedPath)
end mergeIntoTabs

-- Build first, destroy last. The originals stay open until every wanted tab
-- really exists; if tab creation fails at any point (e.g. Cmd-T cannot fire
-- without Accessibility permission) the rebuild aborts and closes nothing, so
-- Finder is left untidy but intact rather than exploded into one window per
-- folder.
on rebuildAsTabs(orderedPaths, excludedPath)
	set survivorID to missing value
	set originalIDs to {}
	-- Finder answers "busy" (-15260) while it has heavy work in flight (a Smart
	-- Folder's Spotlight query, iCloud churn), so retry briefly. If it never
	-- answers, abort before anything is built or closed.
	repeat 10 times
		try
			tell application "Finder"
				activate
				set survivorID to id of front Finder window
				set originalIDs to id of every Finder window
			end tell
			exit repeat
		on error
			delay 0.2
		end try
	end repeat
	if survivorID is missing value then return

	-- Point the survivor at the first folder. The guard is strict on purpose:
	-- retarget only when the survivor's current target resolves to a path that
	-- is part of the rebuild. Anything else -- a transient search, or a folder
	-- that dropped out of orderedPaths because Finder was too busy to answer --
	-- is left alone, because retargeting would destroy it.
	try
		tell application "Finder"
			set survivorPath to POSIX path of ((target of Finder window id survivorID) as alias)
			if (survivorPath is in orderedPaths) and (survivorPath is not (item 1 of orderedPaths)) then
				set firstAlias to my folderAliasFor(item 1 of orderedPaths)
				if firstAlias is not missing value then set target of Finder window id survivorID to firstAlias
			end if
		end tell
	end try

	-- New tabs land after the survivor window's existing tabs, and the old
	-- ones are closed below, so the surviving order is still orderedPaths
	-- order.
	if (count of orderedPaths) ≥ 2 then
		tell application "System Events" to launch application "System Events"
		my pauseFor("delay_system_events_launch", 0.2)
		repeat with pathIndex from 2 to (count of orderedPaths)
			set nextAlias to my folderAliasFor(item pathIndex of orderedPaths)
			if nextAlias is not missing value then
				if not (my openAsTab(nextAlias)) then return
			end if
		end repeat
	end if

	-- Every wanted tab now exists; close the originals except the survivor, and
	-- only when their target is part of the rebuild (or the folder the dual
	-- pane opens separately). A window whose target cannot be recreated --
	-- a transient search, or one that dropped out of orderedPaths while Finder
	-- was busy -- stays open, so the result is then not strictly one window.
	-- The id comparison coerces to text: `repeat with x in (id of every …)`
	-- binds references, not integers, and `reference is integer` is false even
	-- when the ids match (measured) -- which closed the survivor itself.
	tell application "Finder"
		repeat with anID in originalIDs
			if (anID as text) is not (survivorID as text) then
				try
					set aPath to POSIX path of ((target of Finder window id anID) as alias)
					if (aPath is in orderedPaths) or (aPath is excludedPath) then close Finder window id anID
				end try
			end if
		end repeat
	end tell

	-- Leave the folder that was frontmost showing, rather than the last tab made.
	try
		tell application "Finder" to set index of Finder window id survivorID to 1
	end try
end rebuildAsTabs

-- How many real Finder browser windows there are, tabs not counted. System
-- Events also sees Get Info panels and copy-progress windows as windows of
-- the Finder process, so they have to be told apart from browser windows.
--
-- The test is the presence of a split group -- the sidebar/content divider.
-- Measured on macOS 26: a browser window keeps its AXSplitGroup child with the
-- toolbar hidden, with `sidebar width` set to 0, and with the sidebar hidden
-- outright via Cmd-Opt-S; a Get Info window has an AXScrollArea and no split
-- group. Two things that look like they would work but do not: subrole is
-- "AXStandardWindow" for both, and `exists toolbar 1` reports false for a
-- browser window whose toolbar the user has hidden -- which would count such a
-- user's windows as zero and silently stop merging from ever happening.
--
-- Returns -1 when System Events cannot answer (no Accessibility permission),
-- which callers treat as "unverifiable: do not rebuild".
on realWindowCount()
	try
		tell application "System Events" to tell process "Finder"
			set browserCount to 0
			repeat with w in (get every window)
				if (exists splitter group 1 of w) or (exists toolbar 1 of w) then
					set browserCount to browserCount + 1
				end if
			end repeat
			return browserCount
		end tell
	end try
	return -1
end realWindowCount

-- Cmd-T, wait for the tab to really appear, then retarget it. Returns true
-- only on success. There is no fallback window: a caller that gets false
-- aborts the rebuild and closes nothing, and opening a separate window would
-- leave Finder in a state the user did not ask for.
on openAsTab(folderAlias)
	tell application "Finder" to set beforeCount to count of Finder windows
	try
		tell application "System Events"
			tell process "Finder" to set frontmost to true
			keystroke "t" using command down
		end tell
	end try
	-- Poll for the tab instead of trusting a fixed delay. A fixed delay was both
	-- slower and wrong: with several folders to add, Cmd-T for the later ones
	-- landed while Finder was still busy and the tab never appeared. Retargeting
	-- a tab that does not exist would overwrite a folder the user still wants, so
	-- the retarget only happens once the new tab is really there.
	repeat 20 times
		delay 0.05
		tell application "Finder" to set nowCount to count of Finder windows
		if nowCount > beforeCount then
			try
				tell application "Finder" to set target of front Finder window to folderAlias
				return true
			end try
			return false
		end if
	end repeat
	return false
end openAsTab
