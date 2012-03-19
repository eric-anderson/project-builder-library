#!/usr/bin/perl -w
#
# Creates common environment for distributions
#
# $Id$
#

package ProjectBuilder::Distribution;

use strict;
use Carp 'confess';
use Data::Dumper;
use ProjectBuilder::Version;
use ProjectBuilder::Base;
use ProjectBuilder::Conf;
use File::Basename;
use File::Copy;
use File::Compare;
use FileHandle;

# Global vars
# Inherit from the "Exporter" module which handles exporting functions.
 
use vars qw($VERSION $REVISION @ISA @EXPORT);
use Exporter;
 
# Export, by default, all the functions into the namespace of
# any code which uses this module.
 
our @ISA = qw(Exporter);
our @EXPORT = qw(pb_distro_conffile pb_distro_get pb_distro_getlsb pb_distro_installdeps pb_distro_getdeps pb_distro_only_deps_needed pb_distro_setuprepo pb_distro_setuposrepo pb_distro_get_param pb_distro_get_context);
($VERSION,$REVISION) = pb_version_init();

=pod

=head1 NAME

ProjectBuilder::Distribution, part of the project-builder.org - module dealing with distribution detection

=head1 DESCRIPTION

This modules provides functions to allow detection of Linux distributions, and giving back some attributes concerning them.

=head1 SYNOPSIS

  use ProjectBuilder::Distribution;

  # 
  # Return information on the running distro
  #
  my $pbos = pb_distro_get_context();
  print "distro tuple: ".Dumper($pbos->name, $pbos->ver, $pbos->fam, $pbos->type, $pbos->pbsuf, $pbos->pbupd, $pbos->pbins, $pbos->arch)."\n";
  # 
  # Return information on the requested distro
  #
  my $pbos = pb_distro_get_context("ubuntu-7.10-x86_64");
  print "distro tuple: ".Dumper($pbos->name, $pbos->ver, $pbos->fam, $pbos->type, $pbos->pbsuf, $pbos->pbupd, $pbos->pbins, $pbos->arch)."\n";
  # 
  # Return information on the running distro
  #
  my ($ddir,$dver) = pb_distro_get();

=head1 USAGE

=over 4

=item B<pb_distro_conffile>

This function returns the mandatory configuration file used for distribution/OS detection

=cut

sub pb_distro_conffile {

return("CCCC/pb.conf");
}


=item B<pb_distro_init>

This function returns a hash of parameters indicating the distribution name, version, family, type of build system, suffix of packages, update command line, installation command line and architecture of the underlying Linux distribution. The value of the fields may be "unknown" in case the function was unable to recognize on which distribution it is running.

As an example, Ubuntu and Debian are in the same "du" family. As well as RedHat, RHEL, CentOS, fedora are on the same "rh" family.
Mandriva, Open SuSE and Fedora have all the same "rpm" type of build system. Ubuntu and Debian have the same "deb" type of build system. 
And "fc" is the extension generated for all Fedora packages (Version will be added by pb).
All this information is stored in an external configuration file typically at /etc/pb/pb.conf

When passing the distribution name and version as parameters, the B<pb_distro_init> function returns the parameter of that distribution instead of the underlying one.

Cf: http://linuxmafia.com/faq/Admin/release-files.html
Ideas taken from http://search.cpan.org/~kerberus/Linux-Distribution-0.14/lib/Linux/Distribution.pm

=cut


