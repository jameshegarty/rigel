MKPATH := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
PLATFORMDIRS = $(wildcard $(MKPATH)/*)
AA = $(patsubst $(MKPATH)/%,%,$(PLATFORMDIRS))
BUILDDIR ?= out

define MyRule
$(BUILDDIR)/%.$(1).bit: $(BUILDDIR)/%.v
	{ time -p $(MKPATH)/$(1)/compile $(shell pwd)/$(BUILDDIR)/$$*.v $(BUILDDIR)/$$*.metadata.lua $(shell pwd)/$(BUILDDIR)/$$*_$(1) $(shell pwd)/$(BUILDDIR)/$$*.$(1).bit; } 2>&1 | tee $(BUILDDIR)/$$*.compiletimeraw.txt
	printf '$$*,' > $(BUILDDIR)/$$*.compiletime.txt
	cat $(BUILDDIR)/$$*.compiletimeraw.txt | grep user | grep -Eo "[0-9\.]+" >> $(BUILDDIR)/$$*.compiletime.txt
	rm $(BUILDDIR)/$$*.compiletimeraw.txt


# hack to allow users of this include to override gold dir
GOLDSTRPRE ?= gold/
GOLDSTRPOST ?= .bmp
$(BUILDDIR)/%.$(1).correct.txt : $(BUILDDIR)/%.$(1).bmp
	diff $(BUILDDIR)/$$*.$(1).bmp $(GOLDSTRPRE)$$*$(GOLDSTRPOST) > $(BUILDDIR)/$$*.$(1).diff
	test ! -s $(BUILDDIR)/$$*.$(1).diff && touch $$@
	date

$(BUILDDIR)/%.$(1).regcorrect.txt : $(BUILDDIR)/%.$(1).bmp
	$(LUA) ../misc/regcheck.lua $(BUILDDIR)/$$*.$(1).regout.lua $(GOLDSTRPRE)$$*.regout.lua && touch $$@
	date

$(BUILDDIR)/%.$(1).cyclescorrect.txt : $(BUILDDIR)/%.$(1).bmp
	$(LUA) ../misc/approxnumdiff.lua $(BUILDDIR)/$$*.$(1).cycles.txt $(GOLDSTRPRE)$$*.$(1).cycles.txt $$@ 0.05 smallerIsBetter

$(BUILDDIR)/%.$(1).raw: $(BUILDDIR)/%.$(1).bit
	{ time -p $(MKPATH)/$(1)/run $(shell pwd)/$(BUILDDIR)/$$*.$(1).bit $(shell pwd)/$(BUILDDIR)/$$*.metadata.lua $(shell pwd)/$(BUILDDIR)/$$*.$(1).raw $(shell pwd)/$(BUILDDIR)/$$*.$(!); } 2>&1 | tee $(BUILDDIR)/$$*.runtimeraw.txt
	printf '$$*,' > $(BUILDDIR)/$$*.runtime.txt
	cat $(BUILDDIR)/$$*.runtimeraw.txt | grep user | grep -Eo "[0-9\.]+" >> $(BUILDDIR)/$$*.runtime.txt
	rm $(BUILDDIR)/$$*.runtimeraw.txt

$(BUILDDIR)/%.$(1).cycles.txt: $(BUILDDIR)/%.$(1).raw
	../rigelLuajit $(MKPATH)/../misc/extractCycles.lua $(BUILDDIR)/$$*.$(1).raw > $(BUILDDIR)/$$*.$(1).cycles.txt

$(BUILDDIR)/%.$(1).bmp: $(BUILDDIR)/%.$(1).raw
	$(LUAJIT) $(MKPATH)/../misc/raw2bmp.lua $(BUILDDIR)/$$*.$(1).raw $(BUILDDIR)/$$*.$(1).bmp $(BUILDDIR)/$$*.metadata.lua 0
	# keep copy for future reference
	mkdir -p $(BUILDDIR)/$$*_$(1)
	cp $(BUILDDIR)/$$*.$(1).bmp $(BUILDDIR)/$$*_$(1)
endef

$(foreach a,$(AA),$(eval $(call MyRule,$(a))))
