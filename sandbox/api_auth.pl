#!/usr/bin/perl -w
use strict;
use LWP::UserAgent;

my $ua = LWP::UserAgent->new();
$ua->ssl_opts(
    SSL_cert_file => '/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate-1385650532.pem',
    SSL_key_file  => '/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate-1385650532.pem',
    SSL_ca_file   => '/etc/ngcp-panel/api_ssl/api_ca.crt',
);
my $can_accept = HTTP::Message::decodable;
my $res = $ua->get(
    'https://serenity:4443/api/contacts/?id=10',
    #'Accept-Encoding' => $can_accept,
    'Accept' => 'application/hal+json',
);
if($res->is_success) {
    print $res->as_string;
} else {
    print STDERR $res->status_line, "\n";
}

# vim: set tabstop=4 expandtab:
