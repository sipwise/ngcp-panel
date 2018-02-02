package NGCP::Panel::Controller::API::Interceptions;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Interception;
use UUID qw/generate unparse/;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines lawful interceptions of subscribers.';
};

sub query_params {
    return [
        {
            param => 'liid',
            description => 'Filter for interceptions of a specific interception id',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.LIID' => $q };
                },
                second => sub { },
            },
        },
        {
            param => 'number',
            description => 'Filter for interceptions of a specific number (in E.164 format)',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.number' => $q };
                },
                second => sub { },
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Interceptions/;

sub resource_name{
    return 'interceptions';
}

sub dispatch_path{
    return '/api/interceptions/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-interceptions';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    #$self->log_request($c);

    unless($c->user->lawful_intercept) {
        $self->error($c, HTTP_FORBIDDEN, "Accessing user has no LI privileges.");
        return;
    }
}



sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('InterceptDB')->txn_scope_guard;
    my $cguard = $c->model('DB')->txn_scope_guard;
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

        my $num_rs = $c->model('DB')->resultset('voip_numbers')->search(
            \[ 'concat(cc,ac,sn) = ?', [ {} => $resource->{number} ]]
        );
        if(not $num_rs->first) {
            $c->log->error("invalid number '$$resource{number}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Number does not exist");
            last;
        } else {
            my $intercept_num_rs = $c->model('InterceptDB')->resultset('voip_numbers')->search(
                \[ 'concat(cc,ac,sn) = ?', [ {} => $resource->{number} ]]
            );
            if(not $intercept_num_rs->first) {
                $c->log->error("invalid local number '$$resource{number}'");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Number does not exist locally");
                last;
            }
        }
	# use the long way, since with ossbss provisioning, the reseller_id
	# is not set in this case
        $resource->{reseller_id} = $num_rs->first->subscriber->contract->contact->reseller_id;

        my $sub = $num_rs->first->subscriber;
        unless($sub) {
            $c->log->error("invalid number '$$resource{number}', not assigned to any subscriber");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Number is not active");
            last;
        }
        $resource->{sip_username} = NGCP::Panel::Utils::Interception::username_to_regexp_pattern($c,$num_rs->first,$sub->username);
        $resource->{sip_domain} = $sub->domain->domain;

        if($resource->{x3_required} && (!defined $resource->{x3_host} || !defined $resource->{x3_port})) {
            $c->log->error("Missing parameter 'x3_host' or 'x3_port' with 'x3_required' activated");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing parameter 'x3_host' or 'x3_port' with 'x3_required' activated");
            last;
        }
        if (defined $resource->{x3_port} && !is_int($resource->{x3_port})) {
            $c->log->error("Parameter 'x3_port' should be an integer");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Parameter 'x3_port' should be an integer");
            last;
        }

        my ($uuid_bin, $uuid_string);
        UUID::generate($uuid_bin);
        UUID::unparse($uuid_bin, $uuid_string);
        $resource->{uuid} = $uuid_string;

        $resource->{deleted} = 0;
        $resource->{create_timestamp} = $resource->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;

        my $item;
        my $dbresource = { %{ $resource } };
        $dbresource = $self->resnames_to_dbnames($dbresource);
        $dbresource->{reseller_id} = $resource->{reseller_id};
        try {
            $item = $c->model('InterceptDB')->resultset('voip_intercept')->create($dbresource);
            my $res = NGCP::Panel::Utils::Interception::request($c, 'POST', undef, {
                liid => $resource->{liid},
                uuid => $resource->{uuid},
                number => $resource->{number},
                sip_username => NGCP::Panel::Utils::Interception::username_to_regexp_pattern($c,$num_rs->first,$sub->username),
                sip_domain => $sub->domain->domain,
                delivery_host => $resource->{x2_host},
                delivery_port => $resource->{x2_port},
                delivery_user => $resource->{x2_user},
                delivery_password => $resource->{x2_password},
                cc_required => $resource->{x3_required},
                cc_delivery_host => $resource->{x3_host},
                cc_delivery_port => $resource->{x3_port},
            });
            die "Failed to populate capture agents\n" unless($res);
        } catch($e) {
            $c->log->error("failed to create interception: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create interception");
            last;
        }

        $guard->commit;
        $cguard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
