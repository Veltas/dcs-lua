local json = require "dkjson"
local dcsget = require "dcsget"

-- This class structures the package data nicely
local PackageData = {}

function PackageData.new(installDir)
	local packageData = dcsget.inherit(PackageData)

	-- Prepare packageData.loadedPackages from packages.json
	local packagesFile = io.input(installDir .. "/packages.json")
	local packagesJson = packagesFile:read("*all")

	packageData.loadedPackages = json.decode(packagesJson)
	if not packageData.loadedPackages then
		error("Failed reading json file " .. installDir .. "/packages.json")
	end

	return packageData
end

-- Generic-for iterator for package names
function PackageData:names()
	local pairsIterator, pairsState, pairsValue = pairs(self.loadedPackages)
	local function iterator(state, currentName)
		local newName, _ = pairsIterator(state, currentName)
		return newName
	end
	return iterator, pairsState, pairsValue
end

-- Returns whether a package name refers to an actual package or not
function PackageData:isPackage(packageName)
	return self.loadedPackages[packageName]
end

-- Generic-for iterator for versions of a package (in order)
function PackageData:versions(packageName)
	local packageVersions = self.loadedPackages[packageName].version
	local versionsIterator, state, currentIndex = ipairs(packageVersions)
	local function iterator()
		local newIndex, versionString = versionsIterator(state, currentIndex)
		currentIndex = newIndex
		return versionString
	end
	return iterator
end

-- Generic-for iterator for dependencies of a package
-- Returned iterator gives name then version
function PackageData:dependencies(packageName)
	local dependenciesTable = self.loadedPackages[packageName].dependencies or {}

	local dependenciesIterator, state, currentIndex = ipairs(dependenciesTable)

	local function iterator()
		local newIndex, dependencyRecord = dependenciesIterator(state, currentIndex)
		currentIndex = newIndex
		if dependencyRecord then
			return dependencyRecord[1], dependencyRecord[2]
		end
	end

	return iterator
end

-- Returns "" if no entry
-- Return type as a string
function PackageData:type(packageName)
	return self.loadedPackages[packageName].type or ""
end

-- Returns "" if no entry
-- Return description as a string
function PackageData:description(packageName)
	return self.loadedPackages[packageName].description or ""
end

-- Generates string of formatted info about a package given its name
function PackageData:longDescription(packageName)
	local versions = self.loadedPackages[packageName].version

	-- Build string of versions
	local versionString = versions[1]
	if #versions > 1 then
		versionString = versionString .. " (default)"
		for i = 2, #versions do
			versionString = versionString .. ", " .. versions[i]
		end
	end

	-- Return string with name, description, and versions
	local description = self.loadedPackages[packageName].description
	return packageName .. " - " .. description .. " - Versions: " .. versionString
end

return PackageData
