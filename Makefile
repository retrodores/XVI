JAVA ?= java
PROG8_VERSION ?= 14.0-BETA3
JAR ?= prog8c-$(PROG8_VERSION)-all.jar
PROG8C = $(JAVA) -jar "$(JAR)"
ifneq ($(filter-out cx16,$(TARGET)),)
$(error XVI2 targets Commander X16 only; use retrodores/p8vi for cross-platform editing)
endif
EMU ?= x16emu
# Keep the pinned, tested BETA3 build path; optimization remains opt-in.
OPT ?= -noopt
XVI_EDITOR ?= xvi2
ifneq ($(filter-out xvi2 xvi,$(XVI_EDITOR)),)
$(error XVI_EDITOR must be xvi2 or xvi)
endif
ifeq ($(XVI_EDITOR),xvi)
SRC_DIRS := -srcdirs src/vtui -srcdirs src/cx16 -srcdirs src
else
SRC_DIRS := -srcdirs src -srcdirs src/cx16
endif
XVI_SRC := src/$(XVI_EDITOR).p8

.DEFAULT_GOAL := build
.PHONY: all build vtui run br debug trace clean

all: build

build:
	$(PROG8C) $(OPT) $(SRC_DIRS) -target cx16 $(XVI_SRC)

vtui:
	$(MAKE) build XVI_EDITOR=xvi

run:
	$(EMU) -scale 2 -prg $(XVI_EDITOR).prg -run

br: build
	$(MAKE) run

debug:
	$(EMU) -scale 2 -prg $(XVI_EDITOR).prg -run -debug

trace:
	$(EMU) -scale 2 -prg $(XVI_EDITOR).prg -run -trace

clean:
	rm -f xvi2.prg xvi2.asm xvi2.vice-mon-list xvi.prg xvi.asm xvi.vice-mon-list src/*.pp.p8
