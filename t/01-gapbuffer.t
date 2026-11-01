#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Prog8Test qw(run_suite);
run_suite('t/gapbuffer_test.p8');
