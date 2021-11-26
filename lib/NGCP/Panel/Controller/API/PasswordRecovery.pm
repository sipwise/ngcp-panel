package NGCP::Panel::Controller::API::PasswordRecovery;
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

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PasswordRecovery/;

sub api_description {
    return 'Recover password following a password reset request.';
}

sub query_params {
    return [
    ];
}

sub resource_name{
    return 'passwordrecovery';
}

sub dispatch_path{
    return '/api/passwordrecovery/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-passwordrecovery';
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

    $c->user->logout if($c->user);

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

        my ($uuid_bin, $uuid_string);
        $uuid_string = $resource->{token} // '';

        unless($uuid_string && UUID::parse($uuid_string, $uuid_bin) != -1) {
            $res = {success => 0};
            $c->log->error("Invalid password recovery attempt for token '$uuid_string' from '".$c->qs($c->req->address)."'");
            $c->response->status(HTTP_FORBIDDEN);
            $c->response->body(JSON::to_json($res));
            return;
        }

        my $redis = Redis->new(
            server => $c->config->{redis}->{central_url},
            reconnect => 10, every => 500000, # 500ms
            cnx_timeout => 3,
        );
        unless ($redis) {
            $res = {success => 0};
            $c->log->error("Failed to connect to central redis url " . $c->config->{redis}->{central_url});
            $c->response->status(HTTP_INTERNAL_SERVER_ERROR);
            $c->response->body(JSON::to_json($res));
            return;
        }
        $redis->select($c->config->{'Plugin::Session'}->{redis_db});
        my $admin = $redis->hget("password_reset:admin::$uuid_string", "user");
        if ($admin) {
            $c->log->debug("Entering password recovery for administrator.");
            my $administrator = $c->model('DB')->resultset('admins')->search({login => $admin})->first;
            unless ($administrator) {
                $res = {success => 0};
                $c->log->error("Invalid password recovery attempt for token '$uuid_string' from '".$c->qs($c->req->address)."'");
                $c->response->status(HTTP_FORBIDDEN);
                $c->response->body(JSON::to_json($res));
                return;
            }
            my $ip = $redis->hget("password_reset:admin::$uuid_string", "ip");
            if ($ip && $ip ne $c->req->address) {
                $res = {success => 0};
                $c->log->error("Invalid password recovery attempt for token '$uuid_string' from '".$c->qs($c->req->address)."'");
                $c->response->status(HTTP_FORBIDDEN);
                $c->response->body(JSON::to_json($res));
                return;
            }
            $c->log->debug("Updating administrator password.");
            $administrator->update({
                saltedpass => NGCP::Panel::Utils::Auth::generate_salted_hash($form->params->{new_password}),
            });
            $redis->del("password_reset:admin::$uuid_string");
            $redis->del("password_reset:admin::$admin");
        }
        else {
            $c->log->debug("Entering password recovery for subscriber.");
            my $rs = $c->model('DB')->resultset('password_resets')->search({
                uuid => $uuid_string,
                timestamp => { '>=' => NGCP::Panel::Utils::DateTime::current_local->epoch - 300 },
            });

            my $subscriber = $rs->first ? $rs->first->voip_subscriber : undef;
            unless($subscriber && $subscriber->provisioning_voip_subscriber) {
                $res = {success => 0};
                $c->log->error("Invalid password recovery attempt for token '$uuid_string' from '".$c->qs($c->req->address)."'");
                $c->response->status(HTTP_FORBIDDEN);
                $c->response->body(JSON::to_json($res));
                return;
            }
            $c->log->debug("Updating subscriber password.");
            my $webpassword = $form->params->{new_password};
            $webpassword = NGCP::Panel::Utils::Auth::generate_salted_hash($webpassword) if $NGCP::Panel::Utils::Auth::ENCRYPT_SUBSCRIBER_WEBPASSWORDS;
            $subscriber->provisioning_voip_subscriber->update({
                webpassword => $webpassword,
            });
            $rs->delete;
        }

        $guard->commit;

        $res = { success => 1, message => 'Password reset successfuly completed.' };

        $c->response->status(HTTP_OK);
        $c->response->body(JSON::to_json($res));
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
