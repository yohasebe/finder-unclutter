-- Keep the front window (Finder exposes each tab as a window, so this closes
-- other tabs too) and close everything else. Iterating over a snapshot of
-- id-based references avoids the old `repeat while window 2 exists` loop, which
-- would spin forever on a window that refuses to close.

tell application "Finder"
	activate
	if (count of Finder windows) is 0 then return
	set survivorID to id of front Finder window
	repeat with aWindow in (get every Finder window)
		try
			if id of aWindow is not survivorID then close aWindow
		end try
	end repeat
end tell
