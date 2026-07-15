export type VersionData = { ref: string }
export type VersionReferences = { [string]: File }

export type RegistryContent = {
	details: { name: string, description: string },
	versions: { [any]: VersionData },
	[string]: any,
}

export type VersionControl = {
	__index: VersionControl,

	-- Variables/Stored

	RegContent: RegistryContent,
	Versions: VersionReferences,

	-- Functions
	embed: (newPlugin: Instance, pluginRoot: Instance, cleanup: (() -> ())?) -> (boolean, any),

	init: () -> (boolean, { [string]: any }? | any),
	rinit: (max: number?) -> (boolean, { [string]: any }? | any),

	install: (version: string?) -> (boolean, any),
	rinstall: (version: string?, max: number?) -> (boolean, any),

	sortVersions: (VersionReferences) -> { string },
	waitFor: (timeout: number, func: (...any) -> ...any, ...any) -> ...any,
}

return {}
