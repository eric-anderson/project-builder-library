#!/usr/bin/perl -w
#
# ProjectBuilder Conf module
# Conf files subroutines brought by the the Project-Builder project
# which can be easily used by wahtever perl project
#
# $Id$
#

package ProjectBuilder::Conf;

use strict;
use Carp 'confess';
use Data::Dumper;
use ProjectBuilder::Base;
use ProjectBuilder::Version;

# Inherit from the "Exporter" module which handles exporting functions.
 
use vars qw($VERSION $REVISION @ISA @EXPORT);
use Exporter;
 
# Export, by default, all the functions into the namespace of
# any code which uses this module.
 
our @ISA = qw(Exporter);
our @EXPORT = qw(pb_conf_init pb_conf_add pb_conf_read pb_conf_read_if pb_conf_get pb_conf_get_if);
($VERSION,$REVISION) = pb_version_init();

# Global hash of conf files
# Key is the conf file name
# Value is its rank
my %pbconffiles;

# Global hash of cached values. 
# We consider that values can not change during the life of pb
# my %cachedval;

=pod

=head1 NAME

ProjectBuilder::Conf, part of the project-builder.org - module dealing with configuration files

=head1 DESCRIPTION

This modules provides functions dealing with configuration files.

=head1 SYNOPSIS

  use ProjectBuilder::Conf;

  #
  # Read hash codes of values from a configuration file and return table of pointers
  #
  my ($k1, $k2) = pb_conf_read_if("$ENV{'HOME'}/.pbrc","key1","key2");
  my ($k) = pb_conf_read("$ENV{'HOME'}/.pbrc","key");

=head1 USAGE

=over 4

=item B<pb_conf_init>

This function setup the environment PBPROJ for project-builder function usage from other projects.
The first parameter is the project name.
It sets up environment variables (PBPROJ) 

=cut

sub pb_conf_init {

my $proj=shift || undef;

if (defined $proj) {
	$ENV{'PBPROJ'} = $proj;
} else {
	$ENV{'PBPROJ'} = "default";
}
}



=item B<pb_conf_add>

This function adds the configuration file to the list last.

=cut

sub pb_conf_add {

pb_log(2,"DEBUG: pb_conf_add with ".Dumper(@_)."\n");

foreach my $cf (@_) {
	# Skip already used conf files
	next if (defined $pbconffiles{$cf});
	# Add the new one at the end
	my $num = keys %pbconffiles;
	pb_log(2,"DEBUG: pb_conf_add $cf at position $num\n");
	$pbconffiles{$cf} = $num;
	pb_log(0,"WARNING: pb_conf_add can not read $cf\n") if (! -r $cf);
}
}

=item B<pb_conf_read_if>

This function returns a table of pointers on hashes
corresponding to the keys in a configuration file passed in parameter.
If that file doesn't exist, it returns undef.

The format of the configuration file is as follows:

key tag = value1,value2,...

Supposing the file is called "$ENV{'HOME'}/.pbrc", containing the following:

  $ cat $HOME/.pbrc
  pbver pb = 3
  pbver default = 1
  pblist pb = 12,25

calling it like this:

  my ($k1, $k2) = pb_conf_read_if("$ENV{'HOME'}/.pbrc","pbver","pblist");

will allow to get the mapping:

  $k1->{'pb'}  contains 3
  $k1->{'default'} contains 1
  $k2->{'pb'} contains 12,25

Valid chars for keys and tags are letters, numbers, '-' and '_'.

=cut

sub pb_conf_read_if {

my $conffile = shift;
my @param = @_;

open(CONF,$conffile) || return((undef));
close(CONF);
return(pb_conf_read($conffile,@param));
}

=item B<pb_conf_read>

This function is similar to B<pb_conf_read_if> except that it dies when the file in parameter doesn't exist.

=cut

