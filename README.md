# dcs-lua
Replacement for dcs-get main executable in Lua (in dev)

Status
------

Test version that mostly works. Missing package, upload and uninstall modes.

Package should be ready for dcs-get now under the name `dcs-lua`

A little elaboration
--------------------

I started with the idea "hey, I reckon I could rewrite dcs-get's main executable":

* In a language that isn't PHP
* Shorter and sweeter (a lot of clutter in original dcs-get)
* In a way that is easier for future compsoc to maintain and extend

While working on it I realised that the original dcs-get is not very robust, and is broken in a lot
of ways that legitimately cause people trouble.

Here are some honest advantages of this implementation:

* Installs do download and writing separately (like all real package managers ever)
* The reinstall feature is superior to reinstall and deep-reinstall from old dcs-get
* Generate symlinks uses better directories, and uses share
* Records whether packages are installed manually or automatically as a dependency
* Should have an uninstall feature eventually -- this is a little superflous
* It more robust in many other ways
* Will be easy to try out on any dcs-get installation as I'm adding a package for it

Here are some honest disadvantages of this implementation:

* Not piping the download to tar extract means that downloading and installing is slower
* The download bar is not as [jizzy](https://github.com/UWCS/dcs-get/blob/master/dcs-get#L151)
* The code is longer, and in some ways more complicated, although overall hopefully easier to read
* This implementation requires some packages to be immediately installed in dcs-get-install to get this executable working... however these packages are tiny and fast to install should we ever make this the default implementation

Todo
----

* Implement package, upload, and uninstall modes
* Write guide on building lua, luarocks and "Lua dcs-get" as a package
