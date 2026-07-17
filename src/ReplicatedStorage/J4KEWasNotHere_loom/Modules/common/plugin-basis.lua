local RunService = game:GetService("RunService")
local StudioService = game:GetService("StudioService")
local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function splitName(name)
	local scopePackage, version = name:match("^(.-)@(.+)$")
	if not scopePackage then
		scopePackage = name
	end
	local scope, package = scopePackage:match("^([^/]+)/([^/]+)$")
	if not scope then
		return nil, scopePackage, version
	end
	return scope, package, version
end

local function cloneQueue(queue)
	local copy = {}
	for _, entry in ipairs(queue or {}) do
		table.insert(copy, {
			raw = entry.raw or "",
			scope = entry.scope,
			package = entry.package,
			version = entry.version,
			name = entry.name or "",
			includeDependencies = entry.includeDependencies ~= false,
			_depsValue = entry._depsValue,
		})
	end
	return copy
end

local function new(className, properties)
	local ok, obj = pcall(Instance.new, className)
	if not ok then
		warn(`[instancer]: {obj}`)
		return nil
	end
	for property, value in pairs(properties) do
		local setOk, err = pcall(function()
			obj[property] = value
		end)
		if not setOk then
			warn(`[instancer]: {err}`)
		end
	end
	return obj
end

local _cs, cachedPlugin = pcall(function()
	return script.Parent:FindFirstAncestor("Modules").Parent:Clone()
end)

