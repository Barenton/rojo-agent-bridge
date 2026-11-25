--[[
	What the plugin and its session are doing, as agents see it, and waiting for that to change.
]]

local Rojo = script:FindFirstAncestor("Rojo")
local Plugin = Rojo.Plugin

local Config = require(Plugin.Config)
local PatchSet = require(Plugin.PatchSet)
local ServeSession = require(Plugin.ServeSession)
local Settings = require(Plugin.Settings)
local Version = require(Plugin.Version)

local Constants = require(script.Parent.Constants)
local Util = require(script.Parent.Util)

local Status = {}

--[[
	The session's status. The app also uses appStatus for the page it shows, so while the
	settings page is open the session's own state is the one to report.
]]
function Status.current(bridge): string
	local app = bridge.app
	local status = app.state.appStatus
	if status ~= "Settings" then
		return status
	end
	local session = app.serveSession
	return if session ~= nil and session:getStatus() == ServeSession.Status.Connected
		then "Connected"
		else "NotConnected"
end

function Status.isSyncActive(bridge): boolean
	local session = bridge.app.serveSession
	return session ~= nil and session:getStatus() == ServeSession.Status.Connected
end

function Status.report(bridge)
	local app = bridge.app
	local state = app.state
	local host, port = app:getHostAndPort()
	local status = Status.current(bridge)

	local liveNotifications = 0
	for _ in state.notifications or {} do
		liveNotifications += 1
	end

	local result = {
		ok = true,
		enabled = bridge:isEnabled(),
		status = status,
		host = host,
		port = port,
		twoWaySync = Settings:get("twoWaySync"),
		confirmationBehavior = Settings:get("confirmationBehavior"),
		patchSeq = bridge.patchSeq,
		liveNotifications = liveNotifications,
		panel = {
			visible = state.guiEnabled == true,
			page = if state.appStatus == "Settings" then "Settings" else "Main",
		},
		pluginVersion = Version.display(Config.version),
		bridgeVersion = Constants.BRIDGE_VERSION,
	}

	if status == "Connected" then
		result.projectName = state.projectName
		result.address = state.address
		result.connectedSince = bridge.connectedSince
		local session = app.serveSession
		if session ~= nil then
			result.syncedInstances = session.__instanceMap:size()
		end
		local patchData = state.patchData
		if patchData then
			result.lastSync = {
				time = patchData.timestamp,
				changes = PatchSet.countChanges(patchData.patch),
				unapplied = PatchSet.countChanges(patchData.unapplied),
			}
		end
	elseif status == "Connecting" then
		result.connectingText = state.connectingText
	elseif status == "Error" then
		result.errorMessage = state.errorMessage
	elseif status == "Confirming" and bridge.pendingPatch then
		local pending = bridge.pendingPatch
		result.pendingPatch = {
			projectName = pending.projectName,
			added = #pending.added,
			removed = #pending.removed,
			updated = #pending.updated,
		}
	end

	return result
end

-- Polls until `isDone` returns true or the timeout passes.
function Status.waitUntil(isDone: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if isDone() then
			return true
		end
		task.wait(0.1)
	end
	return isDone()
end

function Status.waitFor(bridge, isSettled: (status: string) -> boolean, timeout: number): boolean
	return Status.waitUntil(function()
		return isSettled(Status.current(bridge))
	end, timeout)
end

-- The status after an operation, marked as failed if it timed out or ended in an error.
function Status.outcome(bridge, settled: boolean, timeout: number)
	local result = Status.report(bridge)
	if not settled then
		return Util.fail(string.format("timed out after %d seconds", timeout), result)
	elseif result.status == "Error" then
		return Util.fail(result.errorMessage or "session failed", result)
	end
	return result
end

return Status
