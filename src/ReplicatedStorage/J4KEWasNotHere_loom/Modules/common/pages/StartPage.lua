--[[
	StartPage.lua

	The landing page: initialize package folders, import packages from a
	.zip archive, and (in dev mode) show the debug logger card.

	Called fresh every time the user navigates to the "Start" page, same
	as the inline function it was extracted from - `ctx` carries every
	dependency (Fusion primitives, components, services, shared state)
	that used to be an upvalue inside plugin-basis.lua.
]]

return function(ctx)
	local Computed = ctx.fusion.Computed
	local unwrap = ctx.fusion.unwrap

	local Label = ctx.components.Label
	local LabelImage = ctx.components.LabelImage
	local MainButton = ctx.components.MainButton
	local Paragraph = ctx.components.Paragraph

	local makeCard = ctx.ui.makeCard

	local zip_build = ctx.modules.zip_build
	local package_instancer = ctx.modules.package_instancer
	local logger = ctx.modules.logger

	local ChangeHistoryService = ctx.services.ChangeHistoryService
	local StudioService = ctx.services.StudioService
	local ServerScriptService = ctx.services.ServerScriptService
	local ReplicatedStorage = ctx.services.ReplicatedStorage

	local settingsService = ctx.pluginServices.settingsService
	local installService = ctx.pluginServices.installService

	local IsVersionInstalling = ctx.state.IsVersionInstalling
	local IsImporting = ctx.state.IsImporting
	local IsInstalling = ctx.state.IsInstalling
	local StatusText = ctx.state.StatusText
	local SettingsState = ctx.state.SettingsState

	local function CreateLogger(prop: {})
		local properties = {
			Text = logger.output,
			MaxHeight = 350,
			MinHeight = 350,
		}

		for i, v in prop do
			properties[i] = v
		end

		return makeCard({
			Label({ Text = "Logger", TextSize = 16 }),
			Paragraph(properties),
		})
	end

	return {
		makeCard({
			Label({ Text = "Loom Package Manager", TextSize = 18 }),
			Label({
				Text = "Install and manage Wally packages directly from Studio.",
				TextSize = 12,
				TextColor3 = Color3.fromRGB(180, 180, 180),
			}),
			LabelImage({
				Size = UDim2.new(1, 0, 0, 90),
				Image = "rbxassetid://110162513850955",
				BackgroundTransparency = 1,
			}),
			MainButton({
				Text = "Initialize package folders",
				Size = UDim2.new(1, 0, 0, 34),
				Enabled = Computed(function()
					return not unwrap(IsVersionInstalling)
				end),
				Activated = function()
					if IsVersionInstalling:get() then
						return
					end
					ChangeHistoryService:SetWaypoint("LoomInit0")
					package_instancer.createPackages("Packages", true)
					package_instancer.createPackages("Packages", false)
					package_instancer.createPackages("DevPackages", "dev")
					ChangeHistoryService:SetWaypoint("LoomInit1")

					StatusText:set("Package folders initialized.")
				end,
			}),
			MainButton({
				Text = "Import packages (.zip)",
				Size = UDim2.new(1, 0, 0, 34),
				Enabled = Computed(function()
					return not unwrap(IsImporting)
						and not unwrap(IsInstalling)
						and not unwrap(IsVersionInstalling)
				end),
				Activated = function()
					if IsImporting:get() then
						return
					end
					IsImporting:set(true)
					IsInstalling:set(true)

					StatusText:set("Waiting for package archives…")
					local ok, files = pcall(function()
						return StudioService:PromptImportFilesAsync({ "zip" })
					end)
					if not ok or not files or #files == 0 then
						StatusText:set("No archives selected.")
						IsImporting:set(false)
						IsInstalling:set(false)
						return
					end

					ChangeHistoryService:SetWaypoint("LoomImport0")

					local importedCount = 0
					local failedNames = {}

					for _, file in ipairs(files) do
						StatusText:set(("Importing %s…"):format(file.Name))
						local sourceFolder, initModule, wallyData, dependencies =
							zip_build.createFromFile(file)
						if not wallyData then
							table.insert(failedNames, file.Name)
							logger:log(
								`[{os.date("%H:%M:%S")}]: wally.toml, not found in {file.Name}, is this a wally package?`
							)
							if sourceFolder then
								sourceFolder:Destroy()
							end
							continue
						end

						local realm = (wallyData.package and wallyData.package.realm)
							or "shared"

						-- Remove stale instances with the same name so we don't accumulate duplicates
						local origin = (realm == "server") and ServerScriptService
							or ReplicatedStorage
						local folderName = (realm == "dev") and "DevPackages" or "Packages"
						local packagesRoot = origin:FindFirstChild(folderName)

						if packagesRoot and sourceFolder then
							local staleAlias = packagesRoot:FindFirstChild(sourceFolder.Name)
							if staleAlias then
								staleAlias:Destroy()
							end
							local indexFolder = packagesRoot:FindFirstChild("_Index")
							if indexFolder then
								local staleIndex = indexFolder:FindFirstChild(sourceFolder.Name)
								if staleIndex then
									staleIndex:Destroy()
								end
							end
						end

						local importedModule = package_instancer.syncPackage(realm, {
							source = sourceFolder,
							reference = initModule,
							unpackSrc = settingsService:get("unpackSrc", true),
							wally = wallyData,
						})

						if not importedModule then
							table.insert(failedNames, file.Name)
							if sourceFolder then
								sourceFolder:Destroy()
							end
							continue
						end

						local depCount, depFailed = 0, {}
						if dependencies and #dependencies > 0 then
							StatusText:set("Installing Dependencies..")

							depCount, depFailed = installService:installDependencies(
								dependencies,
								{ unpackSrc = settingsService:get("unpackSrc", true) },
								function(step, total, label)
									StatusText:set(("Installing %d/%d: %s"):format(step, total, label))
								end
							)

							importedCount += depCount

							for _, name in ipairs(depFailed) do
								table.insert(failedNames, name)
							end
						end

						importedCount += 1
					end

					if #failedNames == 0 then
						StatusText:set(("Imported %d archive(s) successfully."):format(importedCount))
					elseif importedCount == 0 then
						StatusText:set("Import failed for all selected archives.")
					else
						StatusText:set(
							("Imported %d archive(s), %d failed (%s)."):format(
								importedCount,
								#failedNames,
								table.concat(failedNames, ", ")
							)
						)
					end

					IsImporting:set(false)
					IsInstalling:set(false)
					ChangeHistoryService:SetWaypoint("LoomImport1")
				end,
			}),
			Label({ Text = StatusText, TextColor3 = Color3.fromRGB(180, 240, 180) }),
		}),

		Computed(function()
			if not unwrap(SettingsState).devMode then
				return nil
			end
			return CreateLogger({})
		end, function(instance)
			if instance then
				instance:Destroy()
			end
		end),
	}
end
