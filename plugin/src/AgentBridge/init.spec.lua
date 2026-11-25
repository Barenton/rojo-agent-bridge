return function()
	local Rojo = script:FindFirstAncestor("Rojo")
	local Plugin = Rojo.Plugin

	local PatchSet = require(Plugin.PatchSet)
	local ServeSession = require(Plugin.ServeSession)
	local Settings = require(Plugin.Settings)
	local Version = require(Plugin.Version)

	local AgentBridge = require(script.Parent)

	-- Just enough of the App for the bridge to drive: its state, its address fields and the
	-- methods the bridge calls.
	local function createFakeApp()
		local app = {
			state = {
				appStatus = "NotConnected",
				guiEnabled = false,
				notifications = {},
			},
			host = "",
			port = "",
			announced = {},
			sessionsStarted = 0,
			choices = {},
		}

		function app:setState(partial)
			if type(partial) == "function" then
				partial = partial(self.state)
			end
			for key, value in partial do
				self.state[key] = value
			end
		end

		function app:getHostAndPort()
			return if self.host ~= "" then self.host else "localhost", if self.port ~= "" then self.port else "34872"
		end

		app.setHost = function(host)
			app.host = host
		end
		app.setPort = function(port)
			app.port = port
		end

		function app:addNotification(notification)
			table.insert(self.announced, notification.text)
		end

		function app:closeNotification(id)
			self.state.notifications[id] = nil
		end

		function app:startSession()
			self.sessionsStarted += 1
		end

		function app:endSession()
			self.serveSession = nil
			self.state.appStatus = "NotConnected"
		end

		app.confirmationBindable = {
			Fire = function(_, choice)
				table.insert(app.choices, choice)
				app.state.appStatus = if choice == "Abort" then "Error" else "Connected"
			end,
		}

		return app
	end

	local app, bridge, parent, previousApiBlocked, savedSettings

	beforeEach(function()
		previousApiBlocked = Version._apiBlocked
		Version._apiBlocked = false
		savedSettings = table.clone(Settings._values)

		parent = Instance.new("Folder")
		app = createFakeApp()
		bridge = AgentBridge.new(app, { parent = parent })
	end)

	afterEach(function()
		bridge:destroy()
		parent:Destroy()
		for name, value in savedSettings do
			if Settings._values[name] ~= value then
				Settings:set(name, value)
			end
		end
		Version._apiBlocked = previousApiBlocked
	end)

	local function invoke(action, args)
		return parent.RojoAgentBridge:Invoke(action, args)
	end

	describe("calls", function()
		it("lists every action in help", function()
			local result = invoke("help")
			expect(result.ok).to.equal(true)
			for _, name in
				{
					"status",
					"connect",
					"disconnect",
					"reconnect",
					"setEndpoint",
					"dismissError",
					"pendingChanges",
					"confirm",
					"history",
					"waitForSync",
					"getSettings",
					"setSetting",
					"showPanel",
					"notifications",
					"notificationAction",
					"dismissNotification",
					"activity",
				}
			do
				expect(result.actions[name]).to.be.ok()
			end
		end)

		it("refuses an unknown action and says what exists", function()
			local result = invoke("explode")
			expect(result.ok).to.equal(false)
			expect(result.actions.connect).to.be.ok()
		end)

		it("answers only status and help while the user has switched it off", function()
			Settings:set("agentBridgeEnabled", false)

			expect(invoke("status").ok).to.equal(true)
			local refused = invoke("showPanel", { visible = true })
			expect(refused.ok).to.equal(false)
			expect(refused.enabled).to.equal(false)
			expect(app.state.guiEnabled).to.equal(false)
		end)

		it("records what it was asked, but not reads of that record", function()
			invoke("status")
			invoke("activity")
			local activity = invoke("activity").activity
			expect(#activity).to.equal(1)
			expect(activity[1].action).to.equal("status")
		end)
	end)

	describe("settings", function()
		it("changes a setting and tells the user", function()
			local result = invoke("setSetting", { name = "playSounds", value = not Settings:get("playSounds") })
			expect(result.ok).to.equal(true)
			expect(Settings:get("playSounds")).to.equal(result.value)
			expect(#app.announced).to.equal(1)
		end)

		it("cannot switch the bridge off or on", function()
			local result = invoke("setSetting", { name = "agentBridgeEnabled", value = false })
			expect(result.ok).to.equal(false)
			expect(Settings:get("agentBridgeEnabled")).to.equal(true)
		end)

		it("cannot change two-way sync while syncing", function()
			app.serveSession = {
				getStatus = function()
					return ServeSession.Status.Connected
				end,
			}
			local result = invoke("setSetting", { name = "twoWaySync", value = not Settings:get("twoWaySync") })
			expect(result.ok).to.equal(false)
		end)
	end)

	describe("session", function()
		it("fills in the address fields without connecting", function()
			local result = invoke("setEndpoint", { host = "127.0.0.1", port = 34900 })
			expect(result.ok).to.equal(true)
			expect(app.host).to.equal("127.0.0.1")
			expect(app.port).to.equal("34900")
			expect(app.sessionsStarted).to.equal(0)
		end)

		it("does not change the address while connected", function()
			app.state.appStatus = "Connected"
			local result = invoke("setEndpoint", { port = 1 })
			expect(result.ok).to.equal(false)
			expect(app.port).to.equal("")
		end)

		it("closes the error page", function()
			app.state.appStatus = "Error"
			app.state.errorMessage = "boom"

			expect(invoke("dismissError").ok).to.equal(true)
			expect(app.state.appStatus).to.equal("NotConnected")
			expect(invoke("dismissError").ok).to.equal(false)
		end)
	end)

	describe("confirmation", function()
		local function waitForConfirmation()
			local folder = Instance.new("Folder")
			folder.Name = "Target"
			folder.Parent = parent
			local patch = PatchSet.newEmpty()
			patch.added.NEW = { Name = "New", ClassName = "Folder", Parent = "TARGET" }
			bridge:setPendingPatch(patch, { fromIds = { TARGET = folder } }, { projectName = "Demo" })
			app.state.appStatus = "Confirming"
		end

		it("says when nothing is waiting", function()
			expect(invoke("pendingChanges").ok).to.equal(false)
			expect(invoke("confirm", { choice = "Accept" }).ok).to.equal(false)
		end)

		it("describes a waiting patch and accepts it", function()
			waitForConfirmation()

			local pending = invoke("pendingChanges")
			expect(pending.ok).to.equal(true)
			expect(pending.projectName).to.equal("Demo")
			expect(pending.counts.added).to.equal(1)

			local result = invoke("confirm", { choice = "Accept", timeout = 1 })
			expect(result.ok).to.equal(true)
			expect(app.choices[1]).to.equal("Accept")
		end)

		it("only rejects with two-way sync on, as the page does", function()
			Settings:set("twoWaySync", false)
			waitForConfirmation()
			expect(invoke("confirm", { choice = "Reject" }).ok).to.equal(false)
			expect(#app.choices).to.equal(0)
		end)

		it("treats an abort as the outcome asked for", function()
			waitForConfirmation()
			local result = invoke("confirm", { choice = "Abort", timeout = 1 })
			expect(result.ok).to.equal(true)
			expect(result.aborted).to.equal(true)
			expect(app.state.appStatus).to.equal("NotConnected")
		end)
	end)

	describe("panel", function()
		it("opens the panel on its settings page and back", function()
			invoke("showPanel", { visible = true, page = "Settings" })
			expect(app.state.guiEnabled).to.equal(true)
			expect(app.state.appStatus).to.equal("Settings")

			invoke("showPanel", { page = "Main" })
			expect(app.state.appStatus).to.equal("NotConnected")
		end)

		it("keeps the settings page out of reach while connecting", function()
			app.state.appStatus = "Connecting"
			expect(invoke("showPanel", { page = "Settings" }).ok).to.equal(false)
		end)
	end)

	describe("notifications", function()
		local pressed, closed

		local function showReminder()
			pressed, closed = {}, 0
			local notification = {
				text = "Project 'Demo' is serving. Would you like to connect?",
				onClose = function()
					closed += 1
				end,
				actions = {
					Dismiss = { text = "Dismiss", style = "Bordered", layoutOrder = 2 },
					Connect = {
						text = "Connect",
						style = "Solid",
						layoutOrder = 1,
						onClick = function()
							table.insert(pressed, "Connect")
						end,
					},
				},
			}
			app.state.notifications[7] = notification
			bridge:recordNotification(notification, 7)
		end

		it("lists showing notifications with their buttons in order", function()
			showReminder()
			local entry = invoke("notifications").notifications[1]
			expect(entry.id).to.equal(7)
			expect(entry.showing).to.equal(true)
			expect(table.concat(entry.actions, ",")).to.equal("Connect,Dismiss")
		end)

		it("presses a button, then closes the notification", function()
			showReminder()
			local result = invoke("notificationAction", { id = 7, action = "Connect" })
			expect(result.ok).to.equal(true)
			expect(pressed[1]).to.equal("Connect")
			expect(app.state.notifications[7]).to.equal(nil)
			expect(closed).to.equal(1)
		end)

		it("refuses a button the notification does not have", function()
			showReminder()
			local result = invoke("notificationAction", { id = 7, action = "Forget" })
			expect(result.ok).to.equal(false)
			expect(#result.actions).to.equal(2)
			expect(app.state.notifications[7]).to.be.ok()
		end)

		it("dismisses a notification without pressing anything", function()
			showReminder()
			expect(invoke("dismissNotification", { id = 7 }).ok).to.equal(true)
			expect(#pressed).to.equal(0)
			expect(closed).to.equal(1)
		end)
	end)

	describe("sync history", function()
		it("keeps each applied patch with the paths it touched", function()
			local doomed = Instance.new("Folder")
			doomed.Name = "Doomed"
			doomed.Parent = parent
			local patch = PatchSet.newEmpty()
			table.insert(patch.removed, doomed)

			bridge:beforePatch(patch, { fromIds = {} })
			doomed:Destroy()
			bridge:afterPatch(patch, { fromIds = {} }, PatchSet.newEmpty())

			local history = invoke("history")
			expect(history.patchSeq).to.equal(1)
			expect(string.find(history.patches[1].removed[1].path, "Doomed", 1, true)).to.be.ok()
			expect(parent.RojoAgentBridge:GetAttribute("PatchSeq")).to.equal(1)
		end)

		it("ignores empty patches", function()
			bridge:afterPatch(PatchSet.newEmpty(), { fromIds = {} }, PatchSet.newEmpty())
			expect(invoke("history").patchSeq).to.equal(0)
		end)
	end)
end
