package NGCP::Panel::Controller::API::ContractsItem;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Form::Contract::PeeringReseller qw();
use NGCP::Panel::Utils::ValidateJSON qw();
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API';

class_has('resource_name', is => 'ro', default => 'contracts');
class_has('dispatch_path', is => 'ro', default => '/api/contracts/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-contracts');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => 'api_admin',
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $contract = $self->contract_by_id($c, $id);
        last unless $self->resource_exists($c, contract => $contract);

        my $form = NGCP::Panel::Form::Contract::PeeringReseller->new;
        my $hal = $self->hal_from_contract($c, $contract, $form);

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|;
                s/rel=self/rel="item self"/;
                $_
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub HEAD :Allow {
    my ($self, $c, $id) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c, $id) = @_;
    my $allowed_methods = $self->allowed_methods;
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Patch => 'application/json-patch+json',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub PATCH :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;
        my $json = $self->get_valid_patch_data(
            c => $c, 
            id => $id,
            media_type => 'application/json-patch+json',
        );
        last unless $json;

        my $contract = $self->contract_by_id($c, $id);
        last unless $self->resource_exists($c, contract => $contract);
        my $resource = { $contract->get_inflated_columns };
        $resource = $self->apply_patch($c, $resource, $json);
        last unless $resource;

        my $form = NGCP::Panel::Form::Contract::PeeringReseller->new;
        last unless $self->validate_form(
            c => $c,
            form => $form,
            resource => $resource
        );

        $resource->{modify_timestamp} = DateTime->now;
        $contract->update($resource);

        # TODO: what about changed product, billing-profile etc?
        # TODO: guess we need to update billing-mappings also
        # TODO: handle termination, ....

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            my $hal = $self->hal_from_contract($c, $contract);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $form = NGCP::Panel::Form::Contract::PeeringReseller->new;
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        $resource->{modify_timestamp} = DateTime->now;
        my $contract = $self->contract_by_id($c, $id);

        $contract->update($resource);
        # TODO: again, billing-mappings etc

        # TODO: handle termination, ....
        # TODO: handle termination, ....

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            my $hal = $self->hal_from_contract($c, $contract, $form);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $contract = $self->contract_by_id($c, $id);
        last unless $self->resource_exists($c, contract => $contract);

        # TODO: do we want to prevent deleting used contracts?
        #my $contract_count = $c->model('DB')->resultset('contracts')->search({
        #    contact_id => $id
        #});
        #if($contract_count > 0) {
        #    $self->error($c, HTTP_LOCKED, "Contact is still in use.");
        #    last;
        #} else {
            $contract->delete;
        #}
        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub contract_by_id : Private {
    my ($self, $c, $id) = @_;

    # we only return system contracts, that is, those with contacts without
    # reseller
    my $contract_rs = $c->model('DB')->resultset('contracts')
        ->search({ 
            'contact.reseller_id' => undef 
        }, {
            join => 'contact'
        });
    return $contract_rs->find({'me.id' => $id});
}

sub hal_from_contract : Private {
    my ($self, $c, $contract) = @_;
    my %resource = $contract->get_inflated_columns;
    my $id = $resource{id};

    # TODO: fixxxxxx
    my $billing_profile_id = 1;
    my $contract_balance_id = 1;

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("/%s", $c->request->path)),
            Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $billing_profile_id)),
            Data::HAL::Link->new(relation => 'ngcp:contractbalances', href => sprintf("/api/contractbalances/%d", $contract_balance_id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    # TODO: add billing_profile_id, contract_balance_id etc to
    # %resource as well

    my $form = NGCP::Panel::Form::Contract::PeeringReseller->new;
    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
    );

    $hal->resource({%resource});
    return $hal;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
