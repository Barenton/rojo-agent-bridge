--[[
	Which plugin settings an agent may read and change, and on what terms. The rules match the
	settings page, so an agent can do exactly what the user can do there, except switch the
	bridge itself.
]]

local Rojo = script:FindFirstAncestor("Rojo")
local Plugin = Rojo.Plugin
local Packages = Rojo.Packages

local Log = require(Packages.Log)

local Constants = require(script.Parent.Constants)
local Settings = require(Plugin.Settings)
local Version = require(Plugin.Version)

local SettingsAccess = {}

-- Internal state the settings page never shows; the sync reminder's Forget button clears it.
local HIDDEN = {
	priorEndpoints = true,
}

-- Only the user may change these, in Rojo's settings.
local USER_ONLY = {
	[Constants.ENABLED_SETTING] = true,
}

local function logLevelNames(): { string }
	local names = {}
	for name in Log.Level do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- The dropdowns on the settings page. Kept in step with App/StatusPages/Settings by hand.
local OPTIONS = {
	syncReminderMode = { "None", "Notify", "Fullscreen" },
	confirmationBehavior = { "Initial", "Always", "Large Changes", "Unlisted PlaceId", "Never" },
	logLevel = logLevelNames(),
}

-- The settings page's number field accepts whole numbers in this range.
local NUMBER_RANGES = {
	largeChangesConfirmationThreshold = { min = 1, max = 999 },
}

-- Why the settings page would refuse a change right now, if it would.
local function lockReason(name: string, context): string?
	if name == "twoWaySync" and context.syncActive then
		return "twoWaySync cannot change while syncing; disconnect first"
	end
	if name == "checkForUpdates" and Version.isApiBlocked() then
		return "checkForUpdates is locked because HTTP requests to api.github.com are blocked"
	end
	return nil
end

function SettingsAccess.isVisible(name: string): boolean
	return Settings._values[name] ~= nil and not HIDDEN[name]
end

-- Every visible setting with its value and what the agent may set it to.
function SettingsAccess.describe(context)
	local settings, details = {}, {}
	for name, value in Settings._values do
		if HIDDEN[name] then
			continue
		end
		settings[name] = value
		details[name] = {
			type = typeof(value),
			options = OPTIONS[name],
			range = NUMBER_RANGES[name],
			userOnly = if USER_ONLY[name] then true else nil,
			lockedReason = lockReason(name, context),
		}
	end
	return settings, details
end

--[[
	Checks a change the agent asked for. Returns the value to store, or nil and the reason the
	change is refused.
]]
function SettingsAccess.validate(name: any, value: any, context): (any, string?)
	if type(name) ~= "string" or not SettingsAccess.isVisible(name) then
		return nil, "unknown setting; call getSettings for the list"
	end
	if USER_ONLY[name] then
		return nil, name .. " can only be changed by the user, in Rojo's settings"
	end

	local current = Settings._values[name]
	if typeof(value) ~= typeof(current) then
		return nil, string.format("%s expects a %s", name, typeof(current))
	end

	local options = OPTIONS[name]
	if options and table.find(options, value) == nil then
		return nil, string.format("%s must be one of: %s", name, table.concat(options, ", "))
	end

	local range = NUMBER_RANGES[name]
	if range then
		if value ~= math.floor(value) then
			return nil, name .. " expects a whole number"
		end
		value = math.clamp(value, range.min, range.max)
	end

	local reason = lockReason(name, context)
	if reason then
		return nil, reason
	end

	return value, nil
end

return SettingsAccess
