JAVA ?= java
PROG8_VERSION ?= 14.0-BETA3
JAR ?= prog8c-$(PROG8_VERSION)-all.jar
PROG8C = $(JAVA) -jar "$(JAR)"
TARGET ?= cx16
EMU ?= x16emu
# BETA3 rejects unsigned subtraction in gapbuffer.p8 with optimization enabled.
OPT ?= -noopt
XVI2_SRC := src/xvi2.p8

.DEFAULT_GOAL := build
.PHONY: all build run br debug trace clean

all: build

build:
	$(PROG8C) $(OPT) -srcdirs src -srcdirs src/$(TARGET) -target $(TARGET) $(XVI2_SRC)

run:
	$(EMU) -scale 2 -prg xvi2.prg -run

br: build
	$(MAKE) run

debug:
	$(EMU) -scale 2 -prg xvi2.prg -run -debug

trace:
	$(EMU) -scale 2 -prg xvi2.prg -run -trace

clean:
	rm -f xvi2.prg xvi2.asm xvi2.vice-mon-list src/*.pp.p8
