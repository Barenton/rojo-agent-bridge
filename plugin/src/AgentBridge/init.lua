--[[
	Agent bridge: lets an automation agent operate this plugin hands-free.

	In edit mode the plugin creates a BindableFunction named "RojoAgentBridge" in CoreGui:

		local bridge = game:GetService("CoreGui"):WaitForChild("RojoAgentBridge")
		bridge:Invoke("help")
		bridge:Invoke("connect", { port = "34872", confirm = "Accept" })

	Anything the user can do in the plugin, an agent can do through an action: connect,
	confirm, disconnect, change settings, open the panel, press notification buttons. The one
	exception is the "Agent Bridge" switch in Rojo's settings, which only the user can change;
	while it is off, the bridge answers only `help` and `status`.

	Every call returns a table with `ok` and, when not ok, `error`. The bridge mirrors Status,
	ProjectName, Address, PatchSeq and Enabled in its attributes, and its child BindableEvent
	"Events" fires (name, data) for "status", "confirmation", "patch" and "notification", so
	agents can watch instead of polling.

	The App calls the hooks at the bottom of this file to keep the bridge informed.
]]

local CoreGui = game:GetService("CoreGui")

local Rojo = script:FindFirstAncestor("Rojo")
local Plugin = Rojo.Plugin

local PatchSet = require(Plugin.PatchSet)
local Settings = require(Plugin.Settings)

local Actions = require(script.Actions)
local Constants = require(script.Constants)
local PatchDescription = require(script.PatchDescription)
local Status = require(script.Status)
local Util = require(script.Util)

-- Answered even when the user has switched the bridge off, so an agent can tell why it is idle.
local ALWAYS_ALLOWED = {
	help = true,
	status = true,
}

-- Reading the activity log is not itself recorded in it.
local UNRECORDED = {
	activity = true,
	help = true,
}

local AgentBridge = {}
AgentBridge.__index = AgentBridge

--[[
	`options.parent` is where the bridge is created; CoreGui unless given, so tests can keep it
	out of the way.
]]
function AgentBridge.new(app, options: { parent: Instance? }?)
	local self = setmetatable({
		app = app,
		pendingPatch = nil,
		removedPaths = nil,
		notifications = {},
		history = {},
		activity = {},
		patchSeq = 0,
		connectedSince = nil,
		lastStatus = nil,
	}, AgentBridge)

	local parent = if options and options.parent then options.parent else CoreGui
	local existing = parent:FindFirstChild(Constants.BRIDGE_NAME)
	if existing then
		-- Left behind by an earlier copy of the plugin, for example after a reload.
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = Constants.BRIDGE_NAME
	bindable.Archivable = false

	local events = Instance.new("BindableEvent")
	events.Name = "Events"
	events.Archivable = false
	events.Parent = bindable

	bindable.OnInvoke = function(action, args)
		return self:handle(action, if type(args) == "table" then args else {})
	end
	bindable.Parent = parent

	self.bindable = bindable
	self.events = events
	self.disconnectEnabledChanged = Settings:onChanged(Constants.ENABLED_SETTING, function()
		self:syncAttributes()
	end)
	self:syncAttributes()

	return self
end

function AgentBridge:destroy()
	self.disconnectEnabledChanged()
	self.bindable:Destroy()
end

function AgentBridge:isEnabled(): boolean
	return Settings:get(Constants.ENABLED_SETTING) == true
end

function AgentBridge:handle(action: any, args: { [string]: any })
	local handler = if type(action) == "string" then Actions.handlers[action] else nil
	if handler == nil then
		return Util.fail('unknown action; call "help" for the list', { actions = Actions.help })
	end

	local result
	if not self:isEnabled() and not ALWAYS_ALLOWED[action] then
		result = Util.fail("the agent bridge is switched off in Rojo's settings", { enabled = false })
	else
		local ok, value = pcall(handler, self, args)
		result = if ok then value else Util.fail(tostring(value))
	end

	if not UNRECORDED[action] then
		Util.pushCapped(self.activity, {
			action = action,
			time = os.time(),
			ok = result.ok == true,
			error = result.error,
		}, Constants.ACTIVITY_LOG_SIZE)
	end
	return result
end

-- Each thing an agent changes is shown to the user, so the plugin never acts behind their back.
function AgentBridge:announce(text: string)
	self.app:addNotification({
		text = "Agent bridge: " .. text,
		timeout = 5,
	})
end

-- Hooks the App calls ----------------------------------------------------------------------

-- Whenever the App's state changes.
function AgentBridge:syncAttributes()
	local state = self.app.state
	local status = Status.current(self)
	local connected = status == "Connected"

	if status ~= self.lastStatus then
		self.lastStatus = status
		if connected then
			self.connectedSince = os.time()
		elseif status ~= "Confirming" and status ~= "Connecting" then
			self.connectedSince = nil
		end
		self.bindable:SetAttribute("Status", status)
		self.events:Fire("status", { status = status })
	end
	self.bindable:SetAttribute("ProjectName", if connected then state.projectName else nil)
	self.bindable:SetAttribute("Address", if connected then state.address else nil)
	self.bindable:SetAttribute("Enabled", self:isEnabled())
end

-- For every notification the App raises. `id` is nil when the user has notifications switched
-- off, since the App then shows nothing an agent could press.
function AgentBridge:recordNotification(notification, id: number?)
	local entry = { id = id, text = notification.text, time = os.time() }
	Util.pushCapped(self.notifications, entry, Constants.NOTIFICATION_LOG_SIZE)
	self.events:Fire("notification", entry)
end

-- When a patch starts waiting for confirmation.
function AgentBridge:setPendingPatch(patch, instanceMap, serverInfo)
	local pending = PatchDescription.describe(patch, instanceMap)
	pending.projectName = serverInfo.projectName
	self.pendingPatch = pending
	self.events:Fire("confirmation", {
		projectName = pending.projectName,
		added = #pending.added,
		removed = #pending.removed,
		updated = #pending.updated,
	})
end

function AgentBridge:clearPendingPatch()
	self.pendingPatch = nil
end

-- Just before a patch is applied, while the instances it removes still exist.
function AgentBridge:beforePatch(patch, instanceMap)
	self.removedPaths = PatchDescription.capturePaths(patch, instanceMap)
end

-- After a patch was applied.
function AgentBridge:afterPatch(patch, instanceMap, unappliedPatch)
	local removedPaths = self.removedPaths
	self.removedPaths = nil
	if PatchSet.isEmpty(patch) then
		return
	end

	self.patchSeq += 1
	local entry = PatchDescription.describe(patch, instanceMap, removedPaths)
	entry.seq = self.patchSeq
	entry.time = os.time()
	entry.unapplied = PatchSet.countChanges(unappliedPatch)
	Util.pushCapped(self.history, entry, Constants.HISTORY_SIZE)

	self.bindable:SetAttribute("PatchSeq", self.patchSeq)
	self.events:Fire("patch", {
		seq = entry.seq,
		added = #entry.added,
		removed = #entry.removed,
		updated = #entry.updated,
		unapplied = entry.unapplied,
	})
end

return AgentBridge
