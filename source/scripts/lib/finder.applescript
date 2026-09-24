-- Folder resolution and per-window chrome shared by the pane layouts.

-- The configured home folder is a UNIX path typed by the user, so it may start
-- with "~" and may contain spaces. Resolving it to an alias here means no part of
-- the workflow has to hand-escape it for a shell.
on expandTilde(pathText)
	if pathText does not start with "~" then return pathText
	set homeDirectory to POSIX path of (path to home folder)
	if homeDirectory ends with "/" then set homeDirectory to text 1 thru -2 of homeDirectory
	if pathText is "~" then return homeDirectory
	if pathText starts with "~/" then return homeDirectory & (text 2 thru -1 of pathText)
	return pathText
end expandTilde

on folderAliasFor(pathText)
	try
		return (POSIX file (my expandTilde(pathText))) as alias
	on error
		return missing value
	end try
end folderAliasFor

on homeFolderAlias()
	return my folderAliasFor(my envText("home_folder", "~"))
end homeFolderAlias

on reportBadHomeFolder()
	try
		tell application id "com.runningwithcrayons.Alfred" to run trigger "stop" in workflow "com.yohasebe.finder.unclutter"
	end try
	tell application "Finder" to activate
	display dialog "The folder set as \"Home Folder\" in the workflow configuration does not exist. Please check the configuration." buttons {"OK"} default button "OK" with title "Finder Unclutter" with icon caution
end reportBadHomeFolder

-- What the secondary pane should show, given the window that holds the primary
-- pane's folder.
on secondaryTargetFor(primaryWindow)
	set secondaryMode to my envText("folder_secondary", "same")
	if secondaryMode is "home" then
		set homeAlias to my homeFolderAlias()
		if homeAlias is not missing value then return homeAlias
	else if secondaryMode is "desktop" then
		try
			return (path to desktop folder) as alias
		end try
	else if secondaryMode is "parent" then
		try
			tell application "Finder" to return (container of (target of primaryWindow)) as alias
		end try
		try
			return (POSIX file "/") as alias
		end try
	end if
	-- Anything else -- "same", or "left", the value older prefs.plist files
	-- carry for "same as primary" -- mirrors the primary pane.
	tell application "Finder" to return target of primaryWindow
end secondaryTargetFor

on viewConstantFor(viewName)
	tell application "Finder"
		if viewName is "icon" then return icon view
		if viewName is "column" then return column view
		if viewName is "gallery" then return flow view
		return list view
	end tell
end viewConstantFor

-- Sidebar width only takes effect on the frontmost window, hence the `set index`
-- before it.
on applyChrome(theWindow, viewName, sidebarPixels)
	tell application "Finder"
		set toolbar visible of theWindow to true
		set pathbar visible of theWindow to true
		set statusbar visible of theWindow to true
		try
			set current view of theWindow to my viewConstantFor(viewName)
		end try
		set index of theWindow to 1
		try
			set sidebar width of theWindow to sidebarPixels
		end try
	end tell
end applyChrome

-- Set a window's bounds and return what Finder actually made of them, as
-- {left, top, width, height}. Finder silently widens a window it considers too
-- narrow, and the floor is not a constant: it is ~316pt plus the sidebar plus,
-- when the preview pane is showing, the preview pane's width -- which the user
-- can drag, and which Finder remembers per folder, so it cannot be known in
-- advance. Gallery view shows the preview by default. So ask Finder rather
-- than predict it. The clamped bounds read back immediately; no delay is needed.
on placeWindow(theWindow, aRect)
	tell application "Finder"
		set bounds of theWindow to my boundsOfRect(aRect)
		set actualBounds to bounds of theWindow
	end tell
	set {boundsLeft, boundsTop, boundsRight, boundsBottom} to actualBounds
	return {boundsLeft, boundsTop, boundsRight - boundsLeft, boundsBottom - boundsTop}
end placeWindow

