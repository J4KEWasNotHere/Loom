--[[
	package-utils.lua

	Small, dependency-free helpers for working with package names and
	the install queue. Split out of plugin-basis.lua so pages can share
	them without pulling in Fusion/UI code.
]]

local PackageUtils = {}

-- Splits "scope/package@version" (or any partial form of it) into its
-- three components. Mirrors the parsing wally-search.lua does for
-- dependency specifiers, but is kept local here so pages don't need to
-- pull in the whole search module just to parse a name.
function PackageUtils.splitName(name: string): (string?, string, string?)
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

-- Shallow-copies the install queue into fresh entry tables (carrying over
-- the existing per-entry Fusion Value reference used by the "include
-- dependencies" checkbox) so callers can mutate/remove entries without
-- touching the previous snapshot.
function PackageUtils.cloneQueue(queue)
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
			-- Carries a pre-resolved install (found already on disk via
			-- package_instancer.findInstalled) through queue mutations so
			-- InstallService can link it instead of re-downloading.
			reference = entry.reference,
			existingSource = entry.existingSource,
			realm = entry.realm,
		})
	end
	return copy
end

-- Builds the label shown for a queued/searched package, e.g. "foo/bar @1.2.3"
function PackageUtils.makeEntryLabel(entry): string
	local label = entry.raw or ""
	if entry.version and entry.version ~= "" then
		label = label .. " @" .. entry.version
	end
	return label
end

return PackageUtils
