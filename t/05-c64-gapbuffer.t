#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Prog8Test qw(run_suite);
unless ($ENV{VICE} && $ENV{VICE_ROMS}) {
    print "1..0 # SKIP set VICE and VICE_ROMS to run headless C64 tests\n";
    exit 0;
}
run_suite('t/gapbuffer_test.p8', 'c64');
