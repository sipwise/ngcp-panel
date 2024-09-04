package NGCP::Panel::Controller::API::PasswordChange;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Auth;
use NGCP::Panel::Utils::Admin;
use NGCP::Panel::Utils::Subscriber;

sub allowed_methods{
    return [qw/POST OPTIONS/];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PasswordChange/;

sub api_description {
    return 'Change password of the authenticated user.';
}

sub query_params {
    return [
    ];
}

sub resource_name{
    return 'passwordchange';
}

sub dispatch_path{
    return '/api/passwordchange/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-passwordchange';
}

__PACKAGE__->set_config({
    action => {
        map { $_ => {
            Args => 0,
            Does => [qw(CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
});

sub return_representation_post {}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $item = $c->user;

    try {
        require Data::Dumper;
        print Data::Dumper->Dumpxs([$resource]);
        my $new_password = $resource->{new_password} // '';
        my $ngcp_realm = $c->request->env->{NGCP_REALM} // 'admin';
        if ($ngcp_realm eq 'admin') {
            $item->update({
                saltedpass => NGCP::Panel::Utils::Auth::generate_salted_hash($new_password),
            });
            NGCP::Panel::Utils::Admin::insert_password_journal(
                $c, $item, $new_password
            );
        } elsif ($ngcp_realm eq 'subscriber') {
            $item->update({
                webpassword => $NGCP::Panel::Utils::Auth::ENCRYPT_SUBSCRIBER_WEBPASSWORDS
                                ? NGCP::Panel::Utils::Auth::generate_salted_hash($new_password)
                                : $new_password,
            });
            NGCP::Panel::Utils::Subscriber::insert_webpassword_journal(
                $c, $item, $new_password
            );
        }
    } catch ($e) {
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to change password.", $e);
    }

    $c->response->status(HTTP_NO_CONTENT);
    $c->response->body(q());

    return $item;
}

1;

# vim: set tabstop=4 expandtab:
