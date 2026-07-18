--[[
	QueuePage.lua

	Lets the user paste/search a package spec, pick a version, and queue
	it for install; also renders the current queue with per-entry
	overrides and the "Install all" action.
]]

return function(ctx)
	local Computed = ctx.fusion.Computed
	local unwrap = ctx.fusion.unwrap
	local Value = ctx.fusion.Value
	local Children = ctx.fusion.Children
	local OnChange = ctx.fusion.OnChange

	local New = ctx.fusion.New
	local Label = ctx.components.Label
	local MainButton = ctx.components.MainButton
	local TextInput = ctx.components.TextInput
	local Checkbox = ctx.components.Checkbox
	local Seperator = ctx.components.Seperator
	local Loading = ctx.components.Loading
	local VerticalCollapsibleSection = ctx.components.VerticalCollapsibleSection

	local makeCard = ctx.ui.makeCard
	local makeSectionHeader = ctx.ui.makeSectionHeader

	local wally_search = ctx.modules.wally_search

	local splitName = ctx.utils.splitName
	local cloneQueue = ctx.utils.cloneQueue
	local makeEntryLabel = ctx.utils.makeEntryLabel

	local IsVersionInstalling = ctx.state.IsVersionInstalling
	local DraftSearchText = ctx.state.DraftSearchText
	local DraftSelectedVersion = ctx.state.DraftSelectedVersion
	local DraftOverrideName = ctx.state.DraftOverrideName
	local DraftIncludeDependencies = ctx.state.DraftIncludeDependencies
	local DraftPendingSpecifier = ctx.state.DraftPendingSpecifier
	local DraftPackageResults = ctx.state.DraftPackageResults
	local DraftVersionCollapsed = ctx.state.DraftVersionCollapsed
	local DraftIsDropdownOpen = ctx.state.DraftIsDropdownOpen
	local DraftIsSearching = ctx.state.DraftIsSearching
	local QueueEntries = ctx.state.QueueEntries
	local StatusText = ctx.state.StatusText
	local IsInstalling = ctx.state.IsInstalling
	local IsImporting = ctx.state.IsImporting

	local setPage = ctx.actions.setPage
	local addQueuedPackage = ctx.actions.addQueuedPackage
	local resetDraft = ctx.actions.resetDraft
	local installService = ctx.pluginServices.installService

	local ChangeHistoryService = ctx.services.ChangeHistoryService

	return {
		makeCard({
			makeSectionHeader("Package builder"),
			TextInput({
				Text = DraftSearchText,
				PlaceholderText = "Paste package or author/package",
				Enabled = Computed(function()
					return not unwrap(IsVersionInstalling)
				end),
				[OnChange("Text")] = function(text)
					local pastedName = text
					local key, scopePkg, specifier =
						text:match('^%s*([%w_%-]+)%s*=%s*"([^@"]+)@([^"]+)"')
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
