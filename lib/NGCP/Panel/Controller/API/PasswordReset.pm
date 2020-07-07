package NGCP::Panel::Controller::API::PasswordReset;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


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
            #ACLDetachTo => 'invalid_user',
            # AllowedRole => [qw/admin reseller ccareadmin ccare lintercept subscriberadmin subscriber/],
            Args => 0,
            #Does => [qw(ACL CheckTrailingSlash RequireSSL)],
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

        my $admin = $c->model('DB')->resultset('admins')->search({
            'me.email' => $resource->{email}
        })->first;
        if($admin) {
            if (!$admin->email) {
                $res = {success => 0};
                $c->log->error("Administrator does not have an email set.");
                $c->response->status(HTTP_OK);
                $c->response->body(JSON::to_json($res));
                return;
            }
            elsif ($admin->can_reset_password) {
                my $result = NGCP::Panel::Utils::Auth::initiate_password_reset($c, $admin);
                unless ($result->{success}) {
                    $res = {success => 0};
                    $c->log->error($result->{error});
                    $c->response->status(HTTP_OK);
                    $c->response->body(JSON::to_json($res));
                    return;
                }
            }
            else {
                $res = {success => 0};
                $c->log->error('This user is not allowed to reset password.');
                $c->response->status(HTTP_OK);
                $c->response->body(JSON::to_json($res));
                return;
            }
        }
        else {
            my ($user, $domain) = split /\@/, $resource->{email};
            my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find({
                username => $user,
                'domain.domain' => $domain,
            },{
                join => 'domain',
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
                my $url = $c->uri_for_action('/subscriber/recover_webpassword')->as_string . '?uuid=' . $uuid_string;
                NGCP::Panel::Utils::Email::password_reset($c, $subscriber, $url);
            }
            else {
                $res = {success => 0};
                $c->log->error('User not found.');
                $c->response->status(HTTP_OK);
                $c->response->body(JSON::to_json($res));
                return;
            }
        }

        $guard->commit;

        $res = { success => 1, message => 'Successfully reset password, please check your email' };

        $c->response->status(HTTP_OK);
        $c->response->body(JSON::to_json($res));
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
