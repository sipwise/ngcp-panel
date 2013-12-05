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
use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API';
with 'NGCP::Panel::Role::API::Contracts';

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

        my $hal = $self->hal_from_contract($c, $contract);

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
        my $billing_mapping = $contract->billing_mappings->find($contract->get_column('bmid'));
        my $old_resource = { $contract->get_inflated_columns };
        $old_resource->{billing_profile_id} = $billing_mapping->billing_profile_id;
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = NGCP::Panel::Form::Contract::PeeringReseller->new;
        last unless $self->validate_form(
            c => $c,
            form => $form,
            resource => $resource
        );

        my $now = NGCP::Panel::Utils::DateTime::current_local;
        $resource->{modify_timestamp} = $now;
        if($old_resource->{billing_profile_id} != $resource->{billing_profile_id}) {
            my $billing_profile = $c->model('DB')->resultset('billing_profiles')->find($resource->{billing_profile_id});
            unless($billing_profile) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'billing_profile_id'");
                last;
            }
            $billing_mapping->update({ 
                billing_profile_id => $resource->{billing_profile_id}
            });
        }
        delete $resource->{billing_profile_id};
        $contract->update($resource);

        # TODO: what about changed product, do we allow it?
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

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $contract = $self->contract_by_id($c, $id);
        last unless $self->resource_exists($c, contract => $contract);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        my $billing_mapping = $contract->billing_mappings->find($contract->get_column('bmid'));
        my $old_resource = { $contract->get_inflated_columns };
        $old_resource->{billing_profile_id} = $billing_mapping->billing_profile_id;

        my $form = NGCP::Panel::Form::Contract::PeeringReseller->new;
        last unless $self->validate_form(
            c => $c,
            form => $form,
            resource => $resource
        );

        my $now = NGCP::Panel::Utils::DateTime::current_local;
        $resource->{modify_timestamp} = $now;
        if($old_resource->{billing_profile_id} != $resource->{billing_profile_id}) {
            my $billing_profile = $c->model('DB')->resultset('billing_profiles')->find($resource->{billing_profile_id});
            unless($billing_profile) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'billing_profile_id'");
                last;
            }
            $billing_mapping->update({ 
                billing_profile_id => $resource->{billing_profile_id}
            });
        }
        delete $resource->{billing_profile_id};
        $contract->update($resource);

        # TODO: what about changed product, do we allow it?
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

=pod
# we don't allow to delete contracts
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
=cut

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
