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
use Sys::Syslog qw(:standard :macros);
use Fcntl qw(:flock);
use File::Spec;
use Digest::MD5 qw(md5_hex);

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

# Cache directory for storing speedtest results
my $CACHE_DIR = $ENV{'SMOKEPING_SPEEDTEST_CACHE'} || '/tmp/smokeping-speedtest-cache';
# Cache validity period in seconds (default: 60 seconds)
my $CACHE_TTL = 60;

sub _get_cache_key {
    my ($self, $target) = @_;
    my $server = $target->{vars}{server} || "default";
    my $binary = $self->{properties}{binary};
    # Create a unique key based on server and binary path
    return md5_hex("$binary-$server");
}

sub _get_cache_path {
    my ($self, $cache_key) = @_;
    mkdir($CACHE_DIR, 0755) unless -d $CACHE_DIR;
    return File::Spec->catfile($CACHE_DIR, "$cache_key.cache");
}

sub _read_cache {
    my ($self, $target) = @_;

    my $cache_key = $self->_get_cache_key($target);
    my $cache_file = $self->_get_cache_path($cache_key);

    return undef unless -f $cache_file;

    # Try to open and lock the cache file
    if (open(my $fh, '<', $cache_file)) {
        flock($fh, LOCK_SH) or do {
            close($fh);
            return undef;
        };

        # Read cache content
        my $content = do { local $/; <$fh> };
        flock($fh, LOCK_UN);
        close($fh);

        # Parse cache: timestamp|json_data
        if ($content =~ /^(\d+)\|(.+)$/s) {
            my ($timestamp, $json) = ($1, $2);
            my $age = time() - $timestamp;

            if ($age < $CACHE_TTL) {
                $self->do_debug("[Speedtest] Cache hit (age: ${age}s)\n");
                syslog("debug", "[Speedtest] Cache hit for key $cache_key (age: ${age}s)");
                return $json;
            } else {
                $self->do_debug("[Speedtest] Cache expired (age: ${age}s)\n");
                syslog("debug", "[Speedtest] Cache expired for key $cache_key (age: ${age}s)");
            }
        }
    }

    return undef;
}

sub _write_cache {
    my ($self, $target, $json_data) = @_;

    my $cache_key = $self->_get_cache_key($target);
    my $cache_file = $self->_get_cache_path($cache_key);

    # Open with exclusive lock for writing
    if (open(my $fh, '>', $cache_file)) {
        flock($fh, LOCK_EX) or do {
            close($fh);
            return 0;
        };

        my $timestamp = time();
        print $fh "$timestamp|$json_data";

        flock($fh, LOCK_UN);
        close($fh);

        $self->do_debug("[Speedtest] Cache written\n");
        syslog("debug", "[Speedtest] Cache written for key $cache_key");
        return 1;
    }

    return 0;
}

sub _run_speedtest {
    my ($self, $target) = @_;

    my $server = $target->{vars}{server} || undef;
    my $extra = $target->{vars}{extraargs} || "";
    my $query = "$self->{properties}{binary} ".((defined($server))?"--server-id=$server":"")." -f json --accept-license --accept-gdpr $extra 2>&1";

    $self->do_debug("[Speedtest] Running: $query\n");
    syslog("debug", "[Speedtest] Running: $query");

    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;

    my $pid = open3($inh, $outh, $errh, $query);
    my $json_output = '';

    while (<$outh>) {
        $self->do_debug("[Speedtest] output: ".$_);
        syslog("debug", "[Speedtest] output: ".$_);
        $json_output .= $_;
    }

    waitpid $pid, 0;
    close $errh;
    close $inh;
    close $outh;

    return $json_output;
}

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
        if ($return =~ /speedtest.*?([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:\.[0-9]+)?)/i){
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

    my $measurement = $target->{vars}{measurement} || "download";
    my @times;

    # Try to get cached result first
    my $json_output = $self->_read_cache($target);

    # If no cache or cache expired, run speedtest
    if (!defined $json_output) {
        $self->do_debug("[Speedtest] No valid cache, running speedtest\n");
        syslog("debug", "[Speedtest] No valid cache, running speedtest");

        $json_output = $self->_run_speedtest($target);

        # Cache the result for future use
        $self->_write_cache($target, $json_output);
    }

    # Parse the JSON output based on measurement type
    if ($measurement eq "ping") {
        # Extract ping latency in milliseconds
        if ($json_output =~ /"ping":\s*\{\s*"jitter":\s*[0-9.]+\s*,\s*"latency":\s*([0-9.]+)/s) {
            my $value = $1;
            my $normalizedvalue = $value; # already in milliseconds
            $self->do_debug("[Speedtest] Got ping value: $value ms -> $normalizedvalue\n");
            syslog("debug","[Speedtest] Got ping value: $value ms -> $normalizedvalue\n");
            push @times, $normalizedvalue;
        }
    } elsif ($measurement eq "download") {
        # Extract download bandwidth in bytes/sec and convert to bits/sec
        if ($json_output =~ /"download":\s*\{\s*"bandwidth":\s*([0-9]+)/s) {
            my $value = $1;
            my $normalizedvalue = $value * 8; # convert bytes/sec to bits/sec
            $self->do_debug("[Speedtest] Got download value: $value bytes/s -> $normalizedvalue bits/s\n");
            syslog("debug","[Speedtest] Got download value: $value bytes/s -> $normalizedvalue bits/s\n");
            push @times, $normalizedvalue;
        }
    } elsif ($measurement eq "upload") {
        # Extract upload bandwidth in bytes/sec and convert to bits/sec
        if ($json_output =~ /"upload":\s*\{\s*"bandwidth":\s*([0-9]+)/s) {
            my $value = $1;
            my $normalizedvalue = $value * 8; # convert bytes/sec to bits/sec
            $self->do_debug("[Speedtest] Got upload value: $value bytes/s -> $normalizedvalue bits/s\n");
            syslog("debug","[Speedtest] Got upload value: $value bytes/s -> $normalizedvalue bits/s\n");
            push @times, $normalizedvalue;
        }
    }

    # We run only one test (in order not to get banned too soon), so we ignore pings
    # and have to return the correct number of values.
    my $value = $times[0];
    @times = ();
    for(my $run = 0; $run < $self->pings($target); $run++) {
        push @times, $value;
    }

    @times = map {sprintf "%.10e", $_ } sort {$a <=> $b} grep {$_ ne "-"} @times;

    $self->do_debug("[Speedtest] time=@times\n");
    syslog("debug", "[Speedtest] time=@times");
    return @times;
}
1;