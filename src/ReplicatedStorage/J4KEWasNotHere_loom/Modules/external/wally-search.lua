--!native

local HttpService = game:GetService("HttpService")

local PackageDetailsUrl = "https://api.wally.run/v1/package-metadata/%s/%s"
local PackageZipUrl = "https://api.wally.run/v1/package-contents/%s/%s/%s"
local PackageSearchUrl = "https://api.wally.run/v1/package-search?query=%s"

local UpgradedWallyVersions = {
	"0.3.2",
	"0.3.1",
	"0.3.0",
	"0.2.1",
	"0.1.3",
}

local WallySearch = {}

local CachedDetailSearches = {}
local CachedRawZips = {}
local rawZipsOrder = {}
local workingWallyVersion = nil

local Constants = require(script.Parent.constants)
local MAX_CACHED_ZIPS = Constants.MaxCachedZips

-- Utility



local function requestWithVersionProbe(url)
	local versionsToTry = if workingWallyVersion then { workingWallyVersion } else UpgradedWallyVersions

	local lastOk, lastResponse = false, nil
	for _, ver in versionsToTry do
		local ok, response = pcall(function()
			return HttpService:RequestAsync({
				Url = url,
				Method = "GET",
				Headers = {
					["Wally-Version"] = ver,
				},
			})
		end)

		if ok and response.StatusCode ~= 426 then
			workingWallyVersion = ver
			return true, response
		end

		lastOk, lastResponse = ok, response
	end

	workingWallyVersion = nil
	return lastOk, lastResponse
end

local function addToZip(raw, scope, package, version)
	MAX_CACHED_ZIPS = Constants.MaxCachedZips
	if not raw or #tostring(raw) <= 3 then
		return
	end
	local id = scope .. "/" .. package .. "/" .. version

	if CachedRawZips[id] then
		local index = table.find(rawZipsOrder, id)
		if index then
			table.remove(rawZipsOrder, index)
		end
	else
		CachedRawZips[id] = raw
	end

	table.insert(rawZipsOrder, id)

	while #rawZipsOrder > MAX_CACHED_ZIPS do
		local oldest = table.remove(rawZipsOrder, 1)
		CachedRawZips[oldest] = nil
	end
end

-- Semver requirement resolution ---------------------------------------------

local function parseVersion(v)
	v = tostring(v):gsub('^"(.*)"$', "%1")
	local major, minor, patch = v:match("^(%d+)%.(%d+)%.(%d+)")
	if major then
		return tonumber(major), tonumber(minor), tonumber(patch)
	end
	major, minor = v:match("^(%d+)%.(%d+)$")
	if major then
		return tonumber(major), tonumber(minor), 0
	end
	major = v:match("^(%d+)$")
	if major then
		return tonumber(major), 0, 0
	end
	return nil
end

local function tuple(a, b, c)
	return a * 1000000 + b * 1000 + c
end

local function compareVersions(a, b)
	local aMaj, aMin, aPat = parseVersion(a)
	local bMaj, bMin, bPat = parseVersion(b)
	local av = tuple(aMaj or 0, aMin or 0, aPat or 0)
	local bv = tuple(bMaj or 0, bMin or 0, bPat or 0)
	if av > bv then
		return 1
	elseif av < bv then
		return -1
	end
	return 0
end

-- Parses a Cargo/npm-style requirement. A bare version ("1.2.0") defaults
-- to caret behavior, matching Wally's documented default.
local function parseRequirement(spec)
	spec = tostring(spec):gsub("^%s+", ""):gsub("%s+$", "")

	local op, verPart = spec:match("^(%^)(.+)$")
	if not op then
		op, verPart = spec:match("^(=)(.+)$")
	end
	if not op then
		op, verPart = "^", spec
	end

	local major, minor, patch = parseVersion(verPart)
	if not major then
		return nil
	end

	if op == "=" then
		return "exact", major, minor, patch
	end

	local upMajor, upMinor, upPatch
	if major > 0 then
		upMajor, upMinor, upPatch = major + 1, 0, 0
	elseif minor > 0 then
		upMajor, upMinor, upPatch = 0, minor + 1, 0
	else
		upMajor, upMinor, upPatch = 0, 0, patch + 1
	end

	return "caret", major, minor, patch, upMajor, upMinor, upPatch
