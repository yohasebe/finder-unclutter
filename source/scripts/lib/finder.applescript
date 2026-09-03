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
