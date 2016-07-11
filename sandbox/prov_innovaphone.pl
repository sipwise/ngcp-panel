#!/usr/bin/perl

use strict;

use MIME::Base64 qw/encode_base64/;
use URI::Escape;
use Data::Dumper;

my $cfg  = {
    proto    => 'https',
    host     => 'provisioning.e-connecting.net',
    port     => '443',
    path     => '/redirect/xmlrpc',
    user     => 'office@sipwise.com', 
    password => 'innova4Sipwise!',
};

my $authorization = encode_base64(join(':',@$cfg{qw/user password/}));
#$authorization = 'RVUtU2lwd2lzZTphUlJ3Z3pWYm1K';
##$authorization =~s/[ \s]//gis;
##$authorization .= '=';
print "authorization=$authorization;\n";
if(1){
    # 1.###############################
    use Net::HTTPS::Any qw(https_get https_post);

    my( $page, $response, %reply_headers ) = https_post({
        'host'    => $cfg->{host},
        'port'    => $cfg->{port},
        'path'    => $cfg->{path},
        'headers' => { 'Authorization' => 'Basic '.$authorization },
        'Content-Type' => 'text/xml',
        'content' => "<?xml version=\"1.0\"?> 
<methodCall> 
<methodName>ipredirect.registerPhone</methodName> 
<params> 
<param><value><string>AABBCCDDEEFF</string></value></param> 
<param><value><string>".URI::Escape::uri_escape("http://test-proto.waitforerror.com/?mac={MAC}&model={MODEL}")."</string></value></param> 
</params> 
</methodCall>",
    },);
    print Dumper [$page, $response, \%reply_headers];
    # /1.###############################
}
__DATA__
#use LWP::UserAgent; 
#my $res = $ua->post("https://$cfg->{host}:$cfg->{port}$cfg->{path}","<?xml version=\"1.0\"?> 
#my $res = $ua->post("https://$cfg->{host}:$cfg->{port}$cfg->{path}","<?xml version=\"1.0\"?> 
<methodCall> 
<methodName>ipredirect.registerPhone</methodName> 
<params> 
<param><value><string>AA</string></value></param> 
<param><value><string>waitforerror</string></value></param> 
</params> 
</methodCall>");
#
#print $res->content;