local lfs = require "lfs"
local dcsget = require "dcsget"
local PackageData = require "dcsget.PackageData"

-- Checks file mode ("directory", "file", etc.)
local function isMode(path, mode)
	local attr = lfs.attributes(path)
	if not attr then
		return false
	end
	return attr.mode == mode
end

-- Same as isMode but detects symlinks ("link")
local function isLinkMode(path, mode)
	local attr = lfs.symlinkattributes(path)
	if not attr then
		return false
	end
	return attr.mode == mode
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

local PackageManager = {}

function PackageManager.new(installDir, baseUrl)
	local packageManager = dcsget.inherit(PackageData.new(installDir), PackageManager)

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
			symlinkMirror(toPath, fromPath)
		end
	end

	print("Links generated for " .. versionedPackage)
end

-- Gets a complete list of dependencies (root dependencies first)
-- First call does not need list or inList arguments
function PackageManager:dependenciesList(package, version, list, inList)
	if not self:isPackage(package) then
		error("Dependency search reached non-existant package " .. package)
	end

	list = list or {}
	inList = inList or {}
	inList[package] = inList[package] or {}

	if not inList[package][version] then
		inList[package][version] = true

		for dependencyName, dependencyVersion in self:dependencies(package) do
			self:dependenciesList(dependencyName, dependencyVersion, list, inList)
		end

		table.insert(list, {package, version})
	end

	return list
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
		if not os.execute("curl --fail --progress-bar " .. downloadUrl .. " > " .. downloadedFile) then
			error("Failed to download package " .. versionedPackage)
		end

		-- Now extract the .tar.gz
		print("Installing  | " .. versionedPackage)
		if not os.execute("tar --extract --directory=" .. self.installDir .. " --file=" .. downloadedFile .. " 2> /dev/null") then
			error("Failed to install package " .. versionedPackage)
		end
	end

	-- And we should be done
	print("-- Finished | " .. versionedPackage .. " --")
end

-- Require a package is installed (or reinstalled)
-- mode is either "install" or "reinstall"
function PackageManager:request(mode, package, version)
	if mode == "reinstall" or not self:isInstalled(package, version) then
		-- Get list of dependencies
		local dependencies = self:dependenciesList(package, version)

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

	self:setRequested(package, version, true)
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
