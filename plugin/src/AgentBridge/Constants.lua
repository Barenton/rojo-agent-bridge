--[[
	Names and limits shared by the agent bridge's modules.
]]

return {
	-- The BindableFunction agents find in CoreGui.
	BRIDGE_NAME = "RojoAgentBridge",
	-- Raised whenever an action is added or changes shape, so agents can check what they talk to.
	BRIDGE_VERSION = 5,
	-- The user's switch for the bridge. Agents can read it but never change it.
	ENABLED_SETTING = "agentBridgeEnabled",

	DEFAULT_TIMEOUT = 20,
	DEFAULT_CHANGE_LIMIT = 100,

	NOTIFICATION_LOG_SIZE = 50,
	HISTORY_SIZE = 30,
	ACTIVITY_LOG_SIZE = 50,
}
