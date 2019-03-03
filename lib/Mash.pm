#!/usr/bin/env perl
package Mash;
use strict;
use warnings;
use Exporter qw(import);
use File::Basename qw/fileparse basename dirname/;
use Data::Dumper;

use JSON qw/from_json/;
use Bio::Seq;
use Bio::Tree::Tree;
use Bio::Matrix::Generic;
use Bio::SimpleAlign;
use Bio::Align::DNAStatistics;
use Bio::Tree::DistanceFactory;

our $VERSION = 0.1;

our @EXPORT_OK = qw(
         );

local $0=basename $0;

# If this is used in a scalar context, $self->toString() is called
use overload '""' => 'toString';

=pod

=head1 NAME

Mash

=head1 SYNOPSIS

A module to read `mash info` output and transform it

  use strict;
  use warnings;
  use Mash

  # Quick example

  # Sketch all fastq files into one mash file.
  system("mash sketch *.fastq.gz > all.msh");
  die if $?;
  # Read the mash file.
  my $msh = Mash->new(["all.msh"]);
  # Get a Bio::Tree::Tree object
  my $tree = $msh->tree;

  # Do something with the tree, e.g.,
  print $tree->as_text("newick");

=head1 DESCRIPTION

This is a module to read mash files produced by the Mash executable. For more information on Mash, see L<mash.readthedocs.org>.  This module is capable of reading mash files.  Future versions will read/write mash files.

=head1 METHODS

=over

=item Mash->new(\@listOfFiles,\%options);

Create a new instance of Mash.  One object per set of files.

  Arguments:  List of filenames
              Hash of options (none so far)
  Returns:    Mash object

  -or-

  Arguments:  Hash of data
              Hash of options (none so far)
  Returns:    Mash object

=back

=cut

sub new{
  my($class,$mshData,$settings)=@_;

  my $self={
    file      => [],
    info      => {},
    names     => [],
    hashes    => {},
    distance  => {},
  };
  bless($self,$class);

  # How should we initialize?
  if(ref($mshData) eq 'HASH'){
    # Make sure every key is present that is needed
    my @requiredKeys=qw(info names hashes);
    for my $key(@requiredKeys){
      if(!$$mshData{$key}){
        die "ERROR: could not find key '$key' in hash for $class";
      }
      if(ref($$mshData{$key}) ne ref($$self{$key})){
        die "ERROR: data type for '$key' does not match ".ref($$self{$key});
      }
    }
    $self->_newByHash($mshData,$settings);
  } elsif(ref($mshData) eq 'ARRAY'){
    $self->_newByMashFile($mshData,$settings);
  } else {
    die "ERROR: the first parameter must be a list of mash file(s)";
  }
  return $self;
}


# Initialize with a mash file
sub _newByMashFile{
  my($self,$file,$settings)=@_;

  $self->{file}=$file;
  if(ref($file) ne 'ARRAY'){
    die "ERROR: the first parameter must be a list of mash file(s)";
  }

  # Gather info from each file. $self->{info} and
  # $self->{hashes} gets updated.
  for my $f(@$file){
    $self->addMashFile($f);
  }

  # Test that all metadata for mash are the same as the
  # first genome in the set.  I.e., they are all the same.
  my $info=$self->{info};
  my @genomeName=keys(%$info);
  my $ref=shift(@genomeName); 
  for my $g(@genomeName){
    # TODO don't worry about sketch size b/c you can take
    # first X sketches from each where X is the smallest
    # number of sketches in the set. For now though to make
    # things simple, just take exact numbers.
    for my $key(qw(kmer alphabet preserveCase canonical sketchSize hashType hashBits hashSeed)){
      if($$info{$g}{$key} ne $$info{$ref}{$key}){
        die "ERROR: genomes $ref and $g are incompatible under property $key";
      }
    }
  }

  # Set a sorted list of names
  $self->{names}=[sort {$a cmp $b} keys(%{ $self->{info} })];

  return $self;
}

=pod

=over

=item $msh->addMashFile()

Returns a hash ref that describes a single mash file. Updates the Mash object with this info. This method is ordinarily not used externally to the object.

  Arguments: One mash file
  Returns:   Reference to a hash

  TODO:      add new subroutine to add by hash

=back

=cut

sub addMashFile{
  my($self,$msh)=@_;
  
  my %info = %{ $self->{info} };

  if(!   $msh){
    logmsg "WARNING: no file was given to \$self->addMashFile";
    return {};
  }
  if(!-e $msh){
    die "ERROR: could not find file $msh";
  }

  my $mashInfo=from_json(`mash info -d $msh`);

  for my $sketch(@{ $$mashInfo{sketches} }){
    #delete($$sketch{hashes}); logmsg "DEBUG: removing hashes element";
    $info{$$sketch{name}}=$sketch;

    my %sketchHash;
    for my $pos(@{ $$sketch{hashes} }){
      $$self{hashes}{$pos}++;
      $sketchHash{$pos}=1;
    }
    $info{$$sketch{name}}{hashes}=\%sketchHash;

    # Also take on the general properties of the mash file
    for my $key(qw(kmer alphabet preserveCase canonical sketchSize hashType hashBits hashSeed)){
      $info{$$sketch{name}}{$key}=$$mashInfo{$key};
    }
  }

  $self->{info}=\%info;

  return \%info;
}

=pod

=over

=item $msh->mashDistances()

Returns a reference to a hash of mash distances

=back

=cut

sub mashDistances{
  my($self)=@_;
  # Don't recalculate
  return $self->{distance} if(keys(%{ $self->{distance} }) > 0);

  my @file=@{$self->{file}};
  my $numFiles=@file;
  
  my %distance;
  for(my $i=0;$i<$numFiles;$i++){
    for(my $j=0;$j<$numFiles;$j++){
      open(my $fh, "mash dist '$file[$i]' '$file[$j]' | ") or die "ERROR: running mash dist on $file[$i] and $file[$j]: $!";
      while(<$fh>){
        chomp;
        my($genome1,$genome2,$dist,$p,$sharedFraction)=split(/\t/,$_);
        $distance{$genome1}{$genome2}=$dist;
      }
      close $fh;
    }
  }
  $self->{distance}=\%distance;
  return \%distance;
}

##### Utility methods

sub _reroot_at_midpoint{
  my($tree)=@_;
  my $node_with_longest_branch = (sort{
    my $A=$a->branch_length || 0;
    my $B=$b->branch_length || 0;
    $B <=> $A
  } $tree->get_nodes)[0];
  my $rootNode=$tree->reroot_at_midpoint($node_with_longest_branch);
  if(!$rootNode->branch_length || $rootNode->branch_length < 0.01){
    $rootNode->branch_length(0.01);
  }
  return $rootNode;
}

sub toString{
  my($self)=@_;
  my $fileArr=$self->{file};
  my $return="Mash object with " .scalar(@$fileArr)." files:\n\n";
  
  for(@$fileArr){
    $return.="-------${_}------\n";
    my $info=`mash info '$_'`;
    chomp($info);
    $return.=$info;
    $return.="^^^^^^^${_}^^^^^^\n\n";
  }
  
  return $return;
}

=pod

=head1 COPYRIGHT AND LICENSE

MIT license.

=head1 AUTHOR

Author:  Lee Katz <lkatz@cdc.gov>

For additional help, go to https://github.com/lskatz/perl-mash

CPAN module at http://search.cpan.org/~lskatz/perl-mash

=cut

1; # gotta love how we we return 1 in modules. TRUTH!!!

