#!/usr/bin/env perl
#
#NOTE: this script will clean up all leftover files

use strict;
use warnings;
use File::Spec;
use FindBin qw/$RealBin/;
use lib "$RealBin/../lib";

# In case the mash executable is here
$ENV{PATH}="$ENV{PATH}:$RealBin/../bin/Mash-2.1.1";

use Test::More tests=>1;

pass("CLEANUP");

