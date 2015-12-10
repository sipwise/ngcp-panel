#!/usr/bin/perl -w

my $path = '/tmp/lnp.csv';

my $carrier_base = 'carrier_';
my $prefix_base = 'FF';
my $carrier_count = -1;


open my $fh, ">", $path or die "failed to open $path for writing: $!\n";
for(my $i = 0; $i < 1000000; ++$i) {
    unless($i % 100000) {
        $carrier_count++;
    }
    my $carrier_name = $carrier_base . $carrier_count;
    my $carrier_pref = $prefix_base . $carrier_count;
    my $number = sprintf "%s%015d", "43", $i;
    print $fh "$carrier_name,$carrier_pref,$number,2015-01-01,2015-01-31\n"
}
close $fh;