sub pb_distro_init {

my $pbos = {
	'name' => undef,
	'version' => undef,
	'arch' => undef,
	'family' => "unknown",
	'suffix' => "unknown",
	'update' => "unknown",
	'install' => "unknown",
	'type' => "unknown",
	'os' => "unknown",
	'nover' => "false",
	'rmdot' => "false",
	};
$pbos->{'name'} = shift;
$pbos->{'version'} = shift;
$pbos->{'arch'} = shift;

# Adds conf file for distribution description
# the location of the conf file is finalyzed at install time
# depending whether we deal with package install or tar file install
pb_conf_add(pb_distro_conffile());

# If we don't know which distribution we're on, then guess it
($pbos->{'name'},$pbos->{'version'}) = pb_distro_get() if ((not defined $pbos->{'name'}) || (not defined $pbos->{'version'}));

# For some rare cases, typically nover ones
$pbos->{'name'} = "unknown" if (not defined $pbos->{'name'});
$pbos->{'version'} = "unknown" if (not defined $pbos->{'version'});

# Initialize arch
$pbos->{'arch'} = pb_get_arch() if (not defined $pbos->{'arch'});

# Dig into the tuple to find the best answer
# Do NOT factorize here, as it won't work as of now for hash creation
$pbos->{'family'} = pb_distro_get_param($pbos,pb_conf_get("osfamily"));
$pbos->{'type'} = pb_distro_get_param($pbos,pb_conf_get("ostype"));
($pbos->{'os'},$pbos->{'install'},$pbos->{'suffix'},$pbos->{'nover'},$pbos->{'rmdot'},$pbos->{'update'}) = pb_distro_get_param($pbos,pb_conf_get("os","osins","ossuffix","osnover","osremovedotinver","osupd"));
#($pbos->{'family'},$pbos->{'type'},$pbos->{'os'},$pbos->{'install'},$pbos->{'suffix'},$pbos->{'nover'},$pbos->{'rmdot'},$pbos->{'update'}) = pb_distro_get_param($pbos,pb_conf_get("osfamily","ostype","os","osins","ossuffix","osnover","osremovedotinver","osupd"));

# Some OS have no interesting version
$pbos->{'version'} = "nover" if ((defined $pbos->{'nover'}) && ($pbos->{'nover'} eq "true"));

# For some OS remove the . in version name for extension
my $dver2 = $pbos->{'version'};
$dver2 =~ s/\.//g if ((defined $pbos->{'rmdot'}) && ($pbos->{'rmdot'} eq "true"));

if ((not defined $pbos->{'suffix'}) || ($pbos->{'suffix'} eq "")) {
	# By default suffix is a concatenation of name and version
	$pbos->{'suffix'} = ".$pbos->{'name'}$dver2" 
} else {
	# concat just the version to what has been found
	$pbos->{'suffix'} = ".$pbos->{'suffix'}$dver2";
}

#	if ($arch eq "x86_64") {
#	$opt="--exclude=*.i?86";
#	}
pb_log(2,"DEBUG: pb_distro_init: ".Dumper($pbos)."\n");

return($pbos);
}

=item B<pb_distro_get>

This function returns a list of 2 parameters indicating the distribution name and version of the underlying Linux distribution. The value of those 2 fields may be "unknown" in case the function was unable to recognize on which distribution it is running.

On my home machine it would currently report ("mandriva","2010.2").

=cut

sub pb_distro_get {

# 1: List of files that unambiguously indicates what distro we have
# 2: List of files that ambiguously indicates what distro we have
# 3: Should have the same keys as the previous one. If ambiguity, which other distributions should be checked
# 4: Matching Rg. Expr to detect distribution and version
my ($single_rel_files, $ambiguous_rel_files,$distro_similar,$distro_match) = pb_conf_get("osrelfile","osrelambfile","osambiguous","osrelexpr");

my $release;
my $distro;

# Begin to test presence of non-ambiguous files
# that way we reduce the choice
my ($d,$r);
while (($d,$r) = each %$single_rel_files) {
	if (defined $ambiguous_rel_files->{$d}) {
		print STDERR "The key $d is considered as both unambiguous and ambigous.\n";
		print STDERR "Please fix your configuration file.\n"
	}
	if (-f "$r" && ! -l "$r") {
		my $tmp=pb_get_content("$r");
		# Found the only possibility. 
		# Try to get version and return
		if (defined ($distro_match->{$d})) {
			($release) = $tmp =~ m/$distro_match->{$d}/m;
		} else {
			print STDERR "Unable to find $d version in $r (non-ambiguous)\n";
			print STDERR "Please report to the maintainer bruno_at_project-builder.org\n";
			$release = "unknown";
		}
		return($d,$release);
	}
}

# Now look at ambiguous files
# Ubuntu before 10.04 includes a /etc/debian_version file that creates an ambiguity with debian
# So we need to look at distros in reverse alphabetic order to treat ubuntu always first via lsb
foreach $d (reverse keys %$ambiguous_rel_files) {
	$r = $ambiguous_rel_files->{$d};
	if (-f "$r" && !-l "$r") {
		# Found one possibility. 
		# Get all distros concerned by that file
		my $tmp=pb_get_content("$r");
		my $found = 0;
		my $ptr = $distro_similar->{$d};
		pb_log(2,"amb: ".Dumper($ptr)."\n");
		$release = "unknown";
		foreach my $dd (split(/,/,$ptr)) {
                        # TODO-reviwer: unclear how this should be generalized.
                        $tmp = '7.0' if $dd eq 'debian' && $tmp =~ m!wheezy/sid!;
			pb_log(2,"check $dd\n");
			# Try to check pattern
			if (defined $distro_match->{$dd}) {
				pb_log(2,"cmp: $distro_match->{$dd} - vs - $tmp\n");
				($release) = $tmp =~ m/$distro_match->{$dd}/m;
				if ((defined $release) && ($release ne "unknown")) {
					$distro = $dd;
					$found = 1;
					last;
				}
			}
		}
		if ($found == 0) {
			print STDERR "Unable to find $d version in $r (ambiguous)\n";
			print STDERR "Please report to the maintainer bruno_at_project-builder.org\n";
			$release = "unknown";
		} else {
			return($distro,$release);
		}
	}
}
return("unknown","unknown");
}

=item B<pb_distro_getlsb>

This function returns the 5 lsb values LSB version, distribution ID, Description, release and codename.
As entry it takes an optional parameter to specify whether the output is short or not.

=cut

sub pb_distro_getlsb {

my $s = shift;
pb_log(3,"Entering pb_distro_getlsb\n");

my ($ambiguous_rel_files) = pb_conf_get("osrelambfile");
my $lsbf = $ambiguous_rel_files->{"lsb"};

# LSB has not been configured.
if (not defined $lsbf) {
	print STDERR "no lsb entry defined for osrelambfile\n";
	die "You modified upstream delivery and lost !\n";
}

if (-r $lsbf) {
	my $rep = pb_get_content($lsbf);
	# Create elementary fields
	my ($c, $r, $d, $i, $l) = ("", "", "", "", "");
	for my $f (split(/\n/,$rep)) {
		pb_log(3,"Reading file part ***$f***\n");
		$c = $f if ($f =~ /^DISTRIB_CODENAME/);
		$c =~ s/DISTRIB_CODENAME=/Codename:\t/;
		$r = $f if ($f =~ /^DISTRIB_RELEASE/);
		$r =~ s/DISTRIB_RELEASE=/Release:\t/;
		$d = $f if ($f =~ /^DISTRIB_DESCRIPTION/);
		$d =~ s/DISTRIB_DESCRIPTION=/Description:\t/;
		$d =~ s/"//g;
		$i = $f if ($f =~ /^DISTRIB_ID/);
		$i =~ s/DISTRIB_ID=/Distributor ID:\t/;
		$l = $f if ($f =~ /^LSB_VERSION/);
		$l =~ s/LSB_VERSION=/LSB Version:\t/;
	}
	my $regexp = "^[A-z ]*:[\t ]*";
	$c =~ s/$regexp// if (defined $s);
	$r =~ s/$regexp// if (defined $s);
	$d =~ s/$regexp// if (defined $s);
	$i =~ s/$regexp// if (defined $s);
	$l =~ s/$regexp// if (defined $s);
	return($l, $i, $d, $r, $c);
} else {
	print STDERR "Unable to read $lsbf file\n";
	die "Please report to the maintainer bruno_at_project-builder.org\n";
}
}

sub internal_apply_conf_proxy ($) {
my ($pbos) = @_;
my ($ftp_proxy_map, $http_proxy_map) = pb_conf_get_if('ftp_proxy', 'http_proxy');
my $ftp_proxy = pb_distro_get_param($pbos, $ftp_proxy_map);
my $http_proxy = pb_distro_get_param($pbos, $http_proxy_map);

# TODO-reviewer: ||= or =?  Former lets shell settings apply, latter makes config file win.
# Note that during the setupve step we do not have the config file available so = would be bad, but
# = if defined would be ok.
$ENV{ftp_proxy} ||= $ftp_proxy;
$ENV{http_proxy} ||= $http_proxy;
}

