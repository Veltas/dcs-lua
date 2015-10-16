# dcs-lua
Replacement for dcs-get main executable in Lua (in dev)

Status
------

In development, ask me personally for info on getting it installed if you want to try it,
although I don't recommend doing that until I've got all the old features finished and tested

A little elaboration
--------------------

I started with the idea "hey, I reckon I could rewrite dcs-get's main executable":

* In a language that isn't PHP
* Shorter and sweeter (a lot of clutter in original dcs-get)
* In a way that is easier for future compsoc to maintain and extend

While working on it I realised that the original dcs-get is not very robust, and is broken in a lot
of ways that legitimately cause people trouble. When I am done with this implementation it will not
be worth using the original dcs-get anymore.

Here are some honest advantages of this implementation:

* Installs do download and writing separately (like all real package managers ever)
* The reinstall feature is superior to reinstall and deep-reinstall from old dcs-get
* Records whether packages are installed manually or automatically as a dependency
* Should have an uninstall feature eventually -- this is a little superflous
* It is probably more robust in many other ways
* It is written in Lua, which is a far 'nicer' language than PHP, and probably more appropriate for the task
* Will be easy to try out on any dcs-get installation as I'm adding a package for it

Here are some honest disadvantages of this implementation:

* The download bar is not as [jizzy](https://github.com/UWCS/dcs-get/blob/master/dcs-get#L151)
* Not piping the download to tar extract means that downloading and installing is 'slower'
* The code is longer and when it is finished would require a basic understanding of 'classes' to make easy sense, although anyone should be able to read Lua
* This implementation requires some packages to be immediately installed in dcs-get-install to get this executable working... however these packages are tiny and fast to install should we ever make this the default implementation
