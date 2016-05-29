local lfs = require "lfs"
local dcsget = require "dcsget"
local PackageData = require "dcsget.PackageData"

-- Checks file exists (isMode and isLinkMode already do this as well)
local function fileExists(path)
  return not not lfs.attributes(path)
end

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

-- Generates list of symlinks to make for a mirrored directory structure
local function symlinkMirrorList(outputDir, targetDir, theList)
  if not lfs.attributes(outputDir) then
    assert(lfs.mkdir(outputDir), "Unable to create dir " .. outputDir)
  end

  -- Link files, recursively link directories (but not symlink directories)
  for dirEntry in lfs.dir(targetDir) do
    if not (dirEntry == "." or dirEntry == "..") then
      local entryPath = targetDir.."/"..dirEntry
      local outputPath = outputDir.."/"..dirEntry
      -- Symlinks and regular files get symlinked
      if isLinkMode(entryPath, "link") or isLinkMode(entryPath, "file") then
        table.insert(theList, {entryPath, outputPath})
      -- Directories are called recursively
      elseif isMode(entryPath, "directory") then
        symlinkMirrorList(outputPath, entryPath, theList)
      end
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
function PackageManager:isInstalled(name, version)
  if isMode(self.installDir .. "/" .. name .. "-" .. version, "directory") then
    -- Check directory entry corresponds to a legit package
    for checkVersion in self:versions(name) do
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
          table.insert(requestedFileLines, line)
        end
      end
      requestedFile:close()

      -- Write ammended list
      requestedFile = io.output(self.installDir .. "/requested")
      for _, line in ipairs(requestedFileLines) do
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
  local mirrorList = {}
  for from, to in pairs(linksToMake) do
    local fromPath = self.installDir .. "/" .. versionedPackage .. "/" .. from
    local toPath = self.installDir .. "/" .. to
    if isMode(fromPath, "directory") then
      symlinkMirrorList(toPath, fromPath, mirrorList)
    end
  end
  for _, mirrors in ipairs(mirrorList) do
    local targetPath, outputPath = mirrors[1], mirrors[2]
    print("Linking " .. targetPath .. " to " .. outputPath)
    assert(
      os.execute("ln --symbolic --relative " .. targetPath .. " " .. outputPath),
      "dcs-get: Failed to create symlink at " .. outputPath
    )
  end

  print("Links generated for " .. versionedPackage)
end

