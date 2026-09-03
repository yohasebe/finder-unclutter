-- Alfred exposes workflow variables as environment variables. `system attribute`
-- yields "" for anything unset, and "" as number raises, so every read goes
-- through these helpers with an explicit fallback.

on envText(keyName, fallbackValue)
	try
		set rawValue to system attribute keyName
		if rawValue is missing value then return fallbackValue
		if rawValue is "" then return fallbackValue
		return rawValue
	on error
		return fallbackValue
	end try
end envText

on envNumber(keyName, fallbackValue)
	try
		return (my envText(keyName, "")) as number
	on error
		return fallbackValue
	end try
end envNumber

on envFlag(keyName)
	set rawValue to my envText(keyName, "0")
	return rawValue is "1" or rawValue is "true"
end envFlag

on pauseFor(keyName, fallbackValue)
	set waitSeconds to my envNumber(keyName, fallbackValue)
	if waitSeconds > 0 then delay waitSeconds
end pauseFor