return {
	start = function(pluginInstance, pluginRoot, button)
		local Components = pluginRoot.Components
		local Packages = pluginRoot.Packages
		local PluginComponents = Components:FindFirstChild("PluginComponents")
		local Widget = require(PluginComponents.Widget)
		local StudioComponents = Components:FindFirstChild("StudioComponents")
		local Checkbox = require(StudioComponents.Checkbox)
		local MainButton = require(StudioComponents.MainButton)
		local ScrollFrame = require(StudioComponents.ScrollFrame)
		local Label = require(StudioComponents.Label)
		local LabelImage = require(StudioComponents.LabelImage)
		local Paragraph = require(StudioComponents.Paragraph)
		local TextInput = require(StudioComponents.TextInput)
		local VerticalExpandingList = require(StudioComponents.VerticalExpandingList)
		local VerticalCollapsibleSection = require(StudioComponents.VerticalCollapsibleSection)
		local Seperator = require(StudioComponents.Seperator)
		local Loading = require(StudioComponents.Loading)
		local Fusion = require(Packages.Fusion)
		local New = Fusion.New
		local Value = Fusion.Value
		local Children = Fusion.Children
		local OnChange = Fusion.OnChange
		local OnEvent = Fusion.OnEvent
		local Observer = Fusion.Observer
		local Computed = Fusion.Computed
		local unwrap = require(StudioComponents.Util.unwrap)

		local function makeCard(contents, y: NumberRange?)
			return New("Frame")({
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 0.7,
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BorderSizePixel = 0,
				[Children] = {
					New("UICorner")({ CornerRadius = UDim.new(0, 8) }),
					New("UIPadding")({
						PaddingLeft = UDim.new(0, 10),
						PaddingRight = UDim.new(0, 10),
						PaddingTop = UDim.new(0, 10),
						PaddingBottom = UDim.new(0, 10),
					}),
					New("UIListLayout")({
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					New("UISizeConstraint")({
						MaxSize = Vector2.new(9999, y and y.Max or 9999),
						MinSize = Vector2.new(0, y and y.Min or 0),
					}),
					table.unpack(contents),
				},
			})
		end

		local function makeSectionHeader(text)
			return Label({
				Text = text,
				TextColor3 = Color3.fromRGB(220, 220, 220),
				TextSize = 14,
			})
		end

		local function makeEntryLabel(entry)
			local label = entry.raw or ""
			if entry.version and entry.version ~= "" then
				label = label .. " @" .. entry.version
			end
			return label
		end

		local Modules = pluginRoot.Modules
		local zip_build = require(Modules.files[".zip-build"])
		local package_instancer = require(Modules.common["package-instancer"])
		local wally_search = require(Modules.external["wally-search"])
		local logger = require(Modules.common["logger"])
		local version_control = require(Modules.external["version-control"])

		local Constants = require(Modules.external.constants)

		local SettingsService = require(Modules.common["settings-service"])
		local InstallService = require(Modules.common["install-service"])

		local settingsService = SettingsService.new(pluginInstance)
		local installService = InstallService.new(settingsService)

		-- break on unsupported modes
		if RunService:IsRunMode() or RunService:IsRunning() then
			return
		end

		local StoredText = Value("")

		zip_build.bindDebugCallback(function(msg)
			logger:log(msg)
		end)

		installService:bindDebugCallback(function(msg)
			warn(msg)
			logger:log(msg)
		end)

		local widgetsEnabled = Value(false)

		local function AddWidget(name, children)
			local id = HttpService:GenerateGUID()
			return Widget({
				Id = id,
				Name = name or id,
				InitialDockTo = Enum.InitialDockState.Left,
				InitialEnabled = false,
				ForceInitialEnabled = false,
				FloatingSize = Vector2.new(280, 280),
				MinimumSize = Vector2.new(280, 240),
				Enabled = widgetsEnabled,
				[OnChange("Enabled")] = function(isEnabled)
					widgetsEnabled:set(isEnabled)
				end,
				[Children] = ScrollFrame({
					ZIndex = 1,
					Size = UDim2.fromScale(1, 1),
					CanvasScaleConstraint = Enum.ScrollingDirection.X,
					UILayout = New("UIListLayout")({
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					UIPadding = New("UIPadding")({
						PaddingLeft = UDim.new(0, 6),
						PaddingRight = UDim.new(0, 6),
						PaddingBottom = UDim.new(0, 10),
						PaddingTop = UDim.new(0, 10),
					}),
					[Children] = children,
				}),
			})
		end

		--task.delay(0.2, function()
		--	widgetsEnabled:set(true)
		--end)

		local CurrentPage = Value("Start")
		local StatusText = Value("Ready")
		local mainWidget = nil
		local IsImporting = Value(false)
		local IsInstalling = Value(false)
		local QueueEntries = Value({})
		local SettingsState = Value(settingsService:read())
		local DraftSearchText = Value("")
		local DraftSelectedVersion = Value(nil)
		local DraftOverrideName = Value("")
		local DraftIncludeDependencies = Value(settingsService:get("includeDependencies", true))
		local DraftPendingSpecifier = Value(nil)
		local DraftPackageResults = Value({})
		local DraftVersionCollapsed = Value(true)
		local DraftIsDropdownOpen = Value(false)
		local DraftIsSearching = Value(false)
		local IsVersionInstalling = Value(false)

		logger:log(`[{os.date("%H:%M:%S")}]: Started Loom!`)

		local function setPage(page)
			CurrentPage:set(tostring(page))
		end

		local function updateSettings(key, value)
			local current = settingsService:read()
			local updated = table.clone(current)
			updated[key] = value
			settingsService:write(updated)
			SettingsState:set(updated)
		end

		local function addQueuedPackage(entry)
			local queue = cloneQueue(QueueEntries:get())
			entry._depsValue = Value(entry.includeDependencies ~= nil and entry.includeDependencies == true)
			table.insert(queue, entry)
			QueueEntries:set(queue)
			StatusText:set(("Queued %s"):format(entry.raw or entry.name or "package"))
		end

		local function resetDraft()
			DraftSearchText:set("")
			DraftSelectedVersion:set(nil)
			DraftOverrideName:set("")
			DraftIncludeDependencies:set(settingsService:get("includeDependencies", true))
			DraftPackageResults:set({})
			DraftVersionCollapsed:set(true)
			DraftIsDropdownOpen:set(false)
			DraftIsSearching:set(false)
		end

		local function CreateLogger(prop: {})
			local properties = {
				Text = logger.output,
				MaxHeight = 350,
				MinHeight = 350,
			}

			for i, v in (prop) do
				properties[i] = v
			end

			return makeCard({
				Label({ Text = "Logger", TextSize = 16 }),
				Paragraph(properties),
			})
		end

		local function _CreateStoredViewer(prop: {})
			local properties = {
				Text = StoredText,
				MaxHeight = 350,
				MinHeight = 30,
			}

			for i, v in (prop) do
				properties[i] = v
			end

			return makeCard({
				Label({ Text = "Stored", TextSize = 16 }),
				Paragraph(properties),
			})
		end

		local function StartPage()
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
								local sourceFolder, initModule, wallyData, dependencies = zip_build.createFromFile(file)
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

								local realm = (wallyData.package and wallyData.package.realm) or "shared"

								-- Remove stale instances with the same name so we don't accumulate duplicates
								local origin = (realm == "server") and ServerScriptService or ReplicatedStorage
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
		local SearchQuery = nil ::string
		local SearchResults = nil :: {[string]: any}
		local function SearchRows()
			return New("Frame")({
				Size = UDim2.new(1, 0, 0, 25),
				BackgroundTransparency = .9,
				BackgroundColor3 = Color3.fromRGB(40, 41, 49),
				[Children] = {
					New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					New("TextLabel")({ --NAME
						TextXAlignment = Enum.TextXAlignment.Center,
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = "Author/Name",
						Size = UDim2.new(.2, 0, 0, 25),
						TextSize = 14,
						BackgroundTransparency = 1,
						Font = Enum.Font.SourceSans,
						TextColor3 = Color3.fromRGB(255,255,255),
						TextWrapped = true,
					}),
					
					New("TextLabel")({ --DESCRIPTION
						AutomaticSize = Enum.AutomaticSize.Y,
						TextXAlignment = Enum.TextXAlignment.Left,
						Text = "Description",
						Size = UDim2.new(.6, 0, 0, 25),
						TextSize = 14,
						BackgroundTransparency = 1,
						Font = Enum.Font.SourceSans,
						TextColor3 = Color3.fromRGB(255,255,255),
						TextWrapped = true,
					}),
				}
			})
		end
		local function CreateSearchResultRow(entry)
			return New("Frame")({
				Size = UDim2.new(1, 0, 0, 50),
				BackgroundTransparency = .9,
				BackgroundColor3 = Color3.fromRGB(0,0,0),
				[Children] = {
					New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					New("TextLabel")({ --NAME
						BackgroundColor3 = Color3.fromRGB(40, 41, 49),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = entry.scope.."/"..entry.name,
						Size = UDim2.new(.2, 0, 0, 50),
						TextSize = 14,
						BackgroundTransparency = .6,
						Font = Enum.Font.SourceSans,
						TextColor3 = Color3.fromRGB(255,255,255),
						TextWrapped = true,
					}),
					New("TextLabel")({ --DESCRIPTION
						BackgroundColor3 = Color3.fromRGB(40, 41, 49),
						AutomaticSize = Enum.AutomaticSize.Y,
						TextXAlignment = Enum.TextXAlignment.Left,
						Text = entry.description,
						Size = UDim2.new(.6, 0, 0, 50),
						TextSize = 14,
						BackgroundTransparency = .6,
						Font = Enum.Font.SourceSans,
						TextColor3 = Color3.fromRGB(255,255,255),
						TextWrapped = true,
					}),
					New("TextButton")({--ADD
						Size = UDim2.new(.18, 0, 0, 50),
						TextColor3 = Color3.fromRGB(255,255,255),
						Text = "Add",
						TextSize = 20,
						TextXAlignment = Enum.TextXAlignment.Center,
						
						BackgroundColor3 = Color3.fromRGB(51, 95, 255),
						[OnEvent "Activated"] = function()
							setPage("Queue")
							DraftSearchText:set(entry.scope.."/"..entry.name)
							if IsVersionInstalling:get() then
								return
							end
							DraftIsSearching:set(true)
							local scope, pkg = entry.scope, entry.name
							local ok, versions = wally_search.getPackageDetails(scope, pkg)
							local normalized = {}
							if ok then
								for _, versionData in pairs(versions or {}) do
									table.insert(normalized, versionData.version)
								end
								table.sort(normalized, function(a, b)
									return a > b
								end)
							end
							DraftPackageResults:set(normalized)

							local specifier = unwrap(DraftPendingSpecifier)
							local resolvedOk, resolved
							if specifier then
								resolvedOk, resolved = wally_search.resolveVersion(scope, pkg, specifier)
							end

							if resolvedOk then
								DraftSelectedVersion:set(resolved)
								DraftVersionCollapsed:set(true) -- collapse, we already picked one
								DraftIsDropdownOpen:set(#normalized > 0) -- still browsable to override
								StatusText:set(("Resolved %s to %s"):format(specifier, resolved))
							else
								DraftVersionCollapsed:set(false)
								DraftIsDropdownOpen:set(ok and #normalized > 0)
								StatusText:set(
									ok and "Versions loaded for the current package."
										or "Unable to fetch versions for the current package."
								)
							end

							DraftIsSearching:set(false)
						end,
					}),
				}
			})
		end
		local function SearchPage()
			
			local results = {}
			
			for _,v in pairs(SearchResults) do
				table.insert(results, CreateSearchResultRow(v))
			end
			return {			
				makeCard({

					
					makeSectionHeader("Results For "..SearchQuery),
					New("ImageLabel")({
						Image = "rbxassetid://110162513850955",
					}),
					SearchRows(),
					Seperator({}),
					table.unpack(results)
				})
			}
		end
			
		local function QueuePage()
			return {
				makeCard({
					makeSectionHeader("Package builder"),
					New ("Frame")({
						Size = UDim2.new(1, 0, 0, 25),
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.Y,
						LayoutOrder = 0,
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.fromScale(0, 0.5),
						[Children] = {
							New ("UIListLayout")({
								FillDirection = Enum.FillDirection.Horizontal,
								SortOrder = Enum.SortOrder.LayoutOrder,
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								Padding = UDim.new(0, 6),
							}),
							TextInput({
								Size = UDim2.new(.9, 0, 0, 25),
								Text = DraftSearchText,
								PlaceholderText = "Paste package or author/package",
								Enabled = Computed(function()
									return not unwrap(IsVersionInstalling)
								end),
								[OnChange("Text")] = function(text)
									local pastedName = text
									local key, scopePkg, specifier = text:match('^%s*([%w_%-]+)%s*=%s*"([^@"]+)@([^"]+)"')
									if scopePkg then
										pastedName = scopePkg
									end
									if key then
										local scope = scopePkg and scopePkg:match("^([^/]+)/")
										if scope then
											DraftOverrideName:set(scope .. "/" .. key)
										else
											DraftOverrideName:set(key)
										end
									end
									DraftSearchText:set(pastedName)
									DraftSelectedVersion:set(nil)
									DraftPendingSpecifier:set(specifier)
									DraftPackageResults:set({})
									DraftVersionCollapsed:set(true)
									DraftIsDropdownOpen:set(false)
								end,
							}),
							New ("ImageButton")({
								SizeConstraint = Enum.SizeConstraint.RelativeYY,
								Size = UDim2.fromOffset(25, 25),
								Image = "rbxassetid://2804603863",
								AnchorPoint = Vector2.new(1, 0.5),
								Position = UDim2.fromScale(1, 0.5),
								BackgroundTransparency = 1,
								[OnEvent("Activated")] = function()
									local query = tostring(DraftSearchText:get())
									if query == "" then
										return
									end
									local data = wally_search.SearchForPackage(query)
									if data == nil or #data == 0 then
										StatusText:set("No results found for "..query)
										return
									end
									SearchQuery = query
									SearchResults = data

									setPage("Search")
								end,
							}),
						},
					}),
					
					Seperator({}),
					MainButton({
						Text = Computed(function()
							return unwrap(DraftIsSearching) and "Searching…" or "Get versions"
						end),
						Size = UDim2.new(1, 0, 0, 34),
						Enabled = Computed(function()
							return not unwrap(DraftIsSearching) and not unwrap(IsVersionInstalling)
						end),
						Activated = function()
							if IsVersionInstalling:get() then
								return
							end
							DraftIsSearching:set(true)
							local scope, pkg = splitName(unwrap(DraftSearchText))
							local ok, versions = wally_search.getPackageDetails(scope, pkg)
							local normalized = {}
							if ok then
								for _, versionData in pairs(versions or {}) do
									table.insert(normalized, versionData.version)
								end
								table.sort(normalized, function(a, b)
									return a > b
								end)
							end
							DraftPackageResults:set(normalized)

							local specifier = unwrap(DraftPendingSpecifier)
							local resolvedOk, resolved
							if specifier then
								resolvedOk, resolved = wally_search.resolveVersion(scope, pkg, specifier)
							end

							if resolvedOk then
								DraftSelectedVersion:set(resolved)
								DraftVersionCollapsed:set(true) -- collapse, we already picked one
								DraftIsDropdownOpen:set(#normalized > 0) -- still browsable to override
								StatusText:set(("Resolved %s to %s"):format(specifier, resolved))
							else
								DraftVersionCollapsed:set(false)
								DraftIsDropdownOpen:set(ok and #normalized > 0)
								StatusText:set(
									ok and "Versions loaded for the current package."
										or "Unable to fetch versions for the current package."
								)
							end

							DraftIsSearching:set(false)
						end,
					}),
					VerticalCollapsibleSection({
						Text = Computed(function()
							local version = unwrap(DraftSelectedVersion)
							return version and ("Selected: " .. version) or "Select a version"
						end),
						Collapsed = DraftVersionCollapsed,
						Enabled = DraftIsDropdownOpen,
						[Children] = Computed(function()
							local items = {}
							for _, version in ipairs(unwrap(DraftPackageResults) or {}) do
								table.insert(
									items,
									MainButton({
										Text = version,
										Size = UDim2.new(1, 0, 0, 28),
										Activated = function()
											DraftSelectedVersion:set(version)
											DraftVersionCollapsed:set(true)
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
					TextInput({
						Text = DraftOverrideName,
						PlaceholderText = "Optional override name",
						[OnChange("Text")] = function(text)
							DraftOverrideName:set(text)
						end,
					}),
					Checkbox({
						Text = "Include dependencies",
						Value = DraftIncludeDependencies,
						Enabled = Computed(function()
							return not unwrap(IsVersionInstalling)
						end),
						OnChange = function(value)
							DraftIncludeDependencies:set(value)
						end,
					}),
					MainButton({
						Text = "Add to queue",
						Size = UDim2.new(1, 0, 0, 34),
						Enabled = Computed(function()
							return unwrap(DraftSelectedVersion) ~= nil and unwrap(DraftSearchText) ~= ""
						end),
						Activated = function()
							if IsVersionInstalling:get() then
								return
							end
							local scope, pkg = splitName(DraftSearchText:get())

							addQueuedPackage({
								raw = DraftSearchText:get(),
								scope = scope,
								package = pkg,
								version = DraftSelectedVersion:get(),
								name = DraftOverrideName:get(),
								includeDependencies = DraftIncludeDependencies:get(),
							})

							setPage("Queue")
							resetDraft()
						end,
					}),
				}),
				Seperator({}),
				makeCard({
					makeSectionHeader("Queued installs"),
					Computed(function()
						local queue = unwrap(QueueEntries)
						if #queue == 0 then
							return {
								Label({
									Text = "Your queue is empty. Add a package to begin.",
									TextColor3 = Color3.fromRGB(180, 180, 180),
								}),
							}
						end

						local items = {}
						for index, entry in ipairs(queue) do
							table.insert(
								items,
								VerticalCollapsibleSection({
									Text = makeEntryLabel(entry),
									Collapsed = Value(true),
									[Children] = {
										makeCard({
											TextInput({
												Text = entry.name or "",
												PlaceholderText = "Override name",
												[OnChange("Text")] = function(text)
													entry.name = text
												end,
											}),
											Checkbox({
												Text = "Include dependencies",
												Value = entry._depsValue,
												OnChange = function(value)
													entry.includeDependencies = value
													entry._depsValue:set(value)
												end,
											}),
											MainButton({
												Text = "Remove",
												Size = UDim2.new(1, 0, 0, 30),
												Activated = function()
													if IsVersionInstalling:get() then
														return
													end
													local updated = cloneQueue(queue)
													table.remove(updated, index)
													QueueEntries:set(updated)
												end,
											}),
										}),
									},
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
					MainButton({
						Text = Computed(function()
							return unwrap(IsInstalling) and "Installing…" or "Install all"
						end),
						Size = UDim2.new(1, 0, 0, 34),
						Enabled = Computed(function()
							return not unwrap(IsVersionInstalling)
								and not unwrap(IsInstalling)
								and not unwrap(IsImporting)
								and #unwrap(QueueEntries) > 0
						end),
						Activated = function()
							IsInstalling:set(true)
							task.spawn(function()
								ChangeHistoryService:SetWaypoint("LoomInstall0")
								local queue = cloneQueue(QueueEntries:get())
								local installedCount, failed = installService:installQueue(
									queue,
									function(step, total, label)
										StatusText:set(("Installing %d/%d: %s"):format(step, total, label))
									end
								)

								if #failed == 0 then
									StatusText:set(("Installed %d package(s) successfully."):format(installedCount))
									QueueEntries:set({})
								else
									StatusText:set(("Finished with %d failed install(s)."):format(#failed))
								end
								IsInstalling:set(false)

								ChangeHistoryService:SetWaypoint("LoomInstall1")
							end)
						end,
					}),
					Label({ Text = StatusText, TextColor3 = Color3.fromRGB(180, 240, 180) }),
					New("Frame")({
						Size = UDim2.new(1, 0, 0, 34),

						BackgroundTransparency = 1,
						[Children] = {
							Loading({ Enabled = IsInstalling }),
							New("UIListLayout")({
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								VerticalAlignment = Enum.VerticalAlignment.Center,
							}),
						},
					}),
				}),
			}
		end

		local VersionControlText = Value("Versions (Loading..)")
		local VersionControlEnabled = Value(false)

		local VersionControlVersions = Value({})
		local SelectedVCVersion = Value(nil)
		local VersionControlLoaded = Value(false)

		task.spawn(function()
			local ok, _ = version_control.rinit(3)
			if ok then
				local versions = {}
				for k in pairs(version_control.Versions) do
					table.insert(versions, k)
				end

				table.sort(versions, function(a, b)
					local function split(v): (number, number, number)
						v = tostring(v):gsub('"', "")
						local major, minor, patch = v:match("^(%d+)%.(%d+)%.(%d+)")
						return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
					end

					local aMaj, aMin, aPat = split(a)
					local bMaj, bMin, bPat = split(b)
					if aMaj ~= bMaj then
						return aMaj > bMaj
					end
					if aMin ~= bMin then
						return aMin > bMin
					end
					return aPat > bPat
				end)

				VersionControlVersions:set(versions)
				VersionControlEnabled:set(#versions > 0)
				VersionControlLoaded:set(true)
				if #versions > 0 then
					SelectedVCVersion:set(versions[1])
					VersionControlText:set((versions[1]):gsub('"', "") .. " (Latest)")
				else
					VersionControlText:set("N/A")
				end
			else
				warn("Loom failed to fetch registry, some things may not work as they should.")
				VersionControlText:set("Failed to fetch registry")
			end
		end)

		local function SettingsPage()
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
								if not unwrap(SettingsState).experimentalMode or not unwrap(SettingsState).devMode then
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
											local ok, err = version_control.recreateFromGitHub(pluginRoot, function()
												widgetsEnabled:set(false)
												task.wait()
												pcall(function()
													mainWidget.Enabled = false
												end)
											end)
											if not ok then
												warn("[VersionControl]: Failed to build from GitHub: " .. tostring(err))
												StatusText:set("Failed to build from GitHub.")
												IsVersionInstalling:set(false)
												pcall(function()
													mainWidget.Enabled = true
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
									if not ver or (ver == Constants.Version and not unwrap(SettingsState).devMode) then
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
												pluginRoot,
												function()
													widgetsEnabled:set(false)
													task.wait()
													pcall(function()
														mainWidget.Enabled = false
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

								local embedded = version_control.embed(cachedPlugin, pluginRoot, function()
									widgetsEnabled:set(false)
									task.wait()
									pcall(function()
										mainWidget.Enabled = false
									end)
								end)

								if not embedded then
									warn("[VersionControl]: Failed to reload")
									StatusText:set("Failed to reload plugin.")
									IsVersionInstalling:set(false)
									pcall(function()
										mainWidget.Enabled = true
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

		local NAV = {
			{
				page = "Start",
				icon = "rbxassetid://16898619182",
				RectSize = Vector2.new(256, 256),
				RectOffset = Vector2.new(257, 514),
				IconSize = 37,
				order = 1,
			},
			{
				page = "Queue",
				icon = "rbxassetid://16898730417",
				RectSize = Vector2.new(256, 256),
				RectOffset = Vector2.new(514, 514),
				IconSize = 37,
				order = 2,
			},
			--{
			--	page = "Managed",
			--	icon = "rbxassetid://16898730641",
			--	RectSize = Vector2.new(256, 256),
			--	RectOffset = Vector2.new(257, 0),
			--	order = 3,
			--},
			{
				page = "Settings",
				icon = "rbxassetid://16898734421",
				RectSize = Vector2.new(256, 256),
				RectOffset = Vector2.new(0, 257),
				IconSize = 37,
				order = 3,
			},
		}

		local navButtons = {}
		for _, entry in ipairs(NAV) do
			local page = entry.page
			local size = entry.IconSize or 0.85

			table.insert(
				navButtons,
				New("ImageButton")({
					LayoutOrder = entry.order,
					Size = UDim2.fromOffset(47, 47),
					Image = "",
					ImageRectSize = entry.RectSize or Vector2.zero,
					ImageRectOffset = entry.RectOffset or Vector2.zero,
					BackgroundColor3 = Computed(function()
						return unwrap(CurrentPage) == page and Color3.fromRGB(95, 120, 210)
							or Color3.fromRGB(60, 60, 60)
					end),
					[OnEvent("Activated")] = function()
						setPage(page)
					end,
					[Children] = {
						New("UICorner")({
							CornerRadius = UDim.new(1, 0),
						}),

						New("ImageLabel")({
							Size = UDim2.fromOffset(size, size),
							Image = entry.icon,
							ImageRectSize = entry.RectSize or Vector2.zero,
							ImageRectOffset = entry.RectOffset or Vector2.zero,
							Position = UDim2.fromScale(0.5, 0.5),
							AnchorPoint = Vector2.new(0.5, 0.5),
							BackgroundTransparency = 1,
							ImageColor3 = Computed(function()
								return unwrap(CurrentPage) == page and Color3.fromRGB(255, 255, 255)
									or Color3.fromRGB(152, 152, 152)
							end),
						}),
					},
				})
			)
		end

		mainWidget = AddWidget("Loom | Package Manager", {
			New("Frame")({
				Size = UDim2.fromScale(1, 0),
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 0,
				[Children] = {
					New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, 6),
					}),
					table.unpack(navButtons),
				},
			}),
			Seperator({}),
			VerticalExpandingList({
				[Children] = Computed(function()
					local page = unwrap(CurrentPage)
					if page == "Start" then
						return StartPage()
					elseif page == "Queue" then
						return QueuePage()
					elseif page == "Managed" then -- removed; problematic..
						return nil --ManagedPackagesPage()
					elseif page == "Settings" then
						return SettingsPage()
						elseif page == "Search" then
						return SearchPage()
					end
					return {}
				end, function(instances)
					for _, inst in ipairs(instances or {}) do
						if inst and inst.Destroy then
							inst:Destroy()
						end
					end
				end),
			}),
		})

		return function()
			widgetsEnabled:set(not widgetsEnabled:get(false))

			if not widgetsEnabled:get() then
				logger:clear()
				logger:log(`[{os.date("%H:%M:%S")}]: Loom closed`)
			end
		end
	end,
}
