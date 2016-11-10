package NGCP::Panel::Model::CA;
use Sipwise::Base;
use MIME::Base64 qw(decode_base64);
use Time::HiRes qw();
use Path::Tiny qw();
use Sys::Hostname qw(hostname);
use parent 'Catalyst::Component';

sub client_signing_template {
    my ($self, $serial) = @_;
    return <<"TEMPLATE_END";
cn = "Sipwise NGCP API client certificate"
expiration_days = 3650
serial = $serial
tls_www_client
signing_key
encryption_key

TEMPLATE_END
}

sub COMPONENT {
    my ($class, $app, $args) = @_;
    $args = $class->merge_config_hashes($class->config, $args);
    my $self = $class->new($app, $args);
    return $self;
}

sub make_client {
    my ($self, $c, $serial) = @_;
    my $client_key = Path::Tiny->tempfile;
    my($command,$stdout);
    if($self->check_ca_errors($c)){
        die [$c->loc('Cannot use the configured certificate for signing client certificates'), "showdetails"];
    }
    $command = sprintf 'certtool -p --bits 3248 --outfile %s 1>&- 2>&-', $client_key->stringify;
    $c->log->debug($command);
    system $command;
    my $client_signing_template = Path::Tiny->tempfile;
    my $tmpl = $self->client_signing_template($serial);
    $c->log->debug($tmpl);
    $client_signing_template->spew($tmpl);
    my $client_cert = Path::Tiny->tempfile;
    $command = sprintf
        'certtool -c --load-privkey %s --outfile %s --load-ca-certificate %s --load-ca-privkey %s --template %s',
        $client_key->stringify, $client_cert->stringify,
        ($c->config->{ssl}->{rest_api_certfile} || $c->config->{ssl}->{certfile}),
        ($c->config->{ssl}->{rest_api_keyfile}  || $c->config->{ssl}->{keyfile}),
        $client_signing_template->stringify;
    $c->log->debug($command);
    $stdout = `$command 2>&1`;
    $c->log->debug($stdout) if $stdout;
    my $cert = $client_cert->slurp . $client_key->slurp =~ s/.*(?=-----BEGIN RSA PRIVATE KEY-----)//mrs;
    $client_cert->remove;
    $client_key->remove;

    return $cert;
}

sub check_ca_errors {
    my ($self, $c) = @_;
    my($command,$stdout,$error);
    $command = 'openssl x509 -noout -purpose -in ' . $c->config->{ssl}->{rest_api_certfile};
    $c->log->debug($command);
    $stdout = `$command 2>&1` // "";
    unless ($stdout =~ m/SSL (client|server) CA : Yes/) {
        $error = "Failed to check CA certificate: $stdout";
    }
    $command = 'openssl verify ' . $c->config->{ssl}->{rest_api_certfile};
    #$command = 'openssl verify /etc/ngcp-config/ssl/client-auth-ca.crt';
    $c->log->debug($command);
    $stdout = `$command 2>&1` // "";
    if ($stdout =~ m/certificate has expired/) {
        $error = "Failed to check CA certificate: expired: $stdout";
    }
    if($error){
        $c->log->error($error);
        return $error;        
    }
    return 0;
}

sub make_pkcs12 {
    my ($self, $c, $serial, $cert, $pass) = @_;

    my $cert_file = Path::Tiny->tempfile;
    $cert_file->spew($cert);
    my $p12_file = Path::Tiny->tempfile;
    my $command = sprintf 'openssl pkcs12 -export -in %s -inkey %s -out %s -password pass:%s -name "NGCP API Client Certificate %d"',
        $cert_file->stringify, $cert_file->stringify, $p12_file->stringify, $pass, $serial;
    $c->log->debug($command);
    system $command;
    my $p12 = $p12_file->slurp({binmode => ":raw"});
    $cert_file->remove;
    $p12_file->remove;

    return $p12;
}

sub get_server_cert {
    my ($self, $c) = @_;

    my $cert_file = Path::Tiny->new($c->config->{ssl}->{server_certfile});
    return $cert_file->slurp;
}

sub get_provisioning_server_cert {
    my ($self, $c) = @_;

    my $cert_file = Path::Tiny->new($c->config->{deviceprovisioning}->{server_certfile});
    return $cert_file->slurp;
}

sub get_provisioning_ca_cert {
    my ($self, $c) = @_;

    my $cert_file = Path::Tiny->new($c->config->{deviceprovisioning}->{ca_certfile});
    return $cert_file->slurp;
}

sub get_provisioning_root_ca_cert {
    my ($self, $c) = @_;

    my $content = $self->get_provisioning_ca_cert($c);
    $content =~ s/\r?\n//gm;
    $content =~ s/^.*?BEGIN CERTIFICATE\-+(.*?)\-+END CERTIFICATE.*$/$1/;
    return $content;
}
1;

# vim: set tabstop=4 expandtab
