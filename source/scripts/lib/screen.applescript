-- Screen geometry, in Finder's coordinate space.
--
-- NSScreen reports rects with the origin at the bottom-left of the primary
-- display and y growing upward. Finder's `bounds` and System Events' `position`
-- both put the origin at the top-left of the primary display with y growing
-- downward. Everything here returns the Finder convention as
-- {left, top, width, height}.
--
-- Reading NSScreen also replaces the old `system_profiler SPDisplaysDataType`
-- call, which cost several seconds on the first run after a reboot, and gives us
-- visibleFrame -- the area left over once the menu bar and a pinned Dock are
-- taken out -- so no menu bar height has to be guessed at.

on screenRects()
	set nsScreens to current application's NSScreen's screens()
	if (count of nsScreens) is 0 then return {}
	set primaryHeight to item 2 of item 2 of ((item 1 of nsScreens)'s frame())
	set rectList to {}
	repeat with aScreen in nsScreens
		set fullRect to my toFinderRect(aScreen's frame(), primaryHeight)
		set usableRect to my toFinderRect(aScreen's visibleFrame(), primaryHeight)
		set end of rectList to {fullArea:fullRect, usableArea:usableRect}
	end repeat
	return rectList
end screenRects

on toFinderRect(nsRect, primaryHeight)
	set originX to item 1 of item 1 of nsRect
	set originY to item 2 of item 1 of nsRect
	set rectWidth to item 1 of item 2 of nsRect
	set rectHeight to item 2 of item 2 of nsRect
	return {originX, primaryHeight - (originY + rectHeight), rectWidth, rectHeight}
end toFinderRect

on usableRectContaining(pointX, pointY)
	set rectList to my screenRects()
	if rectList is {} then return {0, 0, 1440, 900}
	repeat with anEntry in rectList
		set {rectLeft, rectTop, rectWidth, rectHeight} to fullArea of anEntry
		if pointX ≥ rectLeft and pointX < rectLeft + rectWidth then
			if pointY ≥ rectTop and pointY < rectTop + rectHeight then
				return usableArea of anEntry
			end if
		end if
	end repeat
	return usableArea of (item 1 of rectList)
end usableRectContaining

-- The screen the user is working on: the one holding the front Finder window,
-- or the one under the pointer when no window is open. The old code always used
-- whichever display system_profiler happened to list first, which dragged
-- windows back to the primary display.
on activeUsableRect()
	try
		tell application "Finder"
			if (count of Finder windows) > 0 then
				set frontBounds to bounds of front Finder window
				set centreX to ((item 1 of frontBounds) + (item 3 of frontBounds)) / 2
				set centreY to ((item 2 of frontBounds) + (item 4 of frontBounds)) / 2
				return my usableRectContaining(centreX, centreY)
			end if
		end tell
	end try
	try
		set nsScreens to current application's NSScreen's screens()
		set primaryHeight to item 2 of item 2 of ((item 1 of nsScreens)'s frame())
		set mouseAt to current application's NSEvent's mouseLocation()
		return my usableRectContaining(item 1 of mouseAt, primaryHeight - (item 2 of mouseAt))
	end try
	return my usableRectContaining(0, 0)
end activeUsableRect

-- Carve out the part of a screen a layout keyword refers to. Both the single and
-- the dual pane layouts start here; the dual pane then splits the result in two.
on regionForPosition(positionName, usableRect)
	set {rectLeft, rectTop, rectWidth, rectHeight} to usableRect
	if positionName is "left" then
		return {rectLeft, rectTop, rectWidth / 2, rectHeight}
	else if positionName is "right" then
		return {rectLeft + rectWidth / 2, rectTop, rectWidth / 2, rectHeight}
	else if positionName is "top" then
		return {rectLeft, rectTop, rectWidth, rectHeight / 2}
	else if positionName is "bottom" then
		return {rectLeft, rectTop + rectHeight / 2, rectWidth, rectHeight / 2}
	else if positionName is "center" then
		return {rectLeft + rectWidth / 6, rectTop + rectHeight / 6, rectWidth * 2 / 3, rectHeight * 2 / 3}
	end if
	return {rectLeft, rectTop, rectWidth, rectHeight} -- "fill", and anything unrecognised
end regionForPosition

on boundsOfRect(aRect)
	set {rectLeft, rectTop, rectWidth, rectHeight} to aRect
	return {round rectLeft, round rectTop, round (rectLeft + rectWidth), round (rectTop + rectHeight)}
end boundsOfRect
