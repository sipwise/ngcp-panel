#!/usr/bin/perl -w
use strict;

use XML::Mini::Document;
use Data::Printer;

my $f = 'banlist.xml';
my $data = do { local $/; open my $fh, $f or die $!; <$fh> };
my $xmlDoc = XML::Mini::Document->new();
$xmlDoc->parse($data);
my $xmlHash = $xmlDoc->toHash();
my @ips = ();

# non empty response
if(defined $xmlHash->{methodResponse}->{params}->{param}->{value} and
   '' ne   $xmlHash->{methodResponse}->{params}->{param}->{value} ) {

    # single IP
    if(ref $xmlHash->{methodResponse}->{params}->{param}->{value}->{struct} eq 'HASH') {
	push @ips, { ip => $xmlHash->{methodResponse}->{params}->{param}->{value}->{struct}->{member}->[2]->{value}->{struct}->{member}->{value}->{struct}->{member}->[0]->{value}->{string} };
    }
    # multiple IPs
    else {
	for my $struct ( @{ $xmlHash->{methodResponse}->{params}->{param}->{value}->{struct} } ) {
	    if(ref $struct->{member}->[2]->{value}->{struct}->{member} eq 'HASH') {
	    	push @ips, { ip => $struct->{member}->[2]->{value}->{struct}->{member}->{value}->{struct}->{member}->[0]->{value}->{string} };
	    } else {
	    	foreach my $member(@{  $struct->{member}->[2]->{value}->{struct}->{member} }) {
	    		push @ips, { ip => $member->{value}->{struct}->{member}->[0]->{value}->{string} };
		}
	    }
	}
    }
}

p @ips;
