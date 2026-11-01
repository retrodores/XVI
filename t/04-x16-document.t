#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Prog8Test qw(run_suite);
unless ($ENV{X16EMU} && $ENV{X16ROM}) {
    print "1..0 # SKIP set X16EMU and X16ROM to run headless X16 tests\n";
    exit 0;
}
run_suite('t/document_test.p8', 'cx16');
