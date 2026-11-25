--[[
	Starting and ending sync sessions: the Connect page, the Disconnect button and the error page.
]]

local Rojo = script:FindFirstAncestor("Rojo")
local Plugin = Rojo.Plugin
local AgentBridge = script.Parent.Parent

local Assets = require(Plugin.Assets)

local Confirmation = require(script.Parent.Confirmation)
local Constants = require(AgentBridge.Constants)
local Status = require(AgentBridge.Status)
local Util = require(AgentBridge.Util)

-- The pages on which the user can still type an address.
local EDITABLE_ADDRESS = {
	NotConnected = true,
	Error = true,
}

-- Leaves the error page as its Close button does, so the plugin is ready to connect again.
local function leaveErrorPage(bridge)
	local app = bridge.app
	if app.state.appStatus == "Error" then
		app:setState({
			appStatus = "NotConnected",
			toolbarIcon = Assets.Images.PluginButton,
		})
	end
end

local function readEndpoint(args): (string?, string?)
	local host = if type(args.host) == "string" and args.host ~= "" then args.host else nil
	local port = if args.port ~= nil then tostring(args.port) else nil
	return host, port
end

local actions = {}

actions.connect = {
	help = '{ host?, port?, timeout?, confirm? } start a session; confirm = "Accept" | "Abort" answers a confirmation right away',
	run = function(bridge, args)
		local app = bridge.app
		local wantedHost, wantedPort = readEndpoint(args)
		local timeout = Util.numberOr(args.timeout, Constants.DEFAULT_TIMEOUT)
		if args.confirm ~= nil and args.confirm ~= "Accept" and args.confirm ~= "Abort" then
			return Util.fail('confirm must be "Accept" or "Abort"')
		end

		local status = Status.current(bridge)
		if status == "Connected" then
			local host, port = app:getHostAndPort()
			if (wantedHost == nil or wantedHost == host) and (wantedPort == nil or wantedPort == port) then
				return Status.report(bridge)
			end
			app:endSession()
		end

		local result
		if status == "Connecting" or status == "Confirming" then
			result = Status.report(bridge)
		else
			leaveErrorPage(bridge)
			if wantedHost ~= nil then
				app.setHost(wantedHost)
			end
			if wantedPort ~= nil then
				app.setPort(wantedPort)
			end

			-- startSession reports its progress through appStatus. That may still read
			-- NotConnected for a moment, so wait for Connecting first, then for its outcome.
			local sawConnecting = false
			app:startSession()
			local settled = Status.waitFor(bridge, function(current)
				if current == "Connecting" then
					sawConnecting = true
					return false
				end
				if current == "Connected" or current == "Confirming" then
					return true
				end
				-- NotConnected or Error only count once the attempt has started, unless
				-- startSession failed before creating a session (the sync lock is taken).
				return sawConnecting or app.serveSession == nil
			end, timeout)
			result = Status.outcome(bridge, settled, timeout)
		end

		if result.status == "Confirming" and args.confirm ~= nil then
			return Confirmation.confirm.run(bridge, { choice = args.confirm, timeout = timeout })
		end
		if result.ok and result.status == "Connected" then
			bridge:announce(string.format("an agent connected to '%s'.", tostring(result.projectName)))
		end
		return result
	end,
}

actions.disconnect = {
	help = "end the session, whatever state it is in",
	run = function(bridge, _args)
		local app = bridge.app
		local wasActive = app.serveSession ~= nil
		if Status.current(bridge) == "Confirming" then
			-- The session is parked on the confirmation; aborting is how it ends.
			app.confirmationBindable:Fire("Abort")
			Status.waitFor(bridge, function(current)
				return current ~= "Confirming"
			end, Constants.DEFAULT_TIMEOUT)
		end

		app:endSession()
		leaveErrorPage(bridge)
		if wasActive then
			bridge:announce("an agent disconnected the session.")
		end

		local result = Status.report(bridge)
		result.wasConnected = wasActive
		return result
	end,
}

actions.reconnect = {
	help = "{ timeout?, confirm? } disconnect, then connect to the same address",
	run = function(bridge, args)
		local host, port = bridge.app:getHostAndPort()
		actions.disconnect.run(bridge, {})
		return actions.connect.run(bridge, {
			host = host,
			port = port,
			timeout = args.timeout,
			confirm = args.confirm,
		})
	end,
}

actions.setEndpoint = {
	help = "{ host?, port? } fill in the address fields on the Connect page without connecting",
	run = function(bridge, args)
		local app = bridge.app
		local host, port = readEndpoint(args)
		if host == nil and port == nil then
			return Util.fail("give a host, a port or both")
		end
		local status = Status.current(bridge)
		if not EDITABLE_ADDRESS[status] then
			return Util.fail("the address cannot change while " .. status, Status.report(bridge))
		end
		if host ~= nil then
			app.setHost(host)
		end
		if port ~= nil then
			app.setPort(port)
		end
		return Status.report(bridge)
	end,
}

actions.dismissError = {
	help = "close the error page, as its Close button does",
	run = function(bridge, _args)
		if bridge.app.state.appStatus ~= "Error" then
			return Util.fail("no error is showing", Status.report(bridge))
		end
		leaveErrorPage(bridge)
		return Status.report(bridge)
	end,
}

return actions