-- Two panes side by side in the region {left, top, width, height}, the divider
-- ideally at leadingWidth. Each pass records the smallest width Finder has
-- shown it will accept for a pane (the width it widened that pane to), then
-- puts the divider as close to the ideal as those floors allow.
--
-- When the floors add up to more than the region -- say two gallery panes in
-- half a screen -- the pair is kept side by side at those widths and allowed
-- to spill out of the region, centred on it but held inside the screen.
-- Stacking one pane on top of the other would leave one of them unusable.
-- Only when even the whole screen is too narrow do they overlap, pinned to its
-- edges.
on placeSideBySide(leadingWindow, trailingWindow, regionRect, leadingWidth, screenRect)
	set {regionLeft, regionTop, regionWidth, regionHeight} to regionRect
	set {screenLeft, screenTop, screenWidth, screenHeight} to screenRect
	set idealLeading to leadingWidth
	set leadingFloor to 0
	set trailingFloor to 0
	repeat 4 times
		set trailingWidth to regionWidth - leadingWidth
		set leadingGot to item 3 of my placeWindow(leadingWindow, {regionLeft, regionTop, leadingWidth, regionHeight})
		set trailingGot to item 3 of my placeWindow(trailingWindow, {regionLeft + leadingWidth, regionTop, trailingWidth, regionHeight})
		if leadingGot > leadingWidth + 1 then set leadingFloor to leadingGot
		if trailingGot > trailingWidth + 1 then set trailingFloor to trailingGot
		if leadingGot ≤ leadingWidth + 1 and trailingGot ≤ trailingWidth + 1 then return
		if leadingFloor + trailingFloor > regionWidth then exit repeat
		set leadingWidth to idealLeading
		if leadingWidth < leadingFloor then set leadingWidth to leadingFloor
		if leadingWidth > regionWidth - trailingFloor then set leadingWidth to regionWidth - trailingFloor
	end repeat
	-- The region cannot hold both panes.
	set leadingWidth to leadingGot
	set trailingWidth to trailingGot
	if leadingFloor > leadingWidth then set leadingWidth to leadingFloor
	if trailingFloor > trailingWidth then set trailingWidth to trailingFloor
	set pairWidth to leadingWidth + trailingWidth
	if pairWidth ≤ screenWidth then
		set pairLeft to regionLeft + (regionWidth - pairWidth) / 2
		if pairLeft + pairWidth > screenLeft + screenWidth then set pairLeft to screenLeft + screenWidth - pairWidth
		if pairLeft < screenLeft then set pairLeft to screenLeft
		my placeWindow(leadingWindow, {pairLeft, regionTop, leadingWidth, regionHeight})
		my placeWindow(trailingWindow, {pairLeft + leadingWidth, regionTop, trailingWidth, regionHeight})
	else
		my placeWindow(leadingWindow, {screenLeft, regionTop, leadingWidth, regionHeight})
		my placeWindow(trailingWindow, {screenLeft + screenWidth - trailingWidth, regionTop, trailingWidth, regionHeight})
	end if
end placeSideBySide

-- Pull a window back inside the screen area it was laid out on, when Finder
-- made it wider or taller than the space it was given. Only ever moves the
-- window, never resizes it: Finder has already said it will not go smaller.
on keepOnScreen(theWindow, screenRect)
	set {screenLeft, screenTop, screenWidth, screenHeight} to screenRect
	tell application "Finder" to set {boundsLeft, boundsTop, boundsRight, boundsBottom} to bounds of theWindow
	set shiftX to 0
	set shiftY to 0
	if boundsRight > screenLeft + screenWidth then set shiftX to (screenLeft + screenWidth) - boundsRight
	if boundsLeft + shiftX < screenLeft then set shiftX to screenLeft - boundsLeft
	if boundsBottom > screenTop + screenHeight then set shiftY to (screenTop + screenHeight) - boundsBottom
	if boundsTop + shiftY < screenTop then set shiftY to screenTop - boundsTop
	if shiftX is 0 and shiftY is 0 then return
	tell application "Finder" to set bounds of theWindow to {round (boundsLeft + shiftX), round (boundsTop + shiftY), round (boundsRight + shiftX), round (boundsBottom + shiftY)}
end keepOnScreen
