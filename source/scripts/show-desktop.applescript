-- Show the desktop through Mission Control itself rather than by pressing the
-- key assigned to it. The old way sent key code 103 (F11), which does nothing
-- once "Show Desktop" is unassigned or disabled in System Settings > Keyboard >
-- Keyboard Shortcuts -- and nothing reported that it had done nothing.
-- Launching Mission Control with the argument 1 shows the desktop regardless of
-- that setting, and running it again brings the windows back, just as the key
-- does. It has to go through `open`: executing the binary inside the app bundle
-- directly is killed by macOS's launch constraints (exit 137).

do shell script "/usr/bin/open -b com.apple.exposelauncher --args 1"
