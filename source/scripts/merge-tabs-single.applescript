-- Merge step ahead of the single pane layout: every folder stays as a tab.

use scripting additions

on run argv
	my mergeIntoTabs(false)
end run

--#include lib/env.applescript
--#include lib/finder.applescript
--#include lib/merge-tabs.applescript
