# Attention

dcs-get as a whole has been **deprecated**. CompSoc is now using a solution over NFS in `~compsoc/packages`. I'd written an article about this but CompSoc's services are currently down. In short, you can replace `/var/tmp/dcs-get` for `/dcs/guest/compsoc/packages` in your `bashrc`. When I get around to it I'll publish an article on how to use the new system and appropriately package for it, probably [here](http://veltas.co.uk/docs/building.html).

# dcs-lua
Replacement for dcs-get main executable in Lua

This project is only of use to those using dcs-get at the University of Warwick

##Installing

At this stage you can overwrite your [dcs-get](http://backus.uwcs.co.uk/dcs-get/) session with dcs-lua in one command:

    $ dcs-get i dcs-lua

Consider adding this to your session scripts!

Alternatively clone the repo and run `make` in its root directory.

##Improvements

Now when you install packages they're marked as manually installed, your pre-existing packages are still there and should remain installed correctly.

The following will give you a list of commands:

    $ dcs-get help

Improvements over the PHP script:
+ Reinstall function works correctly - gets list of dependencies and installs again from the ground up
+ Uninstall function
+ More responsive - PHP version would take a split second to start
+ More robust packaging function
+ Better search results / listing
+ Remembers which packages are requested and which were automatically installed

This software is still in development. If you find bugs, please [report them in the issue tracker](https://github.com/Veltas/dcs-lua/issues).

####Revert installation

If you want to revert your install of dcs-get you can redownload the dcs-get executable:

    $ rm /var/tmp/dcs-get/bin/dcs-get
    $ curl http://backus.uwcs.co.uk/dcs-get/dcs-get > /var/tmp/dcs-get/bin/dcs-get

Alternatively you need to remove the dcs-get directory and trigger the installation script again.

#####Remove dcs-get directory

Try the cleanup script first with either `dcs-get clean`, or if that fails:

    $ /var/tmp/dcs-get/cleanup

If you own the directory and the cleanup script fails, you should remove the dcs-get directory yourself:

    $ rm -rf /var/tmp/dcs-get

#####Install dcs-get

Re-run the install script. In a normal configuration `_dcs-get` will do the job.
