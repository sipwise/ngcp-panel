package NGCP::Panel::Role::API::BillingNetworks;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::Reseller qw();
use NGCP::Panel::Utils::BillingNetworks qw();

sub _usage_select_entries {
    my ($self, %opts) = @_;
    my @select;

    if ($opts{contract_cnt}) {
        my $limit = $opts{contract_cnt_limit};
        $limit = 10 if !defined($limit) || $limit eq '' || !is_int($limit);
        push @select, { '' => \[ NGCP::Panel::Utils::BillingNetworks::get_contract_count_stmt($limit) ], -as => 'contract_cnt' };
    }
    if ($opts{contract_exists}) {
        push @select, { '' => \[ NGCP::Panel::Utils::BillingNetworks::get_contract_exists_stmt() ], -as => 'contract_exists' };
    }
    if ($opts{package_cnt}) {
        push @select, { '' => \[ NGCP::Panel::Utils::BillingNetworks::get_package_count_stmt() ], -as => 'package_cnt' };
    }

    return @select;
}

sub _usage_search_attrs {
    my ($self, $c) = @_;
    my $params = $c->req->query_params;
    my @select = $self->_usage_select_entries(
        contract_cnt       => exists $params->{contract_cnt},
        contract_cnt_limit => (exists $params->{contract_cnt} ? $params->{contract_cnt} : undef),
        contract_exists    => exists $params->{contract_exists},
        package_cnt        => exists $params->{package_cnt},
    );

    return @select ? { '+select' => \@select } : {};
}

sub _load_network_usage_columns {
    my ($self, $c, $network) = @_;
    return $network if $network->has_column_loaded('contract_exists');

    my @select = $self->_usage_select_entries(
        contract_exists    => 1,
        contract_cnt       => 1,
        contract_cnt_limit => 10,
    );
    ($network) = $c->model('DB')->resultset('billing_networks')->search(
        { 'me.id' => $network->id },
        { '+select' => \@select },
    )->all;
    return $network;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::BillingNetwork::NetworkAPI", $c);
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

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

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    my $params = $c->req->query_params;
    if (exists $params->{contract_cnt} && $item->has_column_loaded('contract_cnt')) {
        $resource{contract_cnt} = int($item->get_column('contract_cnt'));
    }
    if (exists $params->{contract_exists} && $item->has_column_loaded('contract_exists')) {
        $resource{contract_exists} = $item->get_column('contract_exists') ? 1 : 0;
    }
    if (exists $params->{package_cnt} && $item->has_column_loaded('package_cnt')) {
        $resource{package_cnt} = int($item->get_column('package_cnt'));
    }

    return \%resource;
}

sub hal_from_item {
    my ($self, $c, $item, $resource, $form) = @_;

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:".$self->resource_name, href => sprintf("/api/%s/%d", $self->resource_name, $item->id)),
            $self->get_journal_relation_link($c, $item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $self->expand_fields($c, $resource);
    $hal->resource($resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('billing_networks')->search_rs();
    my $search_xtra = $self->_usage_search_attrs($c);
    if($c->user->roles eq "admin") {
        $item_rs = $item_rs->search({
            'me.status' => { '!=' => 'terminated' },
        }, $search_xtra);
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            reseller_id => $c->user->reseller_id,
            'me.status' => { '!=' => 'terminated' },
        }, $search_xtra);
    } else {
        $item_rs = $item_rs->search({
            'me.status' => { '!=' => 'terminated' },
        }, $search_xtra);
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

    $item = $self->_load_network_usage_columns($c, $item);

    delete $resource->{id};
    my $schema = $c->model('DB');

    $form //= $self->get_form($c);
    # TODO: for some reason, formhandler lets missing reseller slip thru
    $resource->{reseller_id} //= undef;
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
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
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create billingnetwork.", $e);
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
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
    });
}

1;
# vim: set tabstop=4 expandtab:
