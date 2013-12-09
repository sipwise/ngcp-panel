package NGCP::Panel::Model::CA;
use Sipwise::Base;
use MIME::Base64 qw(decode_base64);
use Path::Tiny qw();
use Time::HiRes qw();
use Types::Path::Tiny qw(AbsDir);
use Sys::Hostname qw(hostname);
extends 'Catalyst::Component';

has('ca_selfsign_template', is => 'ro', isa => 'Str', default => sub { <<'' });
organization = "Sipwise GmbH"
unit = "Dept. of Issuing Snakeoil Certificates"
locality = "Brunn am Gebirge"
state = "Niederösterreich"
country = AT
cn = "*.sipwise.com"
expiration_days = 1000
ca
cert_signing_key

has('server_signingrequest_template', is => 'ro', isa => 'Str', default => sub { <<"" });
cn = "@{[ hostname ]}"
expiration_days = 365
tls_www_server
signing_key
encryption_key

has('server_signing_template', is => 'ro', isa => 'Str', default => sub { <<'' });
expiration_days = 365
honor_crq_extensions

sub client_signing_template {
    my ($self, $serial) = @_;
    return <<"";
cn = "Sipwise NGCP API client certificate"
expiration_days = 365
serial = $serial
tls_www_client
signing_key
encryption_key

}

has('log', is => 'rw', isa => 'Log::Log4perl::Catalyst',);
has('prefix', is => 'ro', isa => AbsDir, coerce => 1, default => '/etc/ssl/ngcp/api');

sub COMPONENT {
    my ($class, $app, $args) = @_;
    $args = $class->merge_config_hashes($class->config, $args);
    my $self = $class->new($app, $args);
    no autobox::Core; # wonky initialisation order
    $self->log($app->log);
    return $self;
}

sub make_ca {
    my ($self) = @_;
    my $command = sprintf 'certtool -p --bits 3248 --outfile %s 1>&- 2>&-', $self->prefix->child('ca-key.pem');
    warn "$command\n";
    system $command;
    my $ca_selfsign_template = Path::Tiny->tempfile;
    $ca_selfsign_template->spew_utf8($self->ca_selfsign_template);
    $command = sprintf 'certtool -s --load-privkey %s --outfile %s --template %s 1>&- 2>&-',
      $self->prefix->child('ca-key.pem'), $self->prefix->child('ca-cert.pem'), $ca_selfsign_template->stringify;
    warn "$command\n";
    system $command;
    return;
}

sub make_server {
    my ($self) = @_;
    my $command = sprintf 'certtool -p --bits 3248 --outfile %s  1>&- 2>&-', $self->prefix->child('server-key.pem');
    warn "$command\n";
    system $command;
    my $server_signingrequest_template = Path::Tiny->tempfile;
    $server_signingrequest_template->spew($self->server_signingrequest_template);
    $command = sprintf 'certtool -q --load-privkey %s --outfile %s --template %s 1>&- 2>&-',
      $self->prefix->child('server-key.pem'), $self->prefix->child('server-csr.pem'),
      $server_signingrequest_template->stringify;
    warn "$command\n";
    system $command;
    my $server_signing_template = Path::Tiny->tempfile;
    $server_signing_template->spew($self->server_signing_template);
    $command = sprintf 'certtool -c --load-request %s --outfile %s --load-ca-certificate %s --load-ca-privkey %s ' .
      '--template %s 1>&- 2>&-', $self->prefix->child('server-csr.pem'), $self->prefix->child('server-cert.pem'),
      $self->prefix->child('ca-cert.pem'), $self->prefix->child('ca-key.pem'), $server_signing_template->stringify;
    warn "$command\n";
    system $command;
    return;
}

sub make_client {
    my ($self, $serial) = @_;
    my $client_key = Path::Tiny->tempfile;
    my $command = sprintf 'certtool -p --bits 3248 --outfile %s 1>&- 2>&-', $client_key->stringify;
    $self->log->debug($command);
    system $command;
    my $client_signing_template = Path::Tiny->tempfile;
    $client_signing_template->spew($self->client_signing_template($serial));
    my $client_cert = Path::Tiny->tempfile;
    $command = sprintf 'certtool -c --load-privkey %s --outfile %s --load-ca-certificate %s --load-ca-privkey %s ' .
      '--template %s 1>&- 2>&-', $client_key->stringify, $client_cert->stringify, $self->prefix->child('ca-cert.pem'),
      $self->prefix->child('ca-key.pem'), $client_signing_template->stringify;
    $self->log->debug($command);
    system $command;
    my $cert_file = $self->client_cert_file($serial);
    $cert_file->spew($client_cert->slurp . $client_key->slurp =~ s/.*(?=-----BEGIN RSA PRIVATE KEY-----)//mrs);
    return;
}

sub client_cert_file {
    my ($self, $serial) = @_;
    return $self->prefix->child("NGCP-API-client-certificate-$serial.pem");
}

__END__

=encoding UTF-8

=head1 NAME

NGCP::Panel::Model::CA - certificate management model

=head1 DESCRIPTION

=head2 Generating prerequisite root certificates

    perl -mNGCP::Panel::Model::CA -e'
        NGCP::Panel::Model::CA->new->make_ca;
        NGCP::Panel::Model::CA->new->make_server;
    '
