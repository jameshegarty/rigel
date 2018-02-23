MKPATH := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
PLATFORMDIRS = $(wildcard $(MKPATH)/*)
AA = $(patsubst $(MKPATH)/%,%,$(PLATFORMDIRS))

define MyRule
out/%.$(1).bit: out/%.v out/%.metadata.lua
	$(MKPATH)/$(1)/compile $(shell pwd)/out/$$*.v out/$$*.metadata.lua $(shell pwd)/out/$$*_$(1) $(shell pwd)/out/$$*.$(1).bit

out/%.$(1).correct.txt : out/%.$(1).bmp
	diff out/$$*.$(1).bmp gold/$$*.bmp > out/$$*.$(1).diff
	test ! -s out/$$*.$(1).diff && touch $$@

out/%.$(1).raw: out/%.$(1).bit out/%.metadata.lua
	$(MKPATH)/$(1)/run $(shell pwd)/out/$$*.$(1).bit $(shell pwd)/out/$$*.metadata.lua $(shell pwd)/out/$$*.$(1).raw $(shell pwd)/out/$$*.$(!)

out/%.$(1).cycles.txt: out/%.$(1).raw
	../rigelLuajit $(MKPATH)/../misc/extractCycles.lua out/$$*.$(1).raw > out/$$*.$(1).cycles.txt

out/%.$(1).bmp: out/%.$(1).raw out/%.metadata.lua
	$(LUA) $(MKPATH)/../misc/raw2bmp.lua out/$$*.$(1).raw out/$$*.$(1).bmp out/$$*.metadata.lua 0
	# keep copy for future reference
	mkdir -p out/$$*_$(1)
	cp out/$$*.$(1).bmp out/$$*_$(1)
endef

$(foreach a,$(AA),$(eval $(call MyRule,$(a))))