=item B<pb_distro_installdeps>

This function install the dependencies required to build the package on a distro.
Dependencies can be passed as a parameter in which case they are not computed

=cut

sub pb_distro_installdeps {

# SPEC file
my $f = shift || undef;
my $pbos = shift;
my $deps = shift || undef;

die "Missing install command for $pbos->{name}-$pbos->{version}-$pbos->{arch}"
       unless defined $pbos->{install} && $pbos->{install} =~ /\w/;
internal_apply_conf_proxy($pbos);
my ($hook_map) = pb_conf_get_if('install_deps_hook');
my $hook = pb_distro_get_param($pbos, $hook_map);

# Get dependencies in the build file if not forced
$deps = pb_distro_getdeps($f, $pbos) if (not defined $deps);
if (defined $hook && $hook ne '') {
        pb_system($hook, "Running install_deps_hook '$hook'");
} else {
        pb_log(1, "No install_deps_hook defined.\n");
}
pb_log(1, "ftp_proxy=$ENV{ftp_proxy} http_proxy=$ENV{http_proxy}\n");
pb_log(2,"deps: $deps\n");
return if ((not defined $deps) || ($deps =~ /^\s*$/));
# This may not be // proof. We should test for availability of repo and sleep if not
my $cmd = "$pbos->{'install'} $deps";
my $ret = pb_system($cmd, "Installing dependencies ($cmd)", undef, 1);
if ($ret != 0) {
        pb_system($cmd, "Re-trying installing dependencies ($cmd)");
}
$deps = pb_distro_getdeps($f, $pbos);
die "Some dependencies did not install ($deps)" if defined $deps && $deps =~ /\S/;
}

=item B<pb_distro_getdeps>

This function computes the dependencies indicated in the build file and return them as a string of packages to install

=cut

