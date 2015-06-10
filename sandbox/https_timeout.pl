#!/usr/bin/perl

use strict;

use MIME::Base64 qw/encode_base64/;
use URI::Escape;
use Data::Dumper;
use Net::HTTPS::Any qw/https_post/;

my $cfg  = {
    proto    => 'https',
    host     => 'www.google.com',
    port     => '81',
    #host     => 'rps.yealink.com',
    #port     => '443',
    path     => '/xmlrpc',
    user     => '',
    password => '',
};

test_timeout();

sub test_timeout {
    my $authorization = encode_base64(join(':',@$cfg{qw/user password/}));
    $authorization =~s/[ \s]//gis;
    $authorization .= '=';
    print "authorization=$authorization;\n";
    $cfg->{headers} = { 'Authorization' => 'Basic '.$authorization };
    my ( $page, $response_code, %reply_headers );
    eval {
        local $SIG{ALRM} = sub { die "Connection timeout\n" };
        alarm(10);
        #eval {
            ( $page, $response_code, %reply_headers ) = https_post({
                'host'    => $cfg->{host},
                'port'    => $cfg->{port},
                'path'    => $cfg->{path},
                'headers' => $cfg->{headers},
                'Content-Type' => 'text/xml',
                'content' => "<?xml version='1.0' encoding='UTF-8'?>
    <methodCall>
    <methodName>redirect.registerDevice</methodName>
    <params>
    <param>
    <value><string>"."0080f0d4dbf1"."</string></value>
    </param>
    <param>
    <value><string><![CDATA["."0080f0d4dbf10080f0d4"."]]></string></value>
    </param>
    </params>
    </methodCall>",
            },);
            #if ( $page ) {
            #    print "qqq;\n";
            #} else {
            #    die "timeout;\n";
            #}
        #};
        print "1.\@=$@;\n";
        print Dumper [$page, $response_code, \%reply_headers];
        alarm(0);
        if ($@) {
            print "2.\@=$@;\n";
            #if ($@ =~ /SSL timeout/) {
            #    warn "request timed out";
            #} else {
            #    die "error in request: $@";
            #}
        }
    };
    alarm(0);
    print "3.\@=$@;\n";
    if ($@) {
        print "4.\@=$@;\n";
        #if ($@ =~ /SSL timeout/) {
        #    warn "request timed out";
        #} else {
        #    die "error in request: $@";
        #}
    }
}
