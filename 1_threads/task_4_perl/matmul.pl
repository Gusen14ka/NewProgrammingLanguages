#!/usr/bin/perl
use strict;
use warnings;
use Time::HiRes qw(time);

my $n       = $ARGV[0] // 200;
my $workers = $ARGV[1] // 4;

srand(42);
my @a = map { [ map { int(rand(10)) } 1 .. $n ] } 1 .. $n;
my @b = map { [ map { int(rand(10)) } 1 .. $n ] } 1 .. $n;

sub multiply_rows {
    my ($from, $to) = @_;
    my @rows;
    for my $i ($from .. $to) {
        my @row = (0) x $n;
        my $ai  = $a[$i];
        for my $k (0 .. $n - 1) {
            my $aik = $ai->[$k];
            next unless $aik;
            my $bk = $b[$k];
            $row[$_] += $aik * $bk->[$_] for 0 .. $n - 1;
        }
        push @rows, \@row;
    }
    return @rows;
}

my $t0  = time;
my @seq = multiply_rows(0, $n - 1);
my $seq_time = time - $t0;

$t0 = time;
my $chunk = int(($n + $workers - 1) / $workers);
my @jobs;
for my $w (0 .. $workers - 1) {
    my $from = $w * $chunk;
    last if $from >= $n;
    my $to = $from + $chunk - 1;
    $to = $n - 1 if $to > $n - 1;

    pipe(my $reader, my $writer) or die "pipe: $!";
    my $pid = fork() // die "fork: $!";
    if ($pid == 0) {
        close $reader;
        print {$writer} join(' ', @$_), "\n" for multiply_rows($from, $to);
        close $writer;
        exit 0;
    }
    close $writer;
    push @jobs, { pid => $pid, reader => $reader, from => $from };
}

my @par;
for my $job (@jobs) {
    my $i = $job->{from};
    my $fh = $job->{reader};
    while (my $line = <$fh>) {
        chomp $line;
        $par[$i++] = [ split / /, $line ];
    }
    close $fh;
    waitpid($job->{pid}, 0);
}
my $par_time = time - $t0;

my $equal = 1;
OUTER: for my $i (0 .. $n - 1) {
    for my $j (0 .. $n - 1) {
        if ($seq[$i][$j] != $par[$i][$j]) { $equal = 0; last OUTER; }
    }
}

printf "Matrix size: %dx%d, processes: %d\n", $n, $n, scalar @jobs;
printf "Sequential: %8.1f ms\n", $seq_time * 1000;
printf "Parallel:   %8.1f ms\n", $par_time * 1000;
printf "Speedup:    x%.2f\n", $seq_time / $par_time;
printf "Results equal: %s\n", $equal ? 'yes' : 'no';

if ($n <= 6) {
    for ([A => \@a], [B => \@b], ['A * B' => \@par]) {
        my ($name, $m) = @$_;
        print "\n$name =\n";
        print join("\t", @$_), "\n" for @$m;
    }
}