sub pb_distro_getdeps {

my $f = shift || undef;
my $pbos = shift;

my $regexp = "";
my $deps = "";
my $sep = $/;

# Protection
return("") if (not defined $pbos->{'type'});
return("") if (not defined $f);

pb_log(3,"entering pb_distro_getdeps: $pbos->{'type'} - $f\n");
if ($pbos->{'type'} eq  "rpm") {
	# In RPM this could include files, but we do not handle them atm.
	$regexp = '^BuildRequires:(.*)$';
} elsif ($pbos->{'type'} eq "deb") {
	$regexp = '^Build-Depends:(.*)$';
} elsif ($pbos->{'type'} eq "ebuild") {
	$sep = '"'.$/;
	$regexp = '^DEPEND="(.*)"\n'
} else {
	# No idea
	return("");
}
pb_log(2,"regexp: $regexp\n");

# Preserve separator before using the one we need
my $oldsep = $/;
$/ = $sep;
open(DESC,"$f") || die "Unable to open $f";
while (<DESC>) {
	pb_log(4,"read: $_\n");
	next if (! /$regexp/);
	chomp();

        my $nextline;
        if ($pbos->{type} eq 'deb') {
                while ($nextline = <DESC>) {
                        last unless $nextline =~ /^\s+(.+)$/o;
                        $_ .= $1;
                }
        }
	# What we found with the regexp is the list of deps.
	pb_log(2,"found deps: $_\n");
	s/$regexp/$1/i;
	# Remove conditions in the middle and at the end for deb
	s/\(\s*[><=]+.*\)[^,]*,/,/g;
	s/\(\s*[><=]+.*$//g;
	# Same for rpm
	s/[><=]+[^,]*,/,/g;
	s/[><=]+.*$//g;
	# Improve string format (remove , and spaces at start, end and in double
	s/,/ /g;
	s/^\s*//;
	s/\s*$//;
	s/\s+/ /g;
	$deps .= " ".$_;
        if (defined $nextline) {
                $_ = $nextline;
                redo;
        }
}
close(DESC);
$/ = $oldsep;
pb_log(2,"now deps: $deps\n");
my $deps2 = pb_distro_only_deps_needed($pbos,$deps);
return($deps2);
}


=item B<pb_distro_only_deps_needed>

This function returns only the dependencies not yet installed

=cut

sub pb_distro_only_deps_needed {

my $pbos = shift;
my $deps = shift || undef;

return("") if ((not defined $deps) || ($deps =~ /^\s*$/));
my $deps2 = "";
# Avoid to install what is already there
foreach my $p (split(/\s+/,$deps)) {
        next if $p =~ /^\s*$/o;
	if ($pbos->{'type'} eq  "rpm") {
		my $res = pb_system("rpm -q --whatprovides --quiet $p","","quiet", 1);
		next if ($res eq 0);
	} elsif ($pbos->{'type'} eq "deb") {
                my $fh = new FileHandle "dpkg -l $p |" or die "Unable to run dpkg -l $p: $!";
                my $ok = 0;
                while (<$fh>) {
                        $ok = 1 if /^ii\s+$p/;
                }
                next if $ok;
	} elsif ($pbos->{'type'} eq "ebuild") {
	} else {
		# Not reached
	}
	pb_log(2,"found deps2: $p\n");
	$deps2 .= " $p";
}

$deps2 =~ s/^\s*//;
pb_log(2,"now deps2: $deps2\n");
return($deps2);
}

=item B<pb_distro_setuposrepo>

This function sets up potential additional repository for the setup phase

=cut

sub pb_distro_setuposrepo {

my $pbos = shift;

pb_distro_setuprepo_gen($pbos,pb_distro_conffile(),"osrepo");
}

=item B<pb_distro_setuprepo>

This function sets up potential additional repository to the build environment

=cut

sub pb_distro_setuprepo {

my $pbos = shift;

pb_distro_setuprepo_gen($pbos,"$ENV{'PBDESTDIR'}/pbrc","addrepo");
}

=item B<pb_distro_setuprepo_gen>

This function sets up in a generic way potential additional repository 

=cut

sub pb_distro_setuprepo_gen {

my $pbos = shift;
my $pbconf = shift || undef;
my $pbkey = shift || undef;

return if (not defined $pbconf);
return if (not defined $pbkey);
my ($addrepo) = pb_conf_read($pbconf,$pbkey);
return if (not defined $addrepo);

my $param = pb_distro_get_param($pbos,$addrepo);
return if ($param eq "");

internal_apply_conf_proxy($pbos);

# Loop on the list of additional repo
foreach my $i (split(/,/,$param)) {

	my ($scheme, $account, $host, $port, $path) = pb_get_uri($i);
	my $bn = basename($i);

	# The repo file can be local or remote. download or copy at the right place
	if (($scheme eq "ftp") || ($scheme eq "http")) {
		pb_system("wget -O $ENV{'PBTMP'}/$bn $i","Downloading additional repository file $i");
	} else {
		copy($i,$ENV{'PBTMP'}/$bn);
	}

	# The repo file can be a real file or a package
	if ($pbos->{'type'} eq "rpm") {
		if ($bn =~ /\.rpm$/) {
			my $pn = $bn;
			$pn =~ s/\.rpm//;
			if (pb_system("rpm -q --quiet $pn","","quiet", 1) != 0) {
				pb_system("sudo rpm -Uvh $ENV{'PBTMP'}/$bn","Adding package to setup repository");
			}
		} elsif ($bn =~ /\.repo$/) {
			# Yum repo
			pb_system("sudo mv $ENV{'PBTMP'}/$bn /etc/yum.repos.d","Adding yum repository") if (not -f "/etc/yum.repos.d/$bn");
		} elsif ($bn =~ /\.addmedia/) {
			# URPMI repo
			# We should test that it's not already a urpmi repo
			pb_system("chmod 755 $ENV{'PBTMP'}/$bn ; sudo $ENV{'PBTMP'}/$bn 2>&1 > /dev/null","Adding urpmi repository");
		} else {
			pb_log(0,"Unable to deal with repository file $i on rpm distro ! Please report to dev team\n");
		}
	} elsif ($pbos->{'type'} eq "deb") {
		if ($bn =~ /\.sources.list$/) {
                        my $dest = "/etc/apt/sources.list.d/$bn";
                        if (! -f $dest) {
                                pb_log(1, "Installing new file $dest");
                        } elsif (-f $dest && -s $dest == 0) {
                                pb_log(1, "Overwriting empty file $dest");
                        } elsif (-f $dest && compare("$ENV{PBTMP}/$bn", $dest) == 0) {
                                pb_log(1, "Overwriting identical file $dest");
                        } else {
                                pb_log(0, "ERROR: destination file $dest exists and is different than source $ENV{PBTMP}/$bn\n");
                                print "Dest...\n";
                                system("cat $dest");
                                print "New...\n";
                                system("cat $ENV{PBTMP}/$bn");
                                print "Returning...\n";
                                return;
                        }
			pb_system("sudo mv $ENV{'PBTMP'}/$bn /etc/apt/sources.list.d","Adding apt repository");
			pb_system("sudo apt-get update","Updating apt repository");
		} else {
			pb_log(0,"Unable to deal with repository file $i on deb distro ! Please report to dev team\n");
		}
	} else {
		pb_log(0,"Unable to deal with repository file $i on that distro ! Please report to dev team\n");
	}
}
return;
}

=item B<pb_distro_get_param>

This function gets the parameter in the conf file from the most precise tuple up to default

=cut

sub pb_distro_get_param {

my @param;
my $param;
my $pbos = shift;

pb_log(2,"DEBUG: pb_distro_get_param on $pbos->{'name'}-$pbos->{'version'}-$pbos->{'arch'} for ".Dumper(@_)."\n");
foreach my $opt (@_) {
	if (defined $opt->{"$pbos->{'name'}-$pbos->{'version'}-$pbos->{'arch'}"}) {
		$param = $opt->{"$pbos->{'name'}-$pbos->{'version'}-$pbos->{'arch'}"};
	} elsif (defined $opt->{"$pbos->{'name'}-$pbos->{'version'}"}) {
		$param = $opt->{"$pbos->{'name'}-$pbos->{'version'}"};
	} elsif (defined $opt->{"$pbos->{'name'}"}) {
		$param = $opt->{"$pbos->{'name'}"};
	} elsif (defined $opt->{$pbos->{'family'}}) {
		$param = $opt->{$pbos->{'family'}};
	} elsif (defined $opt->{$pbos->{'type'}}) {
		$param = $opt->{$pbos->{'type'}};
	} elsif (defined $opt->{$pbos->{'os'}}) {
		$param = $opt->{$pbos->{'os'}};
	} elsif (defined $opt->{"default"}) {
		$param = $opt->{"default"};
	} else {
		$param = "";
	}

	# Allow replacement of variables inside the parameter such as name, version, arch for rpmbootstrap 
	# but not shell variable which are backslashed
	if ($param =~ /[^\\]\$/) {
		pb_log(3,"Expanding variable on $param\n");
		eval { $param =~ s/(\$\w+->{\'\w+\'})/$1/eeg };
	}
	push @param,$param;
}

pb_log(2,"DEBUG: pb_distro_get_param on $pbos->{'name'}-$pbos->{'version'}-$pbos->{'arch'} returns ==".Dumper(@param)."==\n");

# Return one param in scalar context, an array if not.
my $nb = @param;
if ($nb eq 1) {
	return($param);
} else {
	return(@param);
}
}

=item B<pb_distro_get_context>

This function gets the OS context passed as parameter and return the corresponding distribution hash
If passed undef or "" then auto-detects

=cut


sub pb_distro_get_context {

my $os = shift;
my $pbos;

if ((defined $os) && ($os ne "")) {
	my ($name,$ver,$darch) = split(/-/,$os);
	pb_log(0,"Bad format for $os") if ((not defined $name) || (not defined $ver) || (not defined $darch)) ;
	chomp($darch);
	$pbos = pb_distro_init($name,$ver,$darch);
} else {
	$pbos = pb_distro_init();
}
return($pbos);
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
