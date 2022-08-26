package NGCP::Panel::Controller::API::PasswordReset;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Email qw();

sub allowed_methods{
    return [qw/POST OPTIONS/];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PasswordReset/;

sub api_description {
    return 'Request a password reset using administrator email or subscriber SIP URI (username@domain).';
}

sub query_params {
    return [
    ];
}

sub resource_name{
    return 'passwordreset';
}

sub dispatch_path{
    return '/api/passwordreset/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-passwordreset';
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

sub POST :Allow {
    my ($self, $c) = @_;

    my $res;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        if ($resource->{type} eq 'administrator') {
            my $admin = $c->model('DB')->resultset('admins')->search({
                'me.login' => $resource->{username}
            })->first;
            if($admin && $admin->email && $admin->can_reset_password) {
                NGCP::Panel::Utils::Auth::initiate_password_reset($c, $admin);
            }
        }
        elsif($resource->{type} eq 'subscriber') {
            my ($user, $domain) = ($resource->{username}, $resource->{domain});

            if ($user =~ /^([^\@]+)\@([^\@]+)/) {
                ($user, $domain) = ($1, $2);
            }

            my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find({
                'provisioning_voip_subscriber.webusername' => $user,
                'domain.domain' => $domain,
            },{
                join => ['domain', 'provisioning_voip_subscriber'],
            });

            if($subscriber) {
                # don't clear web password, a user might just have guessed it and
                # could then block the legit user out
                my ($uuid_bin, $uuid_string);
                UUID::generate($uuid_bin);
                UUID::unparse($uuid_bin, $uuid_string);
                $subscriber->password_resets->delete; # clear any old entries of this subscriber
                $subscriber->password_resets->create({
                    uuid => $uuid_string,
                    timestamp => NGCP::Panel::Utils::DateTime::current_local->epoch + 300, #expire in 5 minutes
                });

                my $url = NGCP::Panel::Utils::Email::rewrite_url(
                    $c->config->{contact}->{external_base_url},
                    ($c->config->{general}{csc_js_enable} > 0) ?
                    ($c->req->base . 'v2/#/recoverpassword')
                    : $c->uri_for_action('/subscriber/recover_webpassword')->as_string);
                $url .= '?uuid=' . $uuid_string;
                
                $c->log->debug("passreset url: $url");

                NGCP::Panel::Utils::Email::password_reset($c, $subscriber, $url);
            }
        }

        $guard->commit;

        $res = { success => 1, message => 'Please check your email for password reset instructions.' };

        $c->response->status(HTTP_OK);
        $c->response->body(JSON::to_json($res));
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
