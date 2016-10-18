package NGCP::Panel::Controller::API::ContractsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract qw();
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Contracts/;

sub resource_name{
    return 'contracts';
}
sub dispatch_path{
    return '/api/contracts/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-contracts';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->config(
    action => {
        (map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => 'admin',
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }),
        @{ __PACKAGE__->get_journal_action_config(__PACKAGE__->resource_name,{
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => 'admin',
            Does => [qw(ACL RequireSSL)],
        }) } 
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
    #$self->apply_fake_time($c);    
    return 1;
}

sub GET :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->contract_by_id($c, $id);
        last unless $self->resource_exists($c, contract => $item);

        my $hal = $self->hal_from_contract($c, $item, undef, NGCP::Panel::Utils::DateTime::current_local);
        $guard->commit; #potential db write ops in hal_from

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|r =~
                s/rel=self/rel="item self"/r;
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}





sub PATCH :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
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

        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $item = $self->contract_by_id($c, $id, $now);
        last unless $self->resource_exists($c, contract => $item);
        
        my $old_resource = { $item->get_inflated_columns };
        my $billing_mapping = $item->billing_mappings->find($item->get_column('bmid'));
        $old_resource->{billing_profile_id} = $billing_mapping->billing_profile_id;
        $old_resource->{billing_profile_definition} = undef;
        delete $old_resource->{profile_package_id};

        my $resource = $self->apply_patch($c, $old_resource, $json, sub {
            my ($missing_field,$entity) = @_;
            if ($missing_field eq 'billing_profiles') {
                $entity->{billing_profiles} = NGCP::Panel::Utils::Contract::resource_from_future_mappings($item);
                $entity->{billing_profile_definition} //= 'profiles';
            }
        });
        last unless $resource;

        my $form = $self->get_form($c);
        $item = $self->update_contract($c, $item, $old_resource, $resource, $form, $now);
        last unless $item;

        my $hal = $self->hal_from_contract($c, $item, $form, $now);
        last unless $self->add_update_journal_item_hal($c, $hal);
        
        $guard->commit;

        $self->return_representation($c, 'hal' =>$hal, 'preference' => $preference );
    }
    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $item = $self->contract_by_id($c, $id, $now);
        last unless $self->resource_exists($c, contract => $item);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $item->get_inflated_columns };
        my $billing_mapping = $item->billing_mappings->find($item->get_column('bmid'));
        $old_resource->{type} = $billing_mapping->product->class;

        my $form = $self->get_form($c);
        $item = $self->update_contract($c, $item, $old_resource, $resource, $form, $now);
        last unless $item;
        
        my $hal = $self->hal_from_contract($c, $item, $form, $now);
        last unless $self->add_update_journal_item_hal($c, $hal);

        $guard->commit;

        $self->return_representation($c, 'hal' =>$hal, 'preference' => $preference );
    }
    return;
}

=pod

# we don't allow to delete contracts
sub DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $item = $self->contract_by_id($c, $id);
        last unless $self->resource_exists($c, contract => $item);

        # TODO: do we want to prevent deleting used contracts?
        #my $contract_count = $c->model('DB')->resultset('contracts')->search({
        #    contact_id => $id
        #});
        #if($contract_count > 0) {
        #    $self->error($c, HTTP_LOCKED, "Contact is still in use.");
        #    last;
        #} else {
            $item->delete;
        #}
        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

=cut

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

sub end : Private {
    my ($self, $c) = @_;

    #$self->reset_fake_time($c);
    $self->log_response($c);
    return;
}

1;

# vim: set tabstop=4 expandtab:
