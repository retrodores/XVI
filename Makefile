JAVA ?= java
PROG8_VERSION ?= 12.0.1
JAR ?= prog8c-$(PROG8_VERSION)-all.jar
EMU ?= x16emu
OPT ?=
XVI_EDITOR ?= xvi2
.DEFAULT_GOAL := build
.PHONY: build vtui run br clean
build:
ifeq ($(XVI_EDITOR),xvi2)
	$(JAVA) -jar "$(JAR)" $(OPT) -target cx16 src/xvi2.p8
else ifeq ($(XVI_EDITOR),xvi)
	@echo 'Recovering the historical VTUI PRG; not recompiling or modifying its source.'
	cp recovery/XVI-VTUI-ORIGINAL.PRG xvi.prg
else
	$(error XVI_EDITOR must be xvi2 or xvi)
endif
vtui:
	$(MAKE) build XVI_EDITOR=xvi
run:
	$(EMU) -scale 2 -prg $(XVI_EDITOR).prg -run
br: build run
clean:
	rm -f xvi.prg xvi2.prg xvi.asm xvi2.asm xvi.vice-mon-list xvi2.vice-mon-list
