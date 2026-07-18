local module = {
	Version = ".git",
	VersionTip = " (dev)",

	MaxCachedZips = 2 ^ 3,

	Licenses = {
		-- Permissive
		["mit"] = { link = "https://choosealicense.com/licenses/mit/" },
		["apache-2.0"] = { link = "https://choosealicense.com/licenses/apache-2.0/" },
		["bsd-2-clause"] = { link = "https://choosealicense.com/licenses/bsd-2-clause/" },
		["bsd-3-clause"] = { link = "https://choosealicense.com/licenses/bsd-3-clause/" },
		["isc"] = { link = "https://choosealicense.com/licenses/isc/" },
		["unlicense"] = { link = "https://choosealicense.com/licenses/unlicense/" },
		["wtfpl"] = { link = "https://choosealicense.com/licenses/wtfpl/" },
		["cc0-1.0"] = { link = "https://choosealicense.com/licenses/cc0-1.0/" },
		["zlib"] = { link = "https://choosealicense.com/licenses/zlib/" },
		["0bsd"] = { link = "https://choosealicense.com/licenses/0bsd/" },

		-- Weak copyleft
		["lgpl-2.0"] = { link = "https://choosealicense.com/licenses/lgpl-2.1/" }, -- closest available
		["lgpl-2.1"] = { link = "https://choosealicense.com/licenses/lgpl-2.1/" },
		["lgpl-3.0"] = { link = "https://choosealicense.com/licenses/lgpl-3.0/" },
		["mpl-2.0"] = { link = "https://choosealicense.com/licenses/mpl-2.0/" },
		["eupl-1.2"] = { link = "https://opensource.org/license/eupl-1-2" },

		-- Strong copyleft
		["gpl-2.0"] = { link = "https://choosealicense.com/licenses/gpl-2.0/" },
		["gpl-3.0"] = { link = "https://choosealicense.com/licenses/gpl-3.0/" },
		["agpl-3.0"] = { link = "https://choosealicense.com/licenses/agpl-3.0/" },
		["osl-3.0"] = { link = "https://opensource.org/license/osl-3-0-php" },

		-- Proprietary / restrictive
		["proprietary"] = { link = "https://en.wikipedia.org/wiki/Proprietary_software" },
		["all-rights-reserved"] = { link = "https://en.wikipedia.org/wiki/All_rights_reserved" },

		-- Creative Commons
		["cc-by-4.0"] = { link = "https://creativecommons.org/licenses/by/4.0/" },
		["cc-by-sa-4.0"] = { link = "https://creativecommons.org/licenses/by-sa/4.0/" },
		["cc-by-nc-4.0"] = { link = "https://creativecommons.org/licenses/by-nc/4.0/" },
		["cc-by-nc-sa-4.0"] = { link = "https://creativecommons.org/licenses/by-nc-sa/4.0/" },
		["cc-by-nd-4.0"] = { link = "https://creativecommons.org/licenses/by-nd/4.0/" },
		["cc-by-nc-nd-4.0"] = { link = "https://creativecommons.org/licenses/by-nc-nd/4.0/" },
	},

	-- Licenses that trigger a warning due to copyleft, NC, or proprietary restrictions.
	TriggerLicenses = {
		["lgpl-2.0"] = true,
		["lgpl-2.1"] = true,
		["lgpl-3.0"] = true,
		["mpl-2.0"] = true,
		["eupl-1.2"] = true,
		["gpl-2.0"] = true,
		["gpl-3.0"] = true,
		["agpl-3.0"] = true,
		["osl-3.0"] = true,
		["proprietary"] = true,
		["all-rights-reserved"] = true,
		["cc-by-nc-4.0"] = true,
		["cc-by-nc-sa-4.0"] = true,
		["cc-by-nc-nd-4.0"] = true,
		["cc-by-nd-4.0"] = true,
		["cc-by-sa-4.0"] = true,
	},
}

function module.warnForLicense(license, name: string)
	if not license or license == "" then
		return
	end
	license = (tostring(license or ""):lower()):gsub("%s+", "")
	if module.TriggerLicenses[license] then
		local link = module.Licenses[license].link
		warn(
			`[License]: {name or "Resource?"} uses a license that may be very restrictive, ( {link} )`
		)
	elseif not module.Licenses[license] then
		warn(`[License-Unknown] Unknown license: {license}`)
	end
end

return module
