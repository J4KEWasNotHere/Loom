--[[
	SettingsPage.lua

	Plugin preferences, the (experimental) version control browser used
	to hot-swap plugin versions, and the reload/reset actions.
]]

return function(ctx)
	local Computed = ctx.fusion.Computed
	local unwrap = ctx.fusion.unwrap
	local Value = ctx.fusion.Value
	local Children = ctx.fusion.Children

	local Label = ctx.components.Label
	local MainButton = ctx.components.MainButton
	local Checkbox = ctx.components.Checkbox
	local VerticalCollapsibleSection = ctx.components.VerticalCollapsibleSection

	local makeCard = ctx.ui.makeCard
	local makeSectionHeader = ctx.ui.makeSectionHeader

	local version_control = ctx.modules.version_control
	local Constants = ctx.modules.Constants

	local settingsService = ctx.pluginServices.settingsService

	local SettingsState = ctx.state.SettingsState
	local IsVersionInstalling = ctx.state.IsVersionInstalling
	local VersionControlText = ctx.state.VersionControlText
	local VersionControlEnabled = ctx.state.VersionControlEnabled
	local VersionControlVersions = ctx.state.VersionControlVersions
	local SelectedVCVersion = ctx.state.SelectedVCVersion
	local StatusText = ctx.state.StatusText
	local widgetsEnabled = ctx.state.widgetsEnabled

	local updateSettings = ctx.actions.updateSettings
	local widget = ctx.widget -- { instance = <mainWidget once created> }
	local cachedPlugin = ctx.cachedPlugin

	local settings = unwrap(SettingsState)

	return {
		makeCard({
			makeSectionHeader("Plugin"),
			Label({
				Text = "v" .. Constants.Version .. Constants.VersionTip,
				TextSize = 13,
			}),

			Checkbox({
				Text = "Create Package-Directors in Package.",
				Value = Value(settings.includeDirectors),
				Enabled = Computed(function()
					return not unwrap(IsVersionInstalling)
				end),
				OnChange = function(value)
					updateSettings("includeDirectors", value)
				end,
			}),

			Checkbox({
				Text = "Include Developer-Dependencies",
				Value = Value(settings.includeDev),
				Enabled = Computed(function()
					return not unwrap(IsVersionInstalling)
				end),
				OnChange = function(value)
					updateSettings("includeDev", value)
				end,
			}),

			Checkbox({
				Text = "Enable Developer Mode",
				Value = Value(settings.devMode),
				Enabled = Computed(function()
					return not unwrap(IsVersionInstalling)
				end),
				OnChange = function(value)
					updateSettings("devMode", value)
				end,
			}),

			Checkbox({
				Text = "Enable Experimental Mode",
				Value = Value(settings.experimentalMode),
				Enabled = Computed(function()
					return not unwrap(IsVersionInstalling)
				end),
				OnChange = function(value)
					updateSettings("experimentalMode", value)
				end,
			}),

			Computed(function()
				if not unwrap(SettingsState).experimentalMode then
					return nil
				end

				return makeCard({
					Label({ Text = "Version Control" }),
					makeCard({
						VerticalCollapsibleSection({
							Text = VersionControlText,
							Enabled = Computed(function()
								return unwrap(VersionControlEnabled) and not unwrap(IsVersionInstalling)
							end),
							Collapsed = Value(true),
							[Children] = Computed(function()
								local items = {}
								for _, ver in ipairs(unwrap(VersionControlVersions)) do
									ver = ver:gsub('"', "")
									local isCurrent = ver == Constants.Version

									table.insert(
										items,
										MainButton({
											Text = Computed(function()
												if isCurrent then
													return ver .. " (current)"
												end
												return ver
											end),
											Size = UDim2.new(1, 0, 0, 28),
											Enabled = Computed(function()
												return not isCurrent or unwrap(SettingsState).devMode
											end),
											Activated = function()
												SelectedVCVersion:set(ver)
												VersionControlText:set(ver .. " (Selected)")
											end,
										})
									)
								end
								return items
							end, function(instances)
								for _, inst in ipairs(instances or {}) do
									if inst and inst.Destroy then
										inst:Destroy()
									end
								end
							end),
						}),
					}),
					Computed(function()
						if
							not unwrap(SettingsState).experimentalMode
							or not unwrap(SettingsState).devMode
						then
							return nil
						end

						return MainButton({
							Text = "Build from GitHub",
							Size = UDim2.new(1, 0, 0, 30),
							Enabled = Computed(function()
								return unwrap(VersionControlEnabled)
									and unwrap(SettingsState).devMode
									and unwrap(SettingsState).experimentalMode
									and not unwrap(IsVersionInstalling)
							end),
							Activated = function()
								IsVersionInstalling:set(true)
								StatusText:set("Building from GitHub…")
								task.spawn(function()
									local ok, err = version_control.recreateFromGitHub(
										ctx.pluginRoot,
										function()
											widgetsEnabled:set(false)
											task.wait()
											pcall(function()
												widget.instance.Enabled = false
											end)
										end
									)
									if not ok then
										warn("[VersionControl]: Failed to build from GitHub: " .. tostring(err))
										StatusText:set("Failed to build from GitHub.")
										IsVersionInstalling:set(false)
										pcall(function()
											widget.instance.Enabled = true
										end)
									end
								end)
							end,
						})
					end, function(instance)
						if instance then
							instance:Destroy()
						end
					end),

					MainButton({
						Text = Computed(function()
							local ver = unwrap(SelectedVCVersion)
							if ver then
								ver = ver:gsub('"', "")
							end
							if ver and ver == Constants.Version and not unwrap(SettingsState).devMode then
								return "Already on this version"
							end
							return "Load Version"
						end),
						Size = UDim2.new(1, 0, 0, 30),
						Enabled = Computed(function()
							local ver = unwrap(SelectedVCVersion)
							if ver then
								ver = ver:gsub('"', "")
							end

							return unwrap(VersionControlEnabled)
								and ver ~= nil
								and (unwrap(SettingsState).devMode or ver ~= Constants.Version)
								and not unwrap(IsVersionInstalling)
						end),
						Activated = function()
							local ver = SelectedVCVersion:get()
							if
								not ver
								or (ver == Constants.Version and not unwrap(SettingsState).devMode)
							then
								return
							end
							IsVersionInstalling:set(true)
							StatusText:set("Installing v" .. ver .. "…")
							task.spawn(function()
								local ok, result = version_control.rinstall(ver, 3)
								if ok then
									StatusText:set("Loaded v" .. ver .. ". Reloading…")
									local embedded = version_control.waitFor(
										30,
										version_control.embed,
										result,
										ctx.pluginRoot,
										function()
											widgetsEnabled:set(false)
											task.wait()
											pcall(function()
												widget.instance.Enabled = false
											end)
										end
									)
									if not embedded then
										warn("[VersionControl]: Failed to install version")
										StatusText:set("Load succeeded but reload failed.")
										IsVersionInstalling:set(false)
									end
								else
									StatusText:set("Failed to load v" .. ver .. ".")
									warn("[VersionControl]: " .. tostring(result))
									IsVersionInstalling:set(false)
								end
							end)
						end,
					}),
				})
			end, function(instance)
				if instance then
					instance:Destroy()
				end
			end),

			Label({ Text = "Other" }),
			Computed(function()
				if not unwrap(SettingsState).experimentalMode and not unwrap(SettingsState).devMode then
					return nil
				end

				return MainButton({
					Text = "Reload Plugin",
					Size = UDim2.new(1, 0, 0, 34),
					Enabled = Computed(function()
						return not unwrap(IsVersionInstalling)
					end),
					Activated = function()
						IsVersionInstalling:set(true)
						task.wait()

						local embedded = version_control.embed(cachedPlugin, ctx.pluginRoot, function()
							widgetsEnabled:set(false)
							task.wait()
							pcall(function()
								widget.instance.Enabled = false
							end)
						end)

						if not embedded then
							warn("[VersionControl]: Failed to reload")
							StatusText:set("Failed to reload plugin.")
							IsVersionInstalling:set(false)
							pcall(function()
								widget.instance.Enabled = true
							end)
						end
					end,
				})
			end, function(instance)
				if instance then
					instance:Destroy()
				end
			end),

			MainButton({
				Text = "Reset to defaults",
				Size = UDim2.new(1, 0, 0, 34),
				Enabled = Computed(function()
					return not unwrap(IsVersionInstalling)
				end),
				Activated = function()
					settingsService:reset()
					SettingsState:set(settingsService:read())
					StatusText:set("Settings reset to defaults.")
				end,
			}),
		}),
	}
end
