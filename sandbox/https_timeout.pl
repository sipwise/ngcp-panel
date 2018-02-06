#!/usr/bin/perl

use strict;

use MIME::Base64 qw/encode_base64/;
use URI::Escape;
use Data::Dumper;
use Net::HTTPS::Any qw/https_post/;
use LWP::UserAgent;
use HTTP::Request::Common;

my $cfg  = {
    proto    => 'https',
    host     => 'provisioning.e-connecting.net',
    port     => '443',
    path     => '/redirect/xmlrpc',
    user     => 'EU-Sipwise',
    password => 'aRRwgzVbmJ',
    mac      => 'BCC34206F766',
};

test_timeout();

sub test_timeout {
    my $authorization = encode_base64(join(':',@$cfg{qw/user password/}));
    print "authorization=$authorization;\n";
    $cfg->{headers} = { 'Authorization' => 'Basic '.$authorization };
    my $uri_remote = $cfg->{proto}.'://'.$cfg->{host}.':'.$cfg->{port}.$cfg->{path};
    my $uri = 'http://c5.demo.sipwise.com:1445/device/autoprov/bootstrap/{MAC}';
    my $ua = LWP::UserAgent->new;
    $ua->credentials($cfg->{host}.':'.$cfg->{port}, 'Please Enter Your Password', @$cfg{qw/user password/});
    $ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0,
    );
    my $content = "<?xml version=\"1.0\"?>
<methodCall>
<methodName>ipredirect.registerPhone</methodName>
<params>
<param><value><string>08f0c0123456</string></value></param>
<param><value><string>$uri</string></value></param>
</params>
</methodCall>";
#    my $content = "<?xml version=\"1.0\"?> 
#<methodCall> 
#<methodName>ipredirect.registerPhone</methodName> 
#<params> 
#<param><value><string>".$cfg->{mac}."</string></value></param> 
#<param><value><string><![CDATA[".$uri."]]></string></value></param> 
#</params> 
#</methodCall>";
    my $request = POST $uri_remote,
        Content_Type => 'text/xml',
        Content => $content;
    my $response = $ua->request($request);
    print Dumper [$response,$request];
#    my ( $page, $response_code, %reply_headers );
#    eval {
#        #local $SIG{ALRM} = sub { die "Connection timeout\n" };
#        #alarm(10);
#        #eval {
##            ( $page, $response_code, %reply_headers ) = https_post({
##                'host'    => $cfg->{host},
##                'port'    => $cfg->{port},
##                'path'    => $cfg->{path},
##                'headers' => $cfg->{headers},
##                'Content-Type' => 'text/xml',
##                'content' => "",
###                'content' => "<?xml version=\"1.0\"?> 
#<methodCall> 
#<methodName>ipredirect.registerPhone</methodName> 
#<params> 
#<param><value><string>".$cfg->{mac}."</string></value></param> 
#<param><value><string><![CDATA[".$uri."]]></string></value></param> 
#</params> 
#</methodCall>",
##            },);
#            #if ( $page ) {
#            #    print "qqq;\n";
#            #} else {
#            #    die "timeout;\n";
#            #}
#        #};
#        print "1.\@=$@;\n";
#        #print Dumper [$page, $response_code, \%reply_headers];
#        #alarm(0);
#        if ($@) {
#            print "2.\@=$@;\n";
#            #if ($@ =~ /SSL timeout/) {
#            #    warn "request timed out";
#            #} else {
#            #    die "error in request: $@";
#            #}
#        }
#    };
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