-- Removes length of first string from beginning of second string
local function getShortPath(installDir, longPath)
  return longPath:sub(#installDir + 2, #longPath)
end

-- Implementation of package mode
function PackageManager:packagePackage(versionedPackage)
  local initialDir = lfs.currentdir()

  assert(lfs.chdir(self.installDir))

  -- Confirm directory exists
  if not isMode(self.installDir .. "/" .. versionedPackage, "directory") then
    error("Can't access directory " .. self.installDir .. "/" .. versionedPackage)
  end

  local linksToMake = {
    ["bin"] = "bin",
    ["share"] = "share",
    ["include"] = "include",
    ["lib"] = "lib64",
    ["lib64"] = "lib64",
    ["lib32"] = "lib"
  }

  -- Compile list of files from appropriate sections
  local mirrorList = {}
  for from, to in pairs(linksToMake) do
    local fromPath = self.installDir .. "/" .. versionedPackage .. "/" .. from
    local toPath = self.installDir .. "/" .. to
    if isMode(fromPath, "directory") then
      symlinkMirrorList(toPath, fromPath, mirrorList)
    end
  end

  -- Create empty tarball
  local tarball = self.installDir .. "/" .. versionedPackage .. ".tar"
  assert(os.execute("tar --create --file=" .. tarball .. " --files-from=/dev/null"))

  -- Add package files
  assert(os.execute("tar --append --file=" .. tarball .. " " .. versionedPackage .. "/"))
  for _, mirrors in ipairs(mirrorList) do
    local _, outputPath = mirrors[1], mirrors[2]
    if lfs.attributes(outputPath) then
      assert(os.execute("tar --append --file=" .. tarball .. " " .. getShortPath(self.installDir, outputPath)))
    end
  end

  lfs.chdir(initialDir)

  -- Compress tarball and save in correct place
  local targz = self.installDir .. "/downloaded/" .. versionedPackage .. ".tar.gz"
  assert(os.execute("cat " .. tarball .. " | gzip > " .. targz))

  print("Created " .. targz)
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

-- Given an existing package and version will download files
function PackageManager:download(package, version)
  local versionedPackage = package .. "-" .. version

  if self:type(package) ~= "meta" then
    local packageTar = versionedPackage .. ".tar.gz"
    local downloadUrl = self.baseUrl .. "/packages/" .. packageTar
    local downloadedFile = self.installDir .. "/downloaded/" .. packageTar
    print("Get " .. downloadUrl)
    if not os.execute("curl --fail --progress-bar " .. downloadUrl .. " > " .. downloadedFile) then
      error("Failed to download package " .. versionedPackage)
    end
  end
end

-- Given an existing package and version will extract downloaded files,
-- installing the package
function PackageManager:install(package, version)
  local versionedPackage = package .. "-" .. version

  if self:type(package) ~= "meta" then
    local packageTar = versionedPackage .. ".tar.gz"
    local downloadUrl = self.baseUrl .. "/packages/" .. packageTar
    local downloadedFile = self.installDir .. "/downloaded/" .. packageTar
    print("Installing " .. versionedPackage)
    if not os.execute("tar --extract --directory=" .. self.installDir .. " --file=" .. downloadedFile) then
      error("Failed to install package " .. versionedPackage)
    end
  end
end

local function uniqueAppend(t1, t2, t1set)
  for _, v in ipairs(t2) do
    t1set[v[1]] = t1set[v[1]] or {}
    if not t1set[v[1]][v[2]] then
      table.insert(t1, v)
      t1set[v[1]][v[2]] = true
    end
  end
end

-- Require a package is installed (or reinstalled)
-- mode is either "install" or "reinstall"
function PackageManager:request(mode, toInstall)
  local dependencies = {}
  local depSet = {}
  local depCmp = function (a, b) return a[1] == b[1] and a[2] == b[2] end
  for _, installPair in ipairs(toInstall) do
    local name, version = installPair[1], installPair[2]

    if mode == "reinstall" or not self:isInstalled(name, version) then
      -- Get list of dependencies
      uniqueAppend(dependencies, self:dependenciesList(name, version), depSet, depCmp)
    end

    self:setRequested(name, version, true)
  end

  -- Download all dependencies and package
  for _, dependency in ipairs(dependencies) do
    local dependencyName = dependency[1]
    local dependencyVersion = dependency[2]
    if not self:isPackage(dependencyName) then
      error("Dependency " .. dependencyName .. " of package " .. package .. " does not exist")
    end
    if not self:isInstalled(dependencyName, dependencyVersion) or mode == "reinstall" then
      self:download(dependencyName, dependencyVersion)
    end
  end

  -- Install all dependencies and package
  for _, dependency in ipairs(dependencies) do
    local dependencyName = dependency[1]
    local dependencyVersion = dependency[2]
    if not self:isInstalled(dependencyName, dependencyVersion) or mode == "reinstall" then
      self:install(dependencyName, dependencyVersion)
    end
  end
end

-- Gets list of the files that a package installs
function PackageManager:listFiles(package, version)
  if self:type(package) == "meta" then
    return {}
  end
  local versioned = package .. "-" .. version
  local packageFiles = {}
  local packageDl = self.installDir .. "/downloaded/" .. versioned .. ".tar.gz"
  local packageFilesTarIn = io.popen("tar tf " .. packageDl)
  for file in packageFilesTarIn:lines() do
    if not file:find("^%w*$") then
      table.insert(packageFiles, file)
    end
  end
  packageFilesTarIn:close()
  return packageFiles
end

-- Removes a package, and restores files from other packages that have been displaced
function PackageManager:uninstall(package, version)
  local versioned = package .. "-" .. version

  self:setRequested(package, version, false)

  -- List the files of package to uninstall
  local packageFiles = self:listFiles(package, version)

  -- Index owning packages of files from other installed packages
  local fileOwners = {}
  for installedPackage, installedVersion in self:installed() do
    local installedVersioned = installedPackage .. "-" .. installedVersion
    if installedVersioned ~= versioned then
      local idealFiles = self:listFiles(installedPackage, installedVersion)
      for _, idealFile in ipairs(idealFiles) do
        fileOwners[idealFile] = installedVersioned
      end
    end
  end

  -- Remove/replace package's files, list directories to remove
  local terminalDirectories = {}
  for _, file in ipairs(packageFiles) do
    local fullPath = self.installDir .. "/" .. file
    if isLinkMode(fullPath, "directory") then
      table.insert(terminalDirectories, fullPath)
    elseif fileExists(fullPath) then
      assert(os.execute("rm " .. fullPath), "Failed to remove " .. file)
      if fileOwners[file] then
        io.stdout:write("Restoring " .. file .. " from " .. fileOwners[file] .. "\n")
        local dlFile = self.installDir .. "/downloaded/" .. fileOwners[file] .. ".tar.gz"
        if not os.execute("tar --extract --directory=" .. self.installDir .. " --file=" .. dlFile .. " " .. file) then
          io.stderr:write("FAILED to write " .. file .. " ... submit an issue!\n")
        end
      end
    end
  end

  -- Remove empty directories of package
  table.sort(terminalDirectories, function (a, b) return a > b end)
  for _, dir in ipairs(terminalDirectories) do
    os.execute("rmdir " .. dir .. " 2>/dev/null")
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
