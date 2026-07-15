--[[
	Check Version at Modules/external/constants
	
	Loom ( github.com/J4KEWasNotHere/Loom )
		This plugin was created by @J4KEWasNotHere on GitHub,
		more formally on Roblox as @jakeboygamer64.
	
	MPL-2.0 License (Inherited) | PRIVATE USE ONLY
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local pluginRoot = script.Parent
local toolbar = plugin:CreateToolbar("Loom")
local button = toolbar:CreateButton("Loom", "Open Loom", "rbxassetid://104838445885447")
button.ClickableWhenViewportHidden = true

local clickConnection = nil

local function relink(clickHandler)
	if clickConnection then
		clickConnection:Disconnect()
		clickConnection = nil
	end
	if clickHandler then
		clickConnection = button.Click:Connect(clickHandler)

		local unused = pluginRoot:FindFirstChild(".unused", true)
		if unused then
			unused:Destroy()
		end
	end
end

local basis = require(pluginRoot.Modules.common["plugin-basis"])
relink(basis.start(plugin, pluginRoot, button))

pluginRoot:GetAttributeChangedSignal("__needsRestart"):Connect(function()
	if pluginRoot:GetAttribute("__needsRestart") then
		pluginRoot:SetAttribute("__needsRestart", false)
		basis = require(pluginRoot.Modules.common["plugin-basis"])
		relink(basis.start(plugin, pluginRoot, button))
	end
end)

if RunService:IsStudio() and RunService:IsEdit() then
	local noHttpMsg =
		"[Loom]: run 'game.HttpService.HttpEnabled = true' in the CommandBar to allow Loom to gain access to external packages."
	HttpService:GetPropertyChangedSignal("HttpEnabled"):Connect(function()
		if not game.HttpService.HttpEnabled then
			warn(noHttpMsg)
		end
	end)
	if not game.HttpService.HttpEnabled then
		warn(noHttpMsg)
	end
end