end

local function satisfies(version, requirement)
	local kind, loMaj, loMin, loPat, upMaj, upMin, upPat = parseRequirement(requirement)
	if not kind then
		return false
	end

	local maj, min, pat = parseVersion(version)
	if not maj then
		return false
	end

	if kind == "exact" then
		return maj == loMaj and min == loMin and pat == loPat
	end

	local v = tuple(maj, min, pat)
	local lo = tuple(loMaj, loMin, loPat)
	local up = tuple(upMaj, upMin, upPat)
	return v >= lo and v < up
end

-- Splits "scope/package@spec" (as found in wally.toml dependency values)
-- into scope, package, versionSpec.
function WallySearch.splitSpecifier(name)
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

-- Resolves a requirement (e.g. "^1", "1.2.0", "=1.2.0") against the
-- registry's published versions and returns the highest match.
function WallySearch.resolveVersion(scope, package, requirement): (boolean, string?)
	local ok, _, indexed = WallySearch.getPackageDetails(scope, package)
	if not ok then
		return false, `Could not fetch versions for {scope}/{package}`
	end

	local best = nil
	for _, ver in ipairs(indexed) do
		if satisfies(ver, requirement) then
			if not best or compareVersions(ver, best) > 0 then
				best = ver
			end
		end
	end

	if not best then
		return false, `No version of {scope}/{package} satisfies "{requirement}"`
	end

	return true, best
end

-- Module API

function WallySearch.SearchForPackage(query)
	local url = PackageSearchUrl:format(query)
	local success, response = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if not success then
		return nil
	end
	if success then
		local data = HttpService:JSONDecode(response)
		if #data == 0 then
			return nil
		end
		return data
	else
		return {}
	end
end


function WallySearch.getPackageDetails(scope, package): (boolean, { [string]: any }?)
	if not scope or not package then
		return false, "Invalid scope or package", {}
	end
	local indexed = {}
	if not HttpService.HttpEnabled then
		return false, "Http not enabled.", indexed
	end
	local id = scope .. "/" .. package
	if CachedDetailSearches[id] then
		return true, CachedDetailSearches[id], indexed
	end

	local versions = nil

	local success, response = requestWithVersionProbe(PackageDetailsUrl:format(scope, package))
	local ok = success and response.Success == true and response.StatusCode == 200
	if ok then
		local data = HttpService:JSONDecode(response.Body)
		versions = {}
		for index, versionData in data.versions do
			local data = versionData.package
			local description = data.description
			local license = data.license
			local name = data.name
			local ver = data.version
			versions[ver] = {
				["description"] = description,
				["license"] = license,
				["name"] = name,
				["version"] = ver,
			}
			table.insert(indexed, ver)
		end
		CachedDetailSearches[scope .. "/" .. package] = versions
		return true, versions, indexed
	else
		return false, if success then response.Body else response, indexed
	end
end

function WallySearch.getPackageZipRaw(scope, package, version): (boolean, string)
	if not scope or not package then
		return false, "Invalid scope or package", {}
	end
	if not HttpService.HttpEnabled then
		return false, "Http not enabled."
	end
	local id = scope .. "/" .. package .. "/" .. version
	if CachedRawZips[id] then
		local index = table.find(rawZipsOrder, id)
		if index then
			table.remove(rawZipsOrder, index)
			table.insert(rawZipsOrder, id)
		end
		return true, CachedRawZips[id]
	end
	local success0, response = requestWithVersionProbe(PackageZipUrl:format(scope, package, version))
	local success = success0 and response.Success == true and response.StatusCode == 200
	if success then
		addToZip(response.Body, scope, package, version)
		return true, response.Body
	end
	return false, response
end

return WallySearch