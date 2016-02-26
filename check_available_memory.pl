#!/usr/bin/perl -w

#========================================================================
#
# Nagios plugin "check_available_memory"
#
# - provides a better estimate of "free" memory than standard plugins
# - uses the kernel's "MemAvailable" metric
# - degrades gracefully to less accurate metrics if this isn't present
#    (1st choice) MemAvailable
#    (2nd choice) MemFree + Buffers + Cached + SReclaimable
#    (3rd choice) MemFree + Buffers + Cached
#
# Usage examples:
# - standard Nagios parameters.  NB lower limits, so "x:" format.
# - both verbose "-v" and very verbose "-vv" return more detail.
#
# $ ./check_available_memory.pl -w 25: -c 10:
# $ ./check_available_memory.pl --warning=25: --critical=10:


use strict;
use Getopt::Long;
use File::Basename;

# We need either Nagios::Plugin or Monitoring::Plugin
# Availability depends on platform (e.g. Nagios::Plugin on AMI, 
#   Monitoring::Plugin on RHEL) so we load whatever we can find.

# These are available in packages:
#   .rpm: "perl-Nagios-Plugin" / "perl-Monitoring-Plugin"
#   .deb: "libnagios-plugin-perl"

# Note: if you want to package this into an RPM, be aware that rpmbuild 
#  might infer that both options are required.
# TODO: find a more elegant way to handle this than hacking the script





#Initialisation
#===============

my $DEBUG=0;
my $VERSION = "1.0";


chomp (my $PROGRAM_NAME = basename($0));
my $USAGE = "usage: $PROGRAM_NAME [--warning=<level>:] [--critical=<level>:]"; 
my $plugin_name = $PROGRAM_NAME;
$plugin_name =~ s/.pl$//;

my ($np, $UNKNOWN);
# prefer Monitoring::Plugin, because Nagios::Plugin whinges on new installs
my $HAVE_MONITORING_PLUGIN = eval
{
	require Monitoring::Plugin;
	Monitoring::Plugin->import();
	$UNKNOWN = Monitoring::Plugin->UNKNOWN;
	1;
};
if ($HAVE_MONITORING_PLUGIN) {
	$np = Monitoring::Plugin->new(shortname => $plugin_name, version => $VERSION, usage => $USAGE);
} else {
	my $HAVE_NAGIOS_PLUGIN = eval
	{
		require Nagios::Plugin;
		Nagios::Plugin->import();
		$UNKNOWN = Nagios::Plugin->UNKNOWN;
		1;
	};
	if($HAVE_NAGIOS_PLUGIN) {
		$np = Nagios::Plugin->new(shortname => $plugin_name, version => $VERSION, usage => $USAGE);
	} else {
		print "$plugin_name UNKNOWN - unable to load either Nagios::Plugin or Monitoring::Plugin\n";
		exit 3;
	}
}

# catch die
$SIG{__DIE__} = sub 
{
    $np->nagios_exit($UNKNOWN, join("", @_));
};


$np->add_arg(
     spec => 'warning|w=s',
     help => '-w, --warning=INT:INT e.g. "--warning=25:" - exit with warning status if less than 25% memory available',
     default => "25:",
   );
$np->add_arg(
     spec => 'critical|c=s',
     help => '-c, --critical=INT:INT (formatted as warning)',
     default => "10:",
   );
   
# Parse @ARGV and process standard arguments (e.g. usage, help, version)
$np->getopts();

# respect timeout (not that this is likely in this particular plugin)
alarm ($np->opts->timeout());

my $VERBOSITY=0;
if ($np->opts->get('verbose')) {
	$VERBOSITY = $np->opts->verbose;
}


# parse /proc/meminfo
my ($percentage_available, $description, $verbose) = parse_meminfo(`cat /proc/meminfo`);

# nagios thresholds
my $nagios_code = $np->check_threshold($percentage_available);
my $threshold_warning = $np->opts->warning || "";
my $threshold_critical = $np->opts->critical || "";


if ($VERBOSITY >= 1) {
	$description .= " $verbose";
}


$np->nagios_exit($nagios_code, 
	"$description"
	." | available_memory=$percentage_available%;$threshold_warning;$threshold_critical;0;100");


#=============================================================================


sub parse_meminfo {
	my $meminfo = shift or die;

	# fields we really need
	my @REQUIRED_FIELDS=qw(MemTotal MemFree Buffers Cached);

	# fields we'd like to see
	my @FIELDS=( qw(MemAvailable SReclaimable),  @REQUIRED_FIELDS);


	my %values;

	for my $line (`cat /proc/meminfo`)  {
		if (my ($name, $value) = ($line=~/^(\S+):\s+(\d+)\skB$/)) {
	#		print "$name, $value\n";
			$values{$name} = $value if grep (/$name/, @FIELDS);
		}
	}

	# debug
	if ($VERBOSITY >= 2) {
		print "fields:\n";
		while (my($x, $y) = each %values) {
			print "$x $y\n";
		}
		print "\n";
	}

	# things we really expect to see
	for my $field (@REQUIRED_FIELDS) {
		die "unable to read field \"$field\" from /proc/meminfo" unless defined $values{$field};
	}

	my $total_memory = $values{MemTotal};
	print "MemTotal: $total_memory\n" if $VERBOSITY >= 2;
	
	my $available_memory = undef;	# our reading (or estimate) of available memory
	my $available_memory_method = undef;	# how we got the estimate
	
	# our first preference is always to use MemAvailable
	if (defined $values{MemAvailable}) {
		$available_memory = $values{MemAvailable};
		$available_memory_method = "MemAvailable";
		print "MemAvailable: $available_memory\n" if $VERBOSITY >= 2;
	}
	# otherwise we'll use free+buffers+cached
	else {
		$available_memory = $values{MemFree} + $values{Buffers} + $values{Cached};
		$available_memory_method = "MemFree+Buffers+Cached";
		print "MemFree + Buffers + Cached = $available_memory\n" if $VERBOSITY >= 2;

		# and if Slab Reclaimable is available, add this
		if (defined $values{SReclaimable}) {
			$available_memory += $values{SReclaimable};
			
			$available_memory_method = "MemFree+Buffers+Cached+SReclaimable";
			print "MemFree + Buffers + Cached + SReclaimable= $available_memory\n" if $VERBOSITY >= 2;
		}
	}

	die unless $available_memory_method;
	die unless defined $available_memory;
	
	my $percentage_available = int ($available_memory / $total_memory * 1000)/10;
	
	my $available_memory_MB = int ($available_memory/1024);
	my $description = "$percentage_available% (${available_memory_MB}MB) memory available";
		
	return ($percentage_available, $description, "(via $available_memory_method)");
}

