package NGCP::Panel::Role::API::NcosLnpPatterns;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('ncos_lnp_pattern_list');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ 
            'ncos_level.reseller_id' => $c->user->reseller_id 
        },{
            join => {'ncos_lnp_list' => 'ncos_level'},
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::NCOS::LnpPatternAPI", $c);
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my %resource = $item->get_inflated_columns;

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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:ncoslists', href => sprintf("/api/ncoslists/%d", $item->ncos_lnp_list_id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
    );

    $resource{id} = int($item->id);
    $hal->resource({%resource});
    return $hal;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $lnp_list_rs = $c->model('DB')->resultset('ncos_lnp_list')->search({
        id => $resource->{ncos_lnp_list_id},
    });
    my $lnp_list = $lnp_list_rs->first;
    unless($lnp_list) {
        $c->log->error("invalid ncos_lnp_list_id '$$resource{ncos_lnp_list_id}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid ncos_lnp_list_id, lnp list does not exist");
        return;
    }

    my $dup_item = $lnp_list->ncos_lnp_pattern_lists->search({
        pattern => $resource->{pattern},
    })->first;
    if($dup_item && $dup_item->id != $item->id) {
        $c->log->error("ncos pattern '$$resource{pattern}' already exists for ncos_lnp_list_id '$$resource{ncos_lnp_list_id}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "NCOS pattern already exists for given ncos lnp list id");
        return;
    }

    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
