#!/usr/bin/perl  
use strict;  
use Net::Jabber;
use Data::Dumper;
my ($recip, $msg) = @ARGV;

if(! $recip || ! $msg) {  
    print 'Syntax: $0 <recipient> <message>\n';  
    exit;  
}

my $con = new Net::Jabber::Client();  
my $status = $con->Connect(  
    hostname => '192.168.1.118',  
    port => '5222',  
    connectiontype => 'tcpip',  
    #tls => 1,
    #ssl_ca_path => '/etc/prosody/certs/localhost.crt',
);
print Dumper $status;
die('ERROR: XMPP connection failed') if ! defined($status);  
my @result = $con->AuthSend(  
    hostname => '192.168.1.118',  
    username => 'sipsub2_1001@192.168.1.118',  
    password => 'sipsub2_pwd_1001',
    resource => 'test',
);  
print Dumper \@result;
die('ERROR: XMPP authentication failed') if $result[0] ne 'ok';  
die('ERROR: XMPP message failed') if ($con->MessageSend(to => $recip, body => $msg) != 0);  
print 'Success!\n';

#<?xml version="1.0"?>  <stream:stream to="192.168.1.118" xmlns="jabber:client" xmlns:stream="http://etherx.jabber.org/streams" version="1.0">