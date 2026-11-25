return function()
	local Rojo = script:FindFirstAncestor("Rojo")
	local Plugin = Rojo.Plugin

	local Version = require(Plugin.Version)

	local SettingsAccess = require(script.Parent.SettingsAccess)

	local IDLE = { syncActive = false }

	local previousApiBlocked
	beforeEach(function()
		-- The real check asks api.github.com; tests decide the answer instead.
		previousApiBlocked = Version._apiBlocked
		Version._apiBlocked = false
	end)
	afterEach(function()
		Version._apiBlocked = previousApiBlocked
	end)

	describe("validate", function()
		it("refuses settings that do not exist or are internal", function()
			local _, unknownReason = SettingsAccess.validate("notASetting", true, IDLE)
			expect(unknownReason).to.be.ok()

			local _, hiddenReason = SettingsAccess.validate("priorEndpoints", {}, IDLE)
			expect(hiddenReason).to.be.ok()
		end)

		it("never lets an agent change the bridge's own switch", function()
			local value, reason = SettingsAccess.validate("agentBridgeEnabled", false, IDLE)
			expect(value).to.equal(nil)
			expect(string.find(reason, "only be changed by the user", 1, true)).to.be.ok()
		end)

		it("refuses a value of the wrong type", function()
			local _, reason = SettingsAccess.validate("playSounds", "yes", IDLE)
			expect(string.find(reason, "expects a boolean", 1, true)).to.be.ok()
		end)

		it("only accepts the options the settings page offers", function()
			local _, reason = SettingsAccess.validate("confirmationBehavior", "Sometimes", IDLE)
			expect(reason).to.be.ok()

			local value = SettingsAccess.validate("confirmationBehavior", "Always", IDLE)
			expect(value).to.equal("Always")
		end)

		it("keeps the confirmation threshold to whole numbers within the page's range", function()
			local _, reason = SettingsAccess.validate("largeChangesConfirmationThreshold", 2.5, IDLE)
			expect(reason).to.be.ok()

			local value = SettingsAccess.validate("largeChangesConfirmationThreshold", 5000, IDLE)
			expect(value).to.equal(999)
		end)

		it("locks two-way sync while a session is syncing, as the page does", function()
			local _, reason = SettingsAccess.validate("twoWaySync", true, { syncActive = true })
			expect(reason).to.be.ok()

			local value = SettingsAccess.validate("twoWaySync", true, IDLE)
			expect(value).to.equal(true)
		end)

		it("locks update checks when api.github.com is blocked", function()
			Version._apiBlocked = true
			local _, reason = SettingsAccess.validate("checkForUpdates", false, IDLE)
			expect(reason).to.be.ok()
		end)
	end)

	describe("describe", function()
		it("lists every setting but the internal ones, with what they may be set to", function()
			local settings, details = SettingsAccess.describe(IDLE)

			expect(settings.priorEndpoints).to.equal(nil)
			expect(settings.agentBridgeEnabled).to.equal(true)
			expect(details.agentBridgeEnabled.userOnly).to.equal(true)
			expect(table.find(details.syncReminderMode.options, "Fullscreen")).to.be.ok()
			expect(details.largeChangesConfirmationThreshold.range.max).to.equal(999)
		end)
	end)
end
