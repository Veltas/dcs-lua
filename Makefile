DCSGETDIR=/var/tmp/dcs-get
MODDIR=$(DCSGETDIR)/dcslib/dcsget

$(DCSGETDIR)/bin/dcs-get: bin/dcs-get $(MODDIR)/PackageManager.lua
	cp $< $@

$(MODDIR)/init.lua: dcslib/dcsget/init.lua | $(MODDIR)
	cp $< $@

$(MODDIR)/PackageData.lua: dcslib/dcsget/PackageData.lua $(MODDIR)/init.lua | $(MODDIR)
	cp $< $@

$(MODDIR)/PackageManager.lua: dcslib/dcsget/PackageManager.lua $(MODDIR)/init.lua $(MODDIR)/PackageData.lua | $(MODDIR)
	cp $< $@

$(MODDIR): | $(DCSGETDIR)/dcslib

$(DCSGETDIR)/dcslib $(MODDIR):
	mkdir $@


# You will usually have to outdate the install the first time to get it to
# update files

.PHONY: outdate
outdate:
	-touch bin/* dcslib/dcsget/*
