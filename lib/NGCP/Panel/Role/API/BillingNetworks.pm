package NGCP::Panel::Role::API::BillingNetworks;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::Reseller qw();
use NGCP::Panel::Utils::BillingNetworks qw();
use NGCP::Panel::Form::BillingNetwork::NetworkAPI;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::BillingNetwork::NetworkAPI->new;
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;

    my %resource = $item->get_inflated_columns;
    my @blocks;
    for my $block ($item->billing_network_blocks->all) {
        my %blockelem = $block->get_inflated_columns;
        delete $blockelem{id};
        delete $blockelem{network_id};
        delete $blockelem{_ipv4_net_from};
        delete $blockelem{_ipv4_net_to};
        delete $blockelem{_ipv6_net_from};
        delete $blockelem{_ipv6_net_to};        
        push @blocks, \%blockelem;
    }
    $resource{blocks} = \@blocks;

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => "ngcp:$type", href => sprintf("/api/%s/%d", $type, $item->id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
        exceptions => [ "reseller_id" ],
    );
    $hal->resource(\%resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('billing_networks')->search_rs({ 'me.status' => { '!=' => 'terminated' } });
    my $search_xtra = {
            '+select' => [ { '' => \[ NGCP::Panel::Utils::BillingNetworks::get_contract_count_stmt() ] , -as => 'contract_cnt' },
                           { '' => \[ NGCP::Panel::Utils::BillingNetworks::get_package_count_stmt() ] , -as => 'package_cnt' }, ],
            };    
    if($c->user->roles eq "admin") {
        $item_rs = $item_rs->search(undef,
                                    $search_xtra);        
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ reseller_id => $c->user->reseller_id },
                                    $search_xtra);
    }
    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};
    my $schema = $c->model('DB');
    
    $form //= $self->get_form($c);
    # TODO: for some reason, formhandler lets missing reseller slip thru
    $resource->{reseller_id} //= undef;
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        exceptions => [ "reseller_id" ],
    );

    return unless NGCP::Panel::Utils::Reseller::check_reseller_update_item($c,$resource->{reseller_id},$old_resource->{reseller_id},sub {
        my ($err) = @_;
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
    });
    
    return unless NGCP::Panel::Utils::BillingNetworks::check_network_update_item($c,$resource,$item,sub {
        my ($err) = @_;
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
    });
   
    return unless $self->prepare_blocks_resource($c,$resource);
    my $blocks = delete $resource->{blocks};
    
    try {
        $item->update($resource);
        $item->billing_network_blocks->delete;        
        for my $block (@$blocks) {
            $item->create_related("billing_network_blocks", $block);
        }
        $item->discard_changes;
    } catch($e) {
        #$c->log->error("failed to create billingnetwork: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create billingnetwork.");
        return;
    };

    return $item;
}

sub prepare_blocks_resource {
    my ($self,$c,$resource) = @_;
    if (! exists $resource->{blocks} ) {
        $resource->{blocks} = [];
    }
    if (ref $resource->{blocks} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'blocks'. Must be an array.");
        return 0;
    }
    return NGCP::Panel::Utils::BillingNetworks::set_blocks_from_to($resource->{blocks},sub {
        my ($err) = @_;
        #$c->log->error($err);
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
    });
}

1;
# vim: set tabstop=4 expandtab:
