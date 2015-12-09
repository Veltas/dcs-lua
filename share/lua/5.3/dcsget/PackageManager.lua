local json = require("dkjson")
local lfs = require("lfs")

-- Try{someFunction}(arg1, arg2) is equivalent to pcall(someFunction, arg1, arg2)
-- FIXME Try is broken
local Try = {}
do
	local TryMt = {}
	setmetatable(Try, TryMt)
	
	function TryMt.__call(_, ...)
		local protected = {}
		local protectedMt = {}
		setmetatable(protected, protectedMt)
		
		local sugarTable = ...
		local functionToCall = sugarTable[1]
		
		function protectedMt.__call(_, ...)
			return pcall(functionToCall, ...)
		end
		
		return protected
	end
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
		local entryPath = targetDir.."/"..dirEntry
		local outputPath = outputDir.."/"..dirEntry
		-- Ignore implicit directories
		if dirEntry ~= "." and dirEntry ~= ".." then
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
end

-- This class structures the package data nicely
local PackageData = {}

function PackageData.new(installDir)
	local packageData = {}
	
	-- The loaded structure containing the JSON file's data
	local loadedPackages = {}
	do
		local packagesFile = io.input(installDir .. "/packages.json")
		local packagesJson = packagesFile:read("*all")
		loadedPackages = json.decode(packagesJson)
		if not loadedPackages then
			error("Failed to read json file from " .. installDir .. "/packages.json")
		end
	end
	
	-- Generic-for iterator for package names
	function packageData.names()
		local loadedIterator, state, currentName = pairs(loadedPackages)
		local function iterator(state, currentName)
			local newName, _ = loadedIterator(state, currentName)
			return newName
		end
		return iterator, state, currentName
	end
	
	-- Returns whether a package name refers to an actual package or not
	function packageData.isPackage(packageName)
		if loadedPackages[packageName] then
			return true
		else
			return false
		end
	end
	
	-- Generic-for iterator for versions of a package (in order)
	function packageData.versions(packageName)
		local versionsIterator, state, currentIndex = ipairs(loadedPackages[packageName].version)
		local function iterator()
			local newIndex, versionString = versionsIterator(state, currentIndex)
			currentIndex = newIndex
			return versionString
		end
		return iterator
	end
	
	-- Generic-for iterator for dependencies of a package
	-- Returned iterator gives name then version
	function packageData.dependencies(packageName)
		local dependenciesTable = loadedPackages[packageName].dependencies or {}
		
		local dependenciesIterator, state, currentIndex = ipairs(dependenciesTable)
		
		local function iterator()
			local newIndex, dependencyRecord = dependenciesIterator(state, currentIndex)
			currentIndex = newIndex
			if dependencyRecord == nil then
				return nil, nil
			end
			return dependencyRecord[1], dependencyRecord[2]
		end
		
		return iterator
	end
	
	-- Returns "" if no entry
	-- Return type as a string
	function packageData.type(packageName)
		return loadedPackages[packageName].type or ""
	end
	
	-- Returns "" if no entry
	-- Return description as a string
	function packageData.description(packageName)
		return loadedPackages[packageName].description or ""
	end
	
	-- Generates string of formatted info about a package given its name
	function packageData.longDescription(packageName)
		-- Build string of versions
		local versionString = loadedPackages[packageName].version[1]
		if #loadedPackages[packageName].version > 1 then
			versionString = versionString .. " (default)"
			for i = 2, #loadedPackages[packageName].version do
				versionString = versionString .. ", " .. loadedPackages[packageName].version[i]
			end
		end
		
		-- Return string with name, description, and versions
		return packageName .. " - " .. loadedPackages[packageName].description .. " - Versions: " .. versionString
	end
	
	return packageData
end

local PackageManager = {}

function PackageManager.new(installDir, baseUrl)
	-- Inherit from PackageData
	local packageManager = PackageData.new(installDir)
	
	-- Check if a package is installed, returns false if not installed or if not a loaded package
	local function isInstalled(package, version)
		if isMode(installDir .. "/" .. package .. "-" .. version, "directory") then
			-- Check directory entry corresponds to a legit package
			for checkVersion in packageManager.versions(package) do
				if checkVersion == version then
					return true
				end
			end
		end
		return false
	end
	
	-- Checks if a package is listed as manually requested
	function packageManager.isRequested(package, version)
		os.execute("touch " .. installDir .. "/requested")
		local requestedFile = io.input(installDir .. "/requested")
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
	local function setRequested(package, version, newRequestedState)
		-- Is already requested?
		if packageManager.isRequested(package, version) then
			if not newRequestedState then
				-- Collect lines that aren't the package
				os.execute("touch " .. installDir .. "/requested")
				local requestedFile = io.input(installDir .. "/requested")
				local requestedFileLines = {}
				for line in requestedFile:lines() do
					if line ~= package .. "-" .. version then
						requestedFileLines:insert(line)
					end
				end
				requestedFile:close()
				
				-- Write ammended list
				local requestedFile = io.output(installDir .. "/requested")
				for _, line in ipairs(requestedFile) do
					requestedFile:write(line .. "\n")
				end
				requestedFile:close()
			end
		
		-- Not already requested
		else
			if newRequestedState then
				-- Write package to end of file
				os.execute("touch " .. installDir .. "/requested")
				local requestedFile = io.open(installDir .. "/requested", "a")
				requestedFile:write(package .. "-" .. version .. "\n")
				requestedFile:close()
			end
		end
	end
	
	-- Get package name and version from versioned string
	local function splitVersionedName(versionedPackage)
		local i = 0
		while versionedPackage:find("-.+$", i + 1) do
			i = versionedPackage:find("-.+$", i + 1)
			local package = versionedPackage:sub(1, i - 1)
			local version = versionedPackage:sub(i + 1)
			if packageManager.isPackage(package) then
				for allowedVersion in packageManager.versions(package) do
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
	function packageManager.installed()
		local directoryIterator, state, currentEntry = lfs.dir(installDir)
		
		local function iterator(state, entry)
			local dirEntry
			repeat
				dirEntry = directoryIterator(state, entry)
				if dirEntry and isMode(installDir .. "/" .. dirEntry, "directory") then
					local package, version = splitVersionedName(dirEntry)
					if package then
						return package, version
					end
				end
			until not dirEntry
			
			return nil, nil
		end
		
		return iterator, state
	end
	
	-- Lists packages matching a list of search strings
	function packageManager.listMatched(searchStrings)
		local results = {}
		
		-- Check for matches from all packages
		for package in packageManager.names() do
			-- Search for matches in the long description of the package
			local packageDesc = (packageManager.longDescription(package)):lower()
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
	function packageManager.generateSymlinks(versionedPackage)
		-- Confirm directory exists
		if not isMode(installDir .. "/" .. versionedPackage, "directory") then
			error("Can't access directory " .. installDir .. "/" .. versionedPackage)
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
			local fromPath = installDir .. "/" .. versionedPackage .. "/" .. from
			local toPath = installDir .. "/" .. to
			if isMode(fromPath, "directory") then
				symlinkMirror(toPath, fromPath)
			end
		end
		
		print("Links generated for " .. versionedPackage)
	end
	
	-- Gets a complete list of dependencies (root dependencies first)
	-- First call does not need currentList, currentSet or loopSet arguments
	local function dependenciesList(package, version, currentList, currentSet, loopSet)
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
		
		if not packageManager.isPackage(package) then
			error("Searching for dependencies of non-existant package " .. package)
		end
		
		-- Add on dependencies first
		for dependencyName, dependencyVersion in packageManager.dependencies(package) do
			dependenciesList(dependencyName, dependencyVersion, currentList, currentSet)
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
	local function install(package, version)
		local versionedPackage = package .. "-" .. version
		
		if packageManager.type(package) ~= "meta" then
			-- Download the package .tar.gz
			local packageTar = versionedPackage .. ".tar.gz"
			local downloadUrl = baseUrl .. "/packages/" .. packageTar
			local downloadedFile = installDir .. "/downloaded/" .. packageTar
			print("Downloading | " .. versionedPackage)
			if not os.execute("curl --progress-bar " .. downloadUrl .. " > " .. downloadedFile) then
				error("Failed to download package " .. versionedPackage)
			end
			
			-- Now extract the .tar.gz
			print("Installing  | " .. versionedPackage)
			if not os.execute("tar --extract --directory=" .. installDir .. " --file=" .. downloadedFile) then
				error("Failed to install package " .. versionedPackage)
			end
		end
		
		-- And we should be done
		print("-- Finished | " .. versionedPackage .. " --")
	end
	
	-- Require a package is installed (or reinstalled)
	-- mode is either "install" or "reinstall"
	function packageManager.request(mode, package, version)
		-- In many places the package is referred to as "package-version"
		local versionedPackage = package .. "-" .. version
		
		-- Set requested state
		setRequested(package, version, true)
		
		-- Only doing something if reinstalling or not already installed
		if mode == "reinstall" or not isInstalled(package, version) then
			-- Get list of dependencies
			-- Okay actually fix me this time
			--[[
			local success, dependencies = Try{dependenciesList}(package, version)
			if not success then
				local errorMessage = dependencies
				print(errorMessage)
				print("FAILED to install " .. package)
				return
			end
			--]]
			local dependencies = dependenciesList(package, version)
			
			-- Install all dependencies and then the package
			for _, dependency in ipairs(dependencies) do
				local dependencyName = dependency[1]
				local dependencyVersion = dependency[2]
				if not packageManager.isPackage(dependencyName) then
					error("Dependency " .. dependencyName .. " of package " .. package .. " does not exist")
				end
				if not isInstalled(dependencyName, dependencyVersion) or mode == "reinstall" then
					install(dependencyName, dependencyVersion)
				end
			end
		end
	end
	
	function packageManager.update()
		local downloadUrl = baseUrl .. "/packages.json"
		local downloadedFile = installDir .. "/packages.json"
		if not os.execute("curl --silent " .. downloadUrl .. " > " .. downloadedFile) then
			error("Failed to download packages.json")
		end
	end
	
	function packageManager.clean()
		os.execute(installDir .. "/cleanup")
	end
	
	return packageManager
end

return PackageManager
