local json = require "dkjson"
local lfs = require "lfs"

-- Creates table copied from entries of given tables
local function inherit(...)
	local childTable = {}
	for _, parentTable in ipairs{...} do
		for k, v in pairs(parentTable) do
			childTable[k] = v
		end
	end
	return childTable
end

-- Return file/dir mode "file", "directory", etc. (follows symlinks)
-- Returns nil on access error (file not exist, no permission, ...)
local function isMode(path, mode)
	local attr = lfs.attributes(path)
	if attr then
		return attr.mode == mode
	else
		return false
	end
end

-- Return file/dir mode, can detect a symlink ("link")
local function isLinkMode(path, mode)
	local attr = lfs.symlinkattributes(path)
	if attr then
		return attr.mode == mode
	else
		return false
	end
end

-- Mirrors a directory structure using symlinks (symbolic links)
local function symlinkMirror(outputDir, targetDir)
	-- Check output path exists
	if not lfs.attributes(outputDir) then
		-- If not then create it
		if not lfs.mkdir(outputDir) then
			error("Unable to use/create output symlink dir " .. outputDir)
		end
	end

	-- Link files, recursively link directories (but not symlink directories)
	for dirEntry in lfs.dir(targetDir) do
		-- Ignore implicits
		if dirEntry == "." or dirEntry == ".." then
			break
		end

		local entryPath = targetDir.."/"..dirEntry
		local outputPath = outputDir.."/"..dirEntry
		-- Symlinks and regular files get symlinked
		if isLinkMode(entryPath, "link") or isLinkMode(entryPath, "file") then
			if not os.execute("ln --symbolic --relative " .. entryPath .. " " .. outputPath) then
				print("dcs-get: Failed to create symlink at " .. outputPath)
			end
		-- Directories are called recursively
		elseif isMode(entryPath, "directory") then
			symlinkMirror(outputPath, entryPath)
		end
	end
end

-- This class structures the package data nicely
local PackageData = {}

function PackageData.new(installDir)
	local packageData = inherit(PackageData)

	-- Prepare packageData.loadedPackages from packages.json
	do
		local packagesFile = io.input(installDir .. "/packages.json")
		local packagesJson = packagesFile:read("*all")
		packageData.loadedPackages = json.decode(packagesJson)
		if not packageData.loadedPackages then
			error("Failed to read json file from " .. installDir .. "/packages.json")
		end
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

local PackageManager = {}

function PackageManager.new(installDir, baseUrl)
	local packageManager = inherit(PackageData.new(installDir), PackageManager)

	packageManager.installDir = installDir
	packageManager.baseUrl = baseUrl

	return packageManager
end

-- Check if a package is installed, returns false if not installed or if not a loaded package
function PackageManager:isInstalled(package, version)
	if isMode(self.installDir .. "/" .. package .. "-" .. version, "directory") then
		-- Check directory entry corresponds to a legit package
		for checkVersion in self:versions(package) do
			if checkVersion == version then
				return true
			end
		end
	end
	return false
end

-- Checks if a package is listed as manually requested
function PackageManager:isRequested(package, version)
	os.execute("touch " .. self.installDir .. "/requested")
	local requestedFile = io.input(self.installDir .. "/requested")
	if not requestedFile then
		return false
	end
	local line = requestedFile:read("*line")
	while line do
		if line == package .. "-" .. version then
			requestedFile:close()
			return true
		end
		line = requestedFile:read("*line")
	end
	requestedFile:close()
	return false
end

-- Adds a package to the list of manually requested packages
function PackageManager:setRequested(package, version, newRequestedState)
	-- Is already requested?
	if self:isRequested(package, version) then
		if not newRequestedState then
			-- Collect lines that aren't the package
			os.execute("touch " .. self.installDir .. "/requested")
			local requestedFile = io.input(self.installDir .. "/requested")
			local requestedFileLines = {}
			for line in requestedFile:lines() do
				if line ~= package .. "-" .. version then
					requestedFileLines:insert(line)
				end
			end
			requestedFile:close()

			-- Write ammended list
			requestedFile = io.output(self.installDir .. "/requested")
			for _, line in ipairs(requestedFile) do
				requestedFile:write(line .. "\n")
			end
			requestedFile:close()
		end

	-- Not already requested
	elseif newRequestedState then
		-- Write package to end of file
		os.execute("touch " .. self.installDir .. "/requested")
		local requestedFile = io.open(self.installDir .. "/requested", "a")
		requestedFile:write(package .. "-" .. version .. "\n")
		requestedFile:close()
	end
end

-- Get package name and version from versioned string
function PackageManager:splitVersionedName(versionedPackage)
	local i = 0
	while versionedPackage:find("-.+$", i + 1) do
		i = versionedPackage:find("-.+$", i + 1)
		local package = versionedPackage:sub(1, i - 1)
		local version = versionedPackage:sub(i + 1)
		if self:isPackage(package) then
			for allowedVersion in self:versions(package) do
				if version == allowedVersion then
					return package, version
				end
			end
		end
	end
	return nil
end

-- Iterates over installed packages
-- Returned iterator gives package then version
function PackageManager:installed()
	local directoryIterator, dirState, _ = lfs.dir(self.installDir)

	local function iterator(state, entry)
		local dirEntry
		repeat
			dirEntry = directoryIterator(state, entry)
			if dirEntry and isMode(self.installDir .. "/" .. dirEntry, "directory") then
				local package, version = self:splitVersionedName(dirEntry)
				if package then
					return package, version
				end
			end
		until not dirEntry

		return nil, nil
	end

	return iterator, dirState
