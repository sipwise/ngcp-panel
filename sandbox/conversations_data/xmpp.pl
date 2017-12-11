#!/usr/bin/perl  
use strict;  
use Net::XMPP;
use Net::XMPP::Debug;
use Data::Dumper;
my ($recip, $msg) = @ARGV;

#if(! $recip || ! $msg) {  
#    print 'Syntax: $0 <recipient> <message>\n';  
#    exit;  
#}

my $con = new Net::XMPP::Client(debuglevel => 1, debugtime=>1);  
my $status = $con->Connect(  
    hostname => '192.168.1.118',  
    port => '5222',  
    connectiontype => 'tcpip',
    #register=>1,
    #connectiontype => 'tcpip',
    #srv => 1,
    #ssl => 1,
tls => 1,
ssl_verify => 0,
   #ssl_ca_path => '/etc/prosody/certs/localhost.crt',
ssl_ca_path => '/etc/ssl/certs',
);
print Dumper $status;
die('ERROR: XMPP connection failed') if ! defined($status);  
my @result = $con->AuthIQAuth(  
    hostname => '192.168.1.118',  
    username => 'sipsub2_1001@192.168.1.118',  
    password => 'sipsub2_pwd_1001',
    resource => 'test',
    #register => 1,
);  
print Dumper \@result;
die('ERROR: XMPP authentication failed') if $result[0] ne 'ok';  
die('ERROR: XMPP message failed') if ($con->MessageSend(to => $recip, body => $msg) != 0);  
print 'Success!\n';
$con->Disconnect();
#<?xml version="1.0"?>  <stream:stream to="192.168.1.118" xmlns="jabber:client" xmlns:stream="http://etherx.jabber.org/streams" version="1.0">

#./lm-send-async --server 192.168.1.118 --username 'sipsub2_1001@192.168.1.118' --password sipsub2_pwd_1001 --fingerprint "D6:F7:A7:30:14:1E:D1:4E:5A:8E:53:C6:5E:EA:88:AC:1B:4F:32:31:00:9A:B3:4B:B2:34:82:34:85:00:F7:F0" --recipient 'sipsub1_1003@192.168.1.118' --message "Hello World!"

#echo 'Hello' |sendxmpp -jserver 192.168.1.118 -username 'sipsub2_1001@192.168.1.118' -password sipsub2_pwd_1001 -tls -no-tls-verify --tls-ca-path /etc/ssl/certs --verbose --debug s 'hello' 'sipsub1_1003@192.168.1.118'

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


#echo 'Hello' |sendxmpp -jserver 192.168.1.118 -username 'sipsub2_1001@192.168.1.118' -password sipsub2_pwd_1001 -tls -no-tls-verify --tls-ca-path /etc/ssl/certs --verbose --debug s 'hello' 'sipsub1_1003@192.168.1.118'

