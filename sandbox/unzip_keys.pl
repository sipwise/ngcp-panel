#!/usr/bin/perl -w
use strict;
use Data::Dumper;
use File::Slurp qw/read_file/;
use IO::Uncompress::Unzip qw/unzip/;

my $zip = read_file("keys.zip");
my $z = IO::Uncompress::Unzip->new(\$zip, MultiStream => 0, Append => 1);

my $data;
while(!$z->eof() && (my $hdr = $z->getHeaderInfo())) {
    print "+++ found $$hdr{Name}\n";
    unless($hdr->{Name} =~ /\.pem$/) {
        # wrong file, just read stream, clear buffer and try next
        while($z->read($data) > 0) {};
        $data = undef;
        $z->nextStream();
        next;
    }

    # got our pem file
    while($z->read($data) > 0) {}
    last;
}
$z->close();
unless($data) {
    die "no PEM file found\n";
}

open my $fh, ">:raw", "/tmp/out.zip";
print $fh $data;
close $fh;