end

-- Lists packages matching a list of search strings
function PackageManager:listMatched(searchStrings)
	local results = {}

	-- Check for matches from all packages
	for package in self:names() do
		-- Search for matches in the long description of the package
		local packageDesc = (self:longDescription(package)):lower()
		local failed = false

		-- Ensure all search strings match
		for _, searchString in ipairs(searchStrings) do
			if not failed then
				failed = not packageDesc:find(searchString:lower())
			end
		end

		-- If all strings matched, add to results
		if not failed then
			table.insert(results, package)
		end
	end

	return results
end

-- Implementation of the getsymlinks mode: mirrors appropriate directories
function PackageManager:generateSymlinks(versionedPackage)
	-- Confirm directory exists
	if not isMode(self.installDir .. "/" .. versionedPackage, "directory") then
		error("Can't access directory " .. self.installDir .. "/" .. versionedPackage)
	end

	-- Symlink appropriate sections
	local linksToMake = {
		["bin"] = "bin",
		["share"] = "share", -- FIXME breaks manpages bookkeeping file
		["include"] = "include",
		["lib"] = "lib64",
		["lib64"] = "lib64",
		["lib32"] = "lib"
	}
	for from, to in pairs(linksToMake) do
		local fromPath = self.installDir .. "/" .. versionedPackage .. "/" .. from
		local toPath = self.installDir .. "/" .. to
		if isMode(fromPath, "directory") then
			self:symlinkMirror(toPath, fromPath)
		end
	end

	print("Links generated for " .. versionedPackage)
end

-- Gets a complete list of dependencies (root dependencies first)
-- First call does not need currentList, currentSet or loopSet arguments
function PackageManager:dependenciesList(package, version, currentList, currentSet, loopSet)
	-- currentList stores list of package dependencies in order of want
	currentList = currentList or {}

	-- currentSet stores the packages which are already on the list
	currentSet = currentSet or {}
	currentSet[package] = currentSet[package] or {}

	-- loopSet stores the packages which have already been visited recursively
	loopSet = loopSet or {}
	loopSet[package] = loopSet[package] or {}

	-- Make sure we're not looping
	if loopSet[package][version] then
		return
	end
	loopSet[package][version] = true

	if not self:isPackage(package) then
		error("Searching for dependencies of non-existant package " .. package)
	end

	-- Add on dependencies first
	for dependencyName, dependencyVersion in self:dependencies(package) do
		self:dependenciesList(dependencyName, dependencyVersion, currentList, currentSet)
	end

	-- Then make sure that this is on the list
	if not currentSet[package][version] then
		currentSet[package][version] = true
		table.insert(currentList, {package, version})
	end

	return currentList
end

-- Given an existing package and version will download and extract files, installing the package
-- Doesn't download or extract anything if a meta package is given
function PackageManager:install(package, version)
	local versionedPackage = package .. "-" .. version

	if self:type(package) ~= "meta" then
		-- Download the package .tar.gz
		local packageTar = versionedPackage .. ".tar.gz"
		local downloadUrl = self.baseUrl .. "/packages/" .. packageTar
		local downloadedFile = self.installDir .. "/downloaded/" .. packageTar
		print("Downloading | " .. versionedPackage)
		if not os.execute("curl --progress-bar " .. downloadUrl .. " > " .. downloadedFile) then
			error("Failed to download package " .. versionedPackage)
		end

		-- Now extract the .tar.gz
		print("Installing  | " .. versionedPackage)
		if not os.execute("tar --extract --directory=" .. self.installDir .. " --file=" .. downloadedFile) then
			error("Failed to install package " .. versionedPackage)
		end
	end

	-- And we should be done
	print("-- Finished | " .. versionedPackage .. " --")
end

-- Require a package is installed (or reinstalled)
-- mode is either "install" or "reinstall"
function PackageManager:request(mode, package, version)
	-- Set requested state
	self:setRequested(package, version, true)

	-- Only doing something if reinstalling or not already installed
	if mode == "reinstall" or not self:isInstalled(package, version) then
		-- Get list of dependencies
		local dependencies
		xpcall(function ()
			dependencies = self:dependenciesList(package, version)
		end, function (errorMessage)
			print(errorMessage)
			print("FAILED to install " .. package)
			return
		end)

		-- Install all dependencies and then the package
		for _, dependency in ipairs(dependencies) do
			local dependencyName = dependency[1]
			local dependencyVersion = dependency[2]
			if not self:isPackage(dependencyName) then
				error("Dependency " .. dependencyName .. " of package " .. package .. " does not exist")
			end
			if not self:isInstalled(dependencyName, dependencyVersion) or mode == "reinstall" then
				self:install(dependencyName, dependencyVersion)
			end
		end
	end
end

function PackageManager:update()
	local downloadUrl = self.baseUrl .. "/packages.json"
	local downloadedFile = self.installDir .. "/packages.json"
	if not os.execute("curl --silent " .. downloadUrl .. " > " .. downloadedFile) then
		error("Failed to download packages.json")
	end
end

function PackageManager:clean()
	os.execute(self.installDir .. "/cleanup")
end

return PackageManager