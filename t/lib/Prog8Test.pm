package Prog8Test;
use strict;
use warnings;
use Exporter 'import';
use File::Temp qw(tempdir);
use File::Spec;
use POSIX qw(setpgid);
our @EXPORT_OK = qw(run_suite);

# Run argv directly, with combined output and a deadline (including the VM).
sub capture {
    my ($log, @argv) = @_;
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if (!$pid) {
        setpgid(0, 0) or die "setpgid: $!";
        open STDOUT, '>', $log or die "$log: $!";
        open STDERR, '>&', \*STDOUT or die "stderr: $!";
        exec { $argv[0] } @argv;
        die "exec $argv[0]: $!";
    }
    my $status;
    my $finished = eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 60;
        waitpid($pid, 0);
        $status = $?;
        alarm 0;
        1;
    };
    if (!$finished) {
        alarm 0;
        kill 'KILL', -$pid;
        kill 'KILL', $pid;
        waitpid($pid, 0);
        $status = 124 << 8;
    }
    open my $fh, '<', $log or die "$log: $!";
    local $/;
    my $output = <$fh> // '';
    close $fh;
    return ($status, $output);
}

sub bail {
    my ($why, $output) = @_;
    $output =~ s/\e\[[0-9;]*m//g;
    print "# $_\n" for split /\n/, $output;
    print "Bail out! $why\n";
    exit 1;
}

sub run_suite {
    my ($source, $target) = @_;
    $target //= 'virtual';
    my $jar = $ENV{JAR} // 'prog8c-14.0-BETA3-all.jar';
    my $java = $ENV{JAVA} // 'java';
    my $dir = tempdir('xvi2-test-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    my @compiler = ($java, '-jar', $jar);
    my @paths = $target ne 'virtual'
        ? ('-srcdirs', "src/$target", '-srcdirs', "t/support/$target")
        : ('-srcdirs', 't/support');
    my ($status, $output) = capture("$dir/compile.log", @compiler,
        '-noopt', '-target', $target, '-srcdirs', 'src',
        @paths, '-out', $dir, $source);
    bail('Prog8 test compilation failed or timed out', $output) if $status;
    (my $name = $source) =~ s{.*/}{};
    $name =~ s/\.p8$//;
    $name .= $target ne 'virtual' ? '.prg' : '.p8ir';
    my $ir = File::Spec->catfile($dir, $name);
    bail('compiler did not produce test output', $output) unless -s $ir;
    my @run = $target eq 'cx16'
        ? ('python3', 't/run_x16.py', $ir)
        : $target eq 'c64' ? ('python3', 't/run_vice.py', $ir)
        : (@compiler, '-vm', $ir);
    ($status, $output) = capture("$dir/run.log", @run);
    my $complete = $target eq 'cx16'
        ? $output =~ /^# X16 test program completed$/m
        : $target eq 'c64' ? $output =~ /^# C64 test program completed$/m
        : $output =~ /^Program exit! Statuscode=0\b/m;
    bail('test execution failed or timed out', $output) if $status || !$complete;
    # Keep TAP from the P8 program verbatim; make compiler/VM chatter diagnostic.
    for my $line (split /\n/, $output) {
        if ($line =~ /^(?:(?:not )?ok\b|1\.\.[0-9]+\b|Bail out!|#)/) {
            print "$line\n";
        } elsif (length $line) {
            print "# $line\n";
        }
    }
}
1;
