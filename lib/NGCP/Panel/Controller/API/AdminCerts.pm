package NGCP::Panel::Controller::API::AdminCerts;

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::AdminCerts/;

use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Admin;

__PACKAGE__->set_config();

sub allowed_roles {
    return qw/admin reseller/;
}

sub allowed_methods {
    return [qw/POST OPTIONS HEAD/];
}

sub api_description {
    return 'Creates a new SSL client certificate package in ZIP format containing a PEM and a P12 certificate.';
}

sub query_params {
    return [
        {},
    ];
}

# avoid automatic creation of HAL response, since we're
# taking care of returning the body ourselves.
sub return_representation_post {}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $login = $resource->{login} // $c->user->login;
    my $item_rs = $self->get_list($c);
    my $admin = $item_rs->search({
        login => $login,
    })->first;

    unless($admin) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid login, administrator does not exist");
        return;
    }

    # only allow to generate a certificate if
    # a. you're doing it for yourself
    # b. you're a master
    # c. you're a superuser
    unless($c->user->login eq $login || $c->user->is_master || $c->user->is_superuser) {
        $self->error($c, HTTP_FORBIDDEN, "Insufficient privileges to create certificate for this administrator");
        return;
    }

    my $err;
    my $res = NGCP::Panel::Utils::Admin::generate_client_cert($c, $admin, sub {
        my $e = shift;
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to generate client certificate");
        $err = 1;
    });
    return if $err;

    my $serial = $res->{serial};
    my $zipped_file = $res->{file};
    $c->res->headers(HTTP::Headers->new(
        'Content-Type' => 'application/zip',
        'Content-Disposition' => sprintf('attachment; filename=%s', "NGCP-API-client-certificate-$serial.zip")
    ));
    $c->res->body($zipped_file);
    $c->response->status(HTTP_CREATED);
}

1;

# vim: set tabstop=4 expandtab:
