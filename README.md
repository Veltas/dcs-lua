# dcs-lua
Replacement for dcs-get main executable in Lua

This project is only of use to those using dcs-get at the University of Warwick

##Status

Test version that mostly works. Missing package, upload and uninstall modes.

Package should be ready for dcs-get now under the name `dcs-lua`

##Installing

I'm putting releases of it on dcs-get for testing. You can try it out if you have [dcs-get](http://backus.uwcs.co.uk/dcs-get/) installed.

    $ dcs-get install dcs-lua

This will overwrite your session with dcs-lua. Now when you install packages they're marked as manually installed, your pre-existing packages are still there and should remain installed correctly. If you find bugs please [report them in the issue tracker](https://github.com/Veltas/dcs-lua/issues).

When installed this version of the executable is used mostly the same way as the old one, check status section above for missing features. The following will give you a list of commands:

    $ dcs-get help

A notable difference is the reinstall mode works better than both the reinstall and deep-reinstall from the old executable. Reinstall mode gets a list of all the dependencies, and manually installs them in an appropriate order, and then reinstalls the requested package. The original reinstall mode only reinstalled the exact package given (which was rarely useful), and deep-reinstall mode would try and reinstall dependencies but would get caught in dependency loops.

Also the list mode just gives a list of all the packages in alphabetical order. The old list mode would hide some packages, with other modes for listing extra lists. The old mode was also not in alphabetical order, and couldn't be piped into less for some unknown reason probably related to PHP.

####Revert installation

If you need to revert your install of dcs-get you can redownload the dcs-get executable:

    $ rm /var/tmp/dcs-get/bin/dcs-get
    $ curl http://backus.uwcs.co.uk/dcs-get/dcs-get > /var/tmp/dcs-get/bin/dcs-get

If something goes wrong or if you prefer, you can run the cleanup script. In bash with a normal installation the install function should still be loaded:

    $ dcs-get clean
    $ _dcs-get

If the dcs-get command is completely failing, you can invoke the cleanup script manually:

    $ /var/tmp/dcs-get/cleanup

##Reasoning

I started with the idea "hey, I reckon I could rewrite dcs-get's main executable":

* In a language that isn't PHP
* Shorter and sweeter (a lot of clutter in original dcs-get)
* In a way that is easier for future compsoc to maintain and extend

While working on it I realised that the original dcs-get is not very robust, and is broken in a lot
of ways that legitimately cause people trouble.

This implementation failed my original goal of writing a shorter program, but I think it is still better overall.

Here are some honest advantages of this implementation:

* Installs do download and writing separately (like all real package managers ever)
* The reinstall feature is superior to reinstall and deep-reinstall from old dcs-get
* Generate symlinks uses better directories, and uses share
* Records whether packages are installed manually or automatically as a dependency
* Should have an uninstall feature eventually -- this is a little superflous
* Is more robust in many other ways
* Will be easy to try out on any dcs-get installation as I'm adding a package for it

Here are some honest disadvantages of this implementation:

* Not piping the download to tar extract means that downloading and installing is slower
* The download bar is not as [jizzy](https://github.com/UWCS/dcs-get/blob/master/dcs-get#L151)
* The code is longer, and in some ways more complicated, although overall hopefully easier to read
* This implementation requires some packages to be immediately installed in dcs-get-install to get this executable working... however these packages are tiny and fast to install should we ever make this the default implementation

##Todo

* Implement package, upload, and uninstall modes
* Write guide on building lua, luarocks and "Lua dcs-get" as a package
