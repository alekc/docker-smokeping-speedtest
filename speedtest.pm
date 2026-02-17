package Smokeping::probes::speedtest;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command

C<smokeping -man Smokeping::probes::speedtest>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::speedtest>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use IPC::Open3;
use Symbol;
use Carp;
use Sys::Syslog qw(:standard :macros);;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::speedtest - Execute tests via Speedtest.net (Ookla)
DOC
		description => <<DOC,
Integrates L<speedtest|https://www.speedtest.net/apps/cli> (official Ookla client) as a probe into smokeping. The variable B<binary> must
point to your copy of the speedtest program. If it is not installed on
your system yet, you should install the latest version from L<https://www.speedtest.net/apps/cli>.

The Probe asks for the given resource one time, ignoring the pings config variable (because pings can't be lower than 3).

You can ask for a specific server (via the server parameter) and record a specific output (via the measurement parameter).

DOC
		authors => <<'DOC',
 Adrian Popa <mad_ady@yahoo.com>
DOC
	};
}

#Set up syslog to write to local0
openlog("speedtest", "nofatal, pid", "local0");
#set to LOG_ERR to disable debugging, LOG_DEBUG to enable debugging
setlogmask(LOG_MASK(LOG_ERR));

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {

        #check for dependencies
        my $call = "$self->{properties}{binary} --version";
        my $return = `$call 2>&1`;
        if ($return =~ /speedtest ([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:\.[0-9]+)?)/){
            print "### parsing $self->{properties}{binary} output... OK (version $1)\n";
            syslog("debug", "[Speedtest] Init: version $1");
        } else {
            croak "ERROR: output of '$call' does not return a meaningful version number. Is speedtest (Ookla) installed?\n";
        }
    };

    return $self;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'binary' ],
		binary => {
			_doc => "The location of your speedtest binary (Ookla).",
			_example => '/usr/bin/speedtest',
			_sub => sub {
				my $val = shift;
        			return "ERROR: speedtest 'binary' does not point to an executable"
            				unless -f $val and -x _;
				return undef;
			},
		},
	});
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		server => { _doc => "The server id you want to test against (optional). If unspecified, speedtest.net will select the closest server to you. The value has to be an id reported by the command speedtest -L",
			    _example => "1234",
		},
        measurement => { _doc => "What output do you want graphed? Supported values are: ping, download, upload",
                    _example => "download",
        },
	extraargs => { _doc => "Append extra arguments to the speedtest command line",
                    _example => "--interface=eth0",
        },
	});
}

sub ProbeDesc($){
    my $self = shift;
    return "Ookla speedtest.net download/upload speeds";
}

sub ProbeUnit($){
    my $self = shift;
    #TODO: We need to know if we are measuring bps or seconds - depending on measurement (or maybe on probe name).
    return "bps";
}

sub pingone ($){
    my $self = shift;
    my $target = shift;

    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;

    my $server = $target->{vars}{server} || undef; #if server is not provided, use the default one recommended by speedtest.
    my $measurement = $target->{vars}{measurement} || "download"; #record download speeds if nothing is returned
    my $extra = $target->{vars}{extraargs} || ""; #append extra arguments if neded
    my $query = "$self->{properties}{binary} ".((defined($server))?"--server-id=$server":"")." -f json --accept-license --accept-gdpr $extra 2>&1";

    my @times;

    $self->do_debug("query=$query\n");
    syslog("debug", "[Speedtest] query=$query");
#    for (my $run = 0; $run < $self->pings($target); $run++) {
	my $pid = open3($inh,$outh,$errh, $query);
	while (<$outh>) {
        $self->do_debug("output: ".$_);
        syslog("debug", "[Speedtest] output: ".$_);

        # Parse JSON output from Ookla speedtest
        # {"ping":{"jitter":0.42,"latency":5.123},"download":{"bandwidth":112140288,"bytes":1234567,"elapsed":10001},"upload":{"bandwidth":56070144,"bytes":654321,"elapsed":9876}}

        if ($measurement eq "ping") {
            # Extract ping latency in milliseconds
            my ($value) = /"ping":\{"jitter":[0-9.]+,"latency":([0-9.]+)/;
            if (defined $value) {
                my $normalizedvalue = $value; # already in milliseconds
                $self->do_debug("Got value: $value ms -> $normalizedvalue\n");
                syslog("debug","[Speedtest] Got value: $value ms -> $normalizedvalue\n");
                push @times, $normalizedvalue;
                last;
            }
        } elsif ($measurement eq "download") {
            # Extract download bandwidth in bytes/sec and convert to bits/sec
            my ($value) = /"download":\{"bandwidth":([0-9]+)/;
            if (defined $value) {
                my $normalizedvalue = $value * 8; # convert bytes/sec to bits/sec
                $self->do_debug("Got value: $value bytes/s -> $normalizedvalue bits/s\n");
                syslog("debug","[Speedtest] Got value: $value bytes/s -> $normalizedvalue bits/s\n");
                push @times, $normalizedvalue;
                last;
            }
        } elsif ($measurement eq "upload") {
            # Extract upload bandwidth in bytes/sec and convert to bits/sec
            my ($value) = /"upload":\{"bandwidth":([0-9]+)/;
            if (defined $value) {
                my $normalizedvalue = $value * 8; # convert bytes/sec to bits/sec
                $self->do_debug("Got value: $value bytes/s -> $normalizedvalue bits/s\n");
                syslog("debug","[Speedtest] Got value: $value bytes/s -> $normalizedvalue bits/s\n");
                push @times, $normalizedvalue;
                last;
            }
        }
	}
	waitpid $pid,0;
	close $errh;
	close $inh;
	close $outh;
#    }
    #we run only one test (in order not to get banned too soon), so we ignore pings and have to return the correct number of values. Uncomment the above for loop if you want the actual testing to be done $ping times.
    my $value = $times[0];
    @times = ();
    for(my $run = 0; $run < $self->pings($target); $run++) {
        push @times, $value;
    }

    @times = map {sprintf "%.10e", $_ } sort {$a <=> $b} grep {$_ ne "-"} @times;

    $self->do_debug("time=@times\n");
    syslog("debug", "[Speedtest] time=@times");
    return @times;
}
1;