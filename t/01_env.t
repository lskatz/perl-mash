#!/usr/bin/env perl

use strict;
use warnings;
use File::Spec;
use FindBin qw/$RealBin/;
use lib "$RealBin/../lib";

# In case the mash executable is here
$ENV{PATH}="$ENV{PATH}:$RealBin/../bin/Mash-2.1.1";

use Test::More tests=>3;
use_ok("Bio::Sketch");
use_ok("Bio::Sketch::Mash");

my $mash = which("mash");
ok($mash, "Found Mash executable");
$mash||="";
note "Path for Mash: $mash";

sub which{
  my($exec)=@_;

  return undef unless $exec;

  my @path = File::Spec->path;
  for my $p(@path){
    if( -e "$p/$exec" && -x "$p/$exec"){
      return "$p/$exec";
    }
  }
  return undef;
}
