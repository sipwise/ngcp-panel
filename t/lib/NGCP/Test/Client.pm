package NGCP::Test::Client;
use strict;
use warnings;

use Moose;
use LWP::UserAgent;
use JSON qw/from_json to_json/;
use IO::Uncompress::Unzip;
use Time::HiRes qw/gettimeofday tv_interval/;
use Digest::MD5 qw/md5_hex/;
use Data::Dumper;

has 'username' => (
    isa => 'Str',
    is => 'ro',
    default => sub {
        $ENV{API_USER} // 'administrator';
    }
);

has 'password' => (
    isa => 'Str',
    is => 'ro',
    default => sub {
        $ENV{API_PASS} // 'administrator';
    }
);

has 'role' => (
    isa => 'Str',
    is => 'ro',
    default => 'admin',
);

has 'uri' => (
    isa => 'Str',
    is => 'ro',
    default => sub { $ENV{CATALYST_SERVER}; },
);

has 'sub_uri' => (
    isa => 'Str',
    is => 'ro',
    default => sub { $ENV{CATALYST_SERVER_SUB}; },
);

has '_uri' => (
    isa => 'Maybe[Str]',
    is => 'rw',
);

has 'verify_ssl' => (
    isa => 'Int',
    is => 'ro',
    default => 0,
);

has '_test' => (
    isa => 'Object',
    is => 'ro',
);

has '_ua' => (
    isa => 'Object',
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;

        my $ua = LWP::UserAgent->new(keep_alive => 1);
        my $uri;
        if($self->role eq "admin" || $self->role eq "reseller") {
            $uri = $self->uri;
        } else {
            $uri = $self->sub_uri;
        }
        $self->_uri($uri);
        $self->_test->debug("client using uri $uri\n");
        $uri =~ s/^https?:\/\///;
        $self->_test->debug("client using ip:port $uri\n");
        my $realm;
        if($self->role eq 'admin' || $self->role eq 'reseller') {
            $realm = 'api_admin_http';
        } elsif($self->role eq 'subscriber') {
            $realm = 'api_subscriber_http';
        }
        $self->_test->debug("client using realm $realm with user=" . $self->username . " and pass " . $self->password . "\n");
        $ua->credentials($uri, $realm, $self->username, $self->password);
        unless($self->verify_ssl) {
            $ua->ssl_opts(
                verify_hostname => 0,
                SSL_verify_mode => 0,
            );
        }
        if($self->role eq "admin" || $self->role eq "reseller") {
            unless(-f $self->_crt_path) {

                # we have to setup a new connection here, because if we're already connected,
                # the connection will be re-used, thus no cert is used
                my $tmpua = LWP::UserAgent->new;
                $tmpua->credentials($uri, $realm, $self->username, $self->password);
                unless($self->verify_ssl) {
                    $tmpua->ssl_opts(
                        verify_hostname => 0,
                        SSL_verify_mode => 0,
                    );
                }

                my $res = $tmpua->post(
                    $self->_uri . '/api/admincerts/',
                    Content_Type => 'application/json',
                    Content => '{}'
                );
                unless($res->is_success) {
                    die "Failed to fetch client certificate: " . $res->status_line . "\n";
                }
                my $zip = $res->decoded_content;
                my $z = IO::Uncompress::Unzip->new(\$zip, MultiStream => 0, Append => 1);
                my $data;
                while(!$z->eof() && (my $hdr = $z->getHeaderInfo())) {
                    unless($hdr->{Name} =~ /\.pem$/) {
                        # wrong file, just read stream, clear buffer and try next
                        while($z->read($data) > 0) {}
                        $data = undef;
                        $z->nextStream();
                        next;
                    }
                    while($z->read($data) > 0) {}
                    last;
                }
                $z->close();
                unless($data) {
                    die "Failed to find PEM file in client certificate zip file\n";
                }
                open my $fh, ">:raw", $self->_crt_path
                    or die "Failed to open " . $self->_crt_path . ": $!\n";
                print $fh $data;
                close $fh;
            }
            $ua->ssl_opts(
                SSL_cert_file => $self->_crt_path,
                SSL_key_file => $self->_crt_path,
            );
        }
        return $ua;
    }
);

has '_crt_path' => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    default => sub {
        my ($self) = @_;
        return '/tmp/' . md5_hex($self->username) . ".crt";
    }
);

has 'last_rtt' => (
    is => 'rw',
    isa => 'Num',
    default => 0,
);

sub _request {
    my ($self, $req) = @_;
    my $t0 = [gettimeofday];
    $self->_test->debug("content of " . $req->method . " request to " . $req->uri . ":\n");
    $self->_test->debug($req->content || "<empty request>");
    $self->_test->debug("\n");
    my $res = $self->_ua->request($req);
    my $rtt = tv_interval($t0);
    $self->last_rtt($rtt);
    $self->_test->debug("content of response:\n");
    $self->_test->debug($res->decoded_content || "<empty response>");
    $self->_test->debug("\n");
    return $res;
}

sub _add_header {
    my ($self, $req, $name, $default, $val) = @_;
    if(defined $val && !length($val)) {
        # skip adding header altogether to simulate missing one
    } else {
        $req->header($name => $val // $default);
    }
    return $req;
}

sub _options {
    my ($self, $uri) = @_;

    $uri = $self->_normalize_uri($uri);
    my $req = HTTP::Request->new('OPTIONS', $uri);
    return $self->_request($req);
}

sub _post {
    my ($self, $uri, $data, $ctype, $prefer) = @_;

    $uri = $self->_normalize_uri($uri);
    my $req = HTTP::Request->new('POST', $uri);
    $req = $self->_add_header($req, 'Content-Type', 'application/json', $ctype);
    $req = $self->_add_header($req, 'Prefer', 'return=representation', $prefer);
    if(defined $data) {
        $req->content(to_json($data));
    }
    return $self->_request($req);
}

sub _put {
    my ($self, $uri, $data, $ctype, $prefer) = @_;

    $uri = $self->_normalize_uri($uri);
    my $req = HTTP::Request->new('PUT', $uri);
    $req = $self->_add_header($req, 'Content-Type', 'application/json', $ctype);
    $req = $self->_add_header($req, 'Prefer', 'return=representation', $prefer);
    if(defined $data) {
        $req->content(to_json($data));
    }
    return $self->_request($req);
}

sub _patch {
    my ($self, $uri, $data, $ctype, $prefer) = @_;

    $uri = $self->_normalize_uri($uri);
    my $req = HTTP::Request->new('PATCH', $uri);
    $req = $self->_add_header($req, 'Content-Type', 'application/json-patch+json', $ctype);
    $req = $self->_add_header($req, 'Prefer', 'return=representation', $prefer);
    if(defined $data) {
        $req->content(to_json($data));
    }
    return $self->_request($req);
}

sub _get {
    my ($self, $uri) = @_;

    $uri = $self->_normalize_uri($uri);
    my $req = HTTP::Request->new('GET', $uri);
    $req->header('Prefer' => 'return=representation');
    return $self->_request($req);
}

sub _delete {
    my ($self, $uri) = @_;

    $uri = $self->_normalize_uri($uri);
    my $req = HTTP::Request->new('DELETE', $uri);
    return $self->_request($req);
}

sub _normalize_uri {
    my ($self, $uri) = @_;
    unless($uri =~ /^http/) {
        unless($self->_uri) {
            if($self->role eq "admin" || $self->role eq "reseller") {
                $self->_uri($self->uri);
            } else {
                $self->_uri($self->sub_uri);
            }
        }
        $uri = $self->_uri . '/' . $uri . '/';
    }
    return $uri;
}

1;
