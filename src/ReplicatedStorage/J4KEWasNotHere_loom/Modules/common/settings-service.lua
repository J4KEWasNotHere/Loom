local PluginSettingsService = {}
PluginSettingsService.__index = PluginSettingsService

local DEFAULT_SETTINGS = {
	unpackSrc = true,
	devMode = false,
	experimentalMode = false,
	includeDev = false,
	includeDirectors = true
}

function PluginSettingsService.new(pluginInstance)
	local self = setmetatable({
		_store = {},
		_prefix = "J4KEWasNotHere_loom",
		_plugin = pluginInstance,
	}, PluginSettingsService)

	if not pluginInstance then
		warn("[Loom-Settings]: No plugin instance provided — settings will NOT persist across sessions.")
	end

	if pluginInstance then
		for key in pairs(DEFAULT_SETTINGS) do
			local full = ("%s.%s"):format(self._prefix, key)
			local ok, v = pcall(pluginInstance.GetSetting, pluginInstance, full)
			if not ok then
				warn(`[Loom-Settings]: GetSetting failed for "{key}": {v}`)
			elseif v ~= nil then
				self._store[key] = v
			end
		end
	end
	return self
end

function PluginSettingsService:set(key, value)
	self._store[key] = value
	if self._plugin then
		local full = ("%s.%s"):format(self._prefix, key)
		local ok, err = pcall(self._plugin.SetSetting, self._plugin, full, value)
		if not ok then
			warn(`[Loom-Settings]: SetSetting failed for "{key}": {err}`)
		end
	end
end

function PluginSettingsService:get(key, fallback)
	local value = self._store[key]
	if value == nil then
		return fallback
	end
	return value
end

function PluginSettingsService:read()
	local settings = {}
	for key, defaultValue in pairs(DEFAULT_SETTINGS) do
		settings[key] = self:get(key, defaultValue)
	end
	return settings
end

function PluginSettingsService:write(settings)
	for key, value in pairs(settings) do
		self:set(key, value)
	end
end

function PluginSettingsService:reset()
	for key, value in pairs(DEFAULT_SETTINGS) do
		self:set(key, value)
	end
end

function PluginSettingsService:getDefaultSettings()
	local cloned = {}
	for key, value in pairs(DEFAULT_SETTINGS) do
		cloned[key] = value
	end
	return cloned
end

return PluginSettingsService