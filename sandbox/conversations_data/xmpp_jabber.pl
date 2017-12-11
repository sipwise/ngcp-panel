#!/usr/bin/perl  
use strict;  
use Net::Jabber;
use Net::Jabber::Debug;
use Data::Dumper;
my ($recip, $msg) = @ARGV;

if(! $recip || ! $msg) {  
    print 'Syntax: $0 <recipient> <message>\n';  
    exit;  
}

my $con = new Net::Jabber::Client(debuglevel => 1, debugtime=>1);  
my $status = $con->Connect(  
    hostname => '192.168.1.118',  
    port => '5222',  
    connectiontype => 'tcpip',
    register=>1,
    #connectiontype => 'tcpip',
    #srv => 1,
    #ssl => 1,
    tls => 1,
    #ssl_ca_path => '/etc/prosody/certs/localhost.crt',
    ssl_ca_path => '/etc/ssl/certs',
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
$con->Disconnect();
#<?xml version="1.0"?>  <stream:stream to="192.168.1.118" xmlns="jabber:client" xmlns:stream="http://etherx.jabber.org/streams" version="1.0">


#    my $cnx =  xmpp_login ($$cmdline{'jserver'}  || $$config{'jserver'},
#                           $$cmdline{'port'}     || $$config{'port'} || ($$cmdline{'ssl'} ? 5223 : 5222),
#                           $$cmdline{'username'} || $$config{'username'},
#                           $$cmdline{'password'} || $$config{'password'},
#                           $$cmdline{'component'}|| $$config{'component'},
#                           $$cmdline{'resource'},
#                           $$cmdline{'tls'} || $$config{'tls'},
#                           $$cmdline{'no-tls-verify'} || $$config{'no-tls-verify'},
#                           $$cmdline{'tls-ca-path'} || $$config{'tls-ca-path'} || '',
#                           $$cmdline{'ssl'},
#                           $$cmdline{'debug'})
#      or error_exit("cannot login: $!");
