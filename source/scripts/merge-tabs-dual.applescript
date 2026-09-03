-- Merge step ahead of the dual pane layout. The folder destined for the
-- secondary pane is dropped here so it does not also appear as a tab of the
-- primary pane.

use scripting additions

on run argv
	my mergeIntoTabs(true)
end run

--#include lib/env.applescript
--#include lib/finder.applescript
--#include lib/merge-tabs.applescript