sub pb_conf_read {

my $conffile = shift;
my @param = @_;
my $trace;
my @ptr;
my %h;

open(CONF,$conffile) || die "Unable to open $conffile";
while(<CONF>) {
	if (/^\s*([A-z0-9-_.]+)\s+([[A-z0-9-_.]+)\s*=\s*(.+)$/) {
		pb_log(3,"DEBUG: 1:$1 2:$2 3:$3\n");
		$h{$1}{$2}=$3;
	}
}
close(CONF);

for my $param (@param) {
	push @ptr,$h{$param};
}
return(@ptr);
}

=item B<pb_conf_get_if>

This function returns a table, corresponding to a set of values queried in the conf files or undef if it doen't exist. It takes a table of keys as an input parameter.

The format of the configurations file is as follows:

key tag = value1,value2,...

It will gather the values from all the configurations files passed to pb_conf_add, and return the values for the keys, taking in account the order of conf files, to manage overloading.

  $ cat $HOME/.pbrc
  pbver pb = 1
  pblist pb = 4
  $ cat $HOME/.pbrc2
  pbver pb = 3
  pblist default = 5

calling it like this:

  pb_conf_add("$HOME/.pbrc","$HOME/.pbrc2");
  my ($k1, $k2) = pb_conf_get_if("pbver","pblist");

will allow to get the mapping:

  $k1->{'pb'} contains 3
  $k2->{'pb'} contains 4

Valid chars for keys and tags are letters, numbers, '-' and '_'.

=cut

sub pb_conf_get_if {

my @param = @_;

my $ptr = undef;

# the most important conf file is first, so read them in reverse order
foreach my $f (reverse sort { $pbconffiles{$a} <=> $pbconffiles{$b} } keys %pbconffiles) {
	pb_log(2,"DEBUG: pb_conf_get_if in file $f\n");
	$ptr = pb_conf_get_fromfile_if("$f",$ptr,@param);
}

return(@$ptr);
}

=item B<pb_conf_fromfile_if>

This function returns a pointer on a table, corresponding to a merge of values queried in the conf file and the pointer on another table passed as parameter. It takes a table of keys as last input parameter.

  my ($k1) = pb_conf_fromfile_if("$HOME/.pbrc",undef,"pbver","pblist");
  my ($k2) = pb_conf_fromfile_if("$HOME/.pbrc3",$k1,"pbver","pblist");

It is used internally by pb_conf_get_if and is not exported yet.

=cut


sub pb_conf_get_fromfile_if {

my $conffile = shift;
my $ptr2 = shift || undef;
my @param = @_;

# Everything is returned via ptr1
my @ptr1 = ();
my @ptr2 = ();

# @ptr1 contains the values overloading what @ptr2 may contain.
@ptr1 = pb_conf_read_if("$conffile", @param) if (defined $conffile);
@ptr2 = @$ptr2 if (defined $ptr2);

my $p1;
my $p2;

pb_log(2,"DEBUG: pb_conf_get_from_file $conffile: ".Dumper(@ptr1)."\n");
pb_log(2,"DEBUG: pb_conf_get_from_file input: ".Dumper(@ptr2)."\n");
pb_log(2,"DEBUG: pb_conf_get_from_file param: ".Dumper(@param)."\n");

foreach my $i (0..$#param) {
	$p1 = $ptr1[$i];
	# Optimisation doesn't seem useful
	# if ((defined $p1) && (defined $cachedval{$p1})) {
	# $ptr1[$i] = $cachedval{$p1};
	# next;
	# }
	$p2 = $ptr2[$i];
	# Always try to take the param from ptr1 
	# in order to mask what could be defined already in ptr2
	if (not defined $p2) {
		# exit if no p1 either
		next if ((not defined $p1) || (not defined $ENV{'PBPROJ'}));
		# No ref in p2 so use p1
		$p1->{$ENV{'PBPROJ'}} = $p1->{'default'} if ((not defined $p1->{$ENV{'PBPROJ'}}) && (defined $p1->{'default'}));
	} else {
		# Ref found in p2
		if (not defined $p1) {
			# No ref in p1 so use p2's value
			$p2->{$ENV{'PBPROJ'}} = $p2->{'default'} if ((not defined $p2->{$ENV{'PBPROJ'}}) && (defined $p2->{'default'}));
			$p1 = $p2;
		} else {
			# Both are defined - handling the overloading
			if (not defined $p1->{'default'}) {
				if (defined $p2->{'default'}) {
					$p1->{'default'} = $p2->{'default'};
				}
			}

			if (not defined $p1->{$ENV{'PBPROJ'}}) {
				if (defined $p2->{$ENV{'PBPROJ'}}) {
					$p1->{$ENV{'PBPROJ'}} = $p2->{$ENV{'PBPROJ'}} if (defined $p2->{$ENV{'PBPROJ'}});
				} else {
					$p1->{$ENV{'PBPROJ'}} = $p1->{'default'} if (defined $p1->{'default'});
				}
			}
			# Now copy back into p1 all p2 content which doesn't exist in p1
			# p1 content always has priority over p2
			foreach my $k (keys %$p2) {
				$p1->{$k} = $p2->{$k} if (not defined $p1->{$k});
			}
		}
	}
	$ptr1[$i] = $p1;
	# Cache values to avoid redoing all that analyze when asked again on a known value
	# $cachedval{$p1} = $p1;
}
pb_log(2,"DEBUG: pb_conf_get output: ".Dumper(@ptr1)."\n");
return(\@ptr1);
}

=item B<pb_conf_get>

This function is the same B<pb_conf_get_if>, except that it tests each returned value as they need to exist in that case.

=cut

sub pb_conf_get {

my @param = @_;
my @return = pb_conf_get_if(@param);
my $proj = undef;

if (not defined $ENV{'PBPROJ'}) {
	$proj = "unknown";
} else {
	$proj = $ENV{'PBPROJ'};
}

die "No params found for $proj" if (not @return);

foreach my $i (0..$#param) {
	confess "No $param[$i] defined for $proj" if (not defined $return[$i]);
}
return(@return);
}

=back 

=head1 WEB SITES

The main Web site of the project is available at L<http://www.project-builder.org/>. Bug reports should be filled using the trac instance of the project at L<http://trac.project-builder.org/>.

=head1 USER MAILING LIST

None exists for the moment.

=head1 AUTHORS

The Project-Builder.org team L<http://trac.project-builder.org/> lead by Bruno Cornec L<mailto:bruno@project-builder.org>.

=head1 COPYRIGHT

Project-Builder.org is distributed under the GPL v2.0 license
described in the file C<COPYING> included with the distribution.

=cut


1;
