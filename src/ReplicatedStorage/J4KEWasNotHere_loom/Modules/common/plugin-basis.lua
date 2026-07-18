local RunService = game:GetService("RunService")
local StudioService = game:GetService("StudioService")
local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

		local Modules = pluginRoot.Modules
		local Utils = Modules.common.utils
		local Pages = Modules.common.pages

		local zip_build = require(Modules.files[".zip-build"])
		local package_instancer = require(Modules.common["package-instancer"])
		local wally_search = require(Modules.external["wally-search"])
		local logger = require(Modules.common["logger"])
		local version_control = require(Modules.external["version-control"])
		local Constants = require(Modules.external.constants)

		local SettingsService = require(Modules.common["settings-service"])
		local InstallService = require(Modules.common["install-service"])

		local PackageUtils = require(Utils["package-utils"])
		local UiUtils = require(Utils["ui-utils"])(New, Children, Label)

		local StartPage = require(Pages.StartPage)
		local QueuePage = require(Pages.QueuePage)
		local SettingsPage = require(Pages.SettingsPage)
		local SearchPage = require(Pages.SearchPage)

		local settingsService = SettingsService.new(pluginInstance)
		local installService = InstallService.new(settingsService)

		-- break on unsupported modes
		if RunService:IsRunMode() or RunService:IsRunning() then
			return
		end

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

		-- Shared reactive state. Anything a page needs to read or mutate
		-- lives here and is threaded through via `ctx` below, since pages
		-- are separate modules now and can no longer just close over
		-- upvalues the way they did as nested functions.
		local CurrentPage = Value("Start")
		local StatusText = Value("Ready")
		local widget = { instance = nil :: Instance? }
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

		-- Search page state
		local SearchQueryText = Value("")
		local SearchResults = Value({})
		local IsSearchingPackages = Value(false)
		local SearchStatusText = Value("")

		local VersionControlText = Value("Versions (Loading..)")
		local VersionControlEnabled = Value(false)
		local VersionControlVersions = Value({})
		local SelectedVCVersion = Value(nil)
		local VersionControlLoaded = Value(false)

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
			local queue = PackageUtils.cloneQueue(QueueEntries:get())
			entry._depsValue =
				Value(entry.includeDependencies ~= nil and entry.includeDependencies == true)
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

		-- Everything a page module needs, gathered in one place. `widget`
		-- is a mutable box (rather than the Instance directly) because
		-- `mainWidget` doesn't exist yet when `ctx` is built below.
		local ctx = {
			fusion = {
				New = New,
				Value = Value,
				Children = Children,
				OnChange = OnChange,
				OnEvent = OnEvent,
				Observer = Observer,
				Computed = Computed,
				unwrap = unwrap,
			},
			components = {
				Checkbox = Checkbox,
				MainButton = MainButton,
				ScrollFrame = ScrollFrame,
				Label = Label,
				LabelImage = LabelImage,
				Paragraph = Paragraph,
				TextInput = TextInput,
				VerticalExpandingList = VerticalExpandingList,
				VerticalCollapsibleSection = VerticalCollapsibleSection,
				Seperator = Seperator,
				Loading = Loading,
			},
			ui = {
				makeCard = UiUtils.makeCard,
				makeSectionHeader = UiUtils.makeSectionHeader,
			},
			modules = {
				zip_build = zip_build,
				package_instancer = package_instancer,
				wally_search = wally_search,
				logger = logger,
				version_control = version_control,
				Constants = Constants,
			},
			services = {
				ChangeHistoryService = ChangeHistoryService,
				StudioService = StudioService,
				ServerScriptService = ServerScriptService,
				ReplicatedStorage = ReplicatedStorage,
			},
			pluginServices = {
				settingsService = settingsService,
				installService = installService,
			},
			utils = {
				splitName = PackageUtils.splitName,
				cloneQueue = PackageUtils.cloneQueue,
				makeEntryLabel = PackageUtils.makeEntryLabel,
			},
			state = {
				CurrentPage = CurrentPage,
				StatusText = StatusText,
				IsImporting = IsImporting,
				IsInstalling = IsInstalling,
				QueueEntries = QueueEntries,
				SettingsState = SettingsState,
				DraftSearchText = DraftSearchText,
				DraftSelectedVersion = DraftSelectedVersion,
				DraftOverrideName = DraftOverrideName,
				DraftIncludeDependencies = DraftIncludeDependencies,
				DraftPendingSpecifier = DraftPendingSpecifier,
				DraftPackageResults = DraftPackageResults,
				DraftVersionCollapsed = DraftVersionCollapsed,
				DraftIsDropdownOpen = DraftIsDropdownOpen,
				DraftIsSearching = DraftIsSearching,
				IsVersionInstalling = IsVersionInstalling,
				SearchQueryText = SearchQueryText,
				SearchResults = SearchResults,
				IsSearchingPackages = IsSearchingPackages,
				SearchStatusText = SearchStatusText,
				VersionControlText = VersionControlText,
				VersionControlEnabled = VersionControlEnabled,
				VersionControlVersions = VersionControlVersions,
				SelectedVCVersion = SelectedVCVersion,
				VersionControlLoaded = VersionControlLoaded,
				widgetsEnabled = widgetsEnabled,
			},
			actions = {
				setPage = setPage,
				updateSettings = updateSettings,
				addQueuedPackage = addQueuedPackage,
				resetDraft = resetDraft,
			},
			widget = widget,
			cachedPlugin = cachedPlugin,
			pluginRoot = pluginRoot,
		}

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
			{
				page = "Search",
				icon = "rbxassetid://6031154871",
				order = 3,
			},
			{
				page = "Settings",
				icon = "rbxassetid://16898734421",
				RectSize = Vector2.new(256, 256),
				RectOffset = Vector2.new(0, 257),
				IconSize = 37,
				order = 4,
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

		local mainWidget = AddWidget("Loom | Package Manager", {
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
						return StartPage(ctx)
					elseif page == "Queue" then
						return QueuePage(ctx)
					elseif page == "Search" then
						return SearchPage(ctx)
					elseif page == "Settings" then
						return SettingsPage(ctx)
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

		widget.instance = mainWidget

		return function()
			widgetsEnabled:set(not widgetsEnabled:get(false))

			if not widgetsEnabled:get() then
				logger:clear()
				logger:log(`[{os.date("%H:%M:%S")}]: Loom closed`)
			end
		end
	end,
}