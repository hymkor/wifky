VERSION:=$(shell git describe --tags 2>/dev/null || echo v0.0.0)

dist:
	cp wifky.pl wifky_usrbin.pl
	gawk '{ gsub(/#!\/usr\/bin\/perl/,"#!/usr/local/bin/perl") ; print }' wifky.pl > wifky_local.pl
	zip -m wifky-$(VERSION).zip wifky_local.pl wifky_usrbin.pl

.PHONY: dist
