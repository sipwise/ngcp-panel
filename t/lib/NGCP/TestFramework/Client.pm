package NGCP::TestFramework::Client;

use strict;
use warnings;
use Data::Dumper;
use Digest::MD5 qw/md5_hex/;
use IO::Uncompress::Unzip;
use Log::Log4perl qw(:easy);
use LWP::UserAgent;
use Moose;
use Time::HiRes qw/gettimeofday tv_interval/;

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

has '_ua' => (
    isa => 'LWP::UserAgent',
    is => 'ro',
    lazy => 1,
    builder => '_build_ua'
);

sub _build_ua {
    my $self = shift;

    my $ua = LWP::UserAgent->new(keep_alive => 1);
    my $uri;
    if($self->role eq "admin" || $self->role eq "reseller") {
        $uri = $self->uri;
    } else {
        $uri = $self->sub_uri;
    }
    $self->_uri($uri);
    DEBUG("client using uri $uri\n");
    $uri =~ s/^https?:\/\///;
    DEBUG("client using ip:port $uri\n");
    my $realm;
    if($self->role eq 'admin' || $self->role eq 'reseller') {
        $realm = 'api_admin_http';
    } elsif($self->role eq 'subscriber') {
        $realm = 'api_subscriber_http';
    }
    DEBUG("client using realm $realm with user=" . $self->username . " and pass " . $self->password . "\n");
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


sub perform_request {
    my ($self, $req) = @_;
    my $t0 = [gettimeofday];
    my $res = $self->_ua->request($req);
    my $rtt = tv_interval($t0);
    $self->last_rtt($rtt);
    return $res;
}

1;

