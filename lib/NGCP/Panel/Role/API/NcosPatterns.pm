package NGCP::Panel::Role::API::NcosPatterns;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('ncos_pattern_list');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ 
            'ncos_level.reseller_id' => $c->user->reseller_id 
        },{
            join => 'ncos_level',
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::NCOS::PatternAPI", $c);
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
            Data::HAL::Link->new(relation => 'ngcp:ncoslevels', href => sprintf("/api/ncoslevels/%d", $item->ncos_level_id)),
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

    my $level_rs = $c->model('DB')->resultset('ncos_levels')->search({
        id => $resource->{ncos_level_id},
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $level_rs = $level_rs->search({
            reseller_id => $c->user->reseller_id,
        });
    }
    my $level = $level_rs->first;
    unless($level) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                     "Invalid ncos_level_id, level does not exist",
                     "invalid ncos_level_id '$$resource{ncos_level_id}' for reseller_id '$$resource{reseller_id}'");
        return;
    }

    my $dup_item = $level->ncos_pattern_lists->search({
        pattern => $resource->{pattern},
    })->first;
    if($dup_item && $dup_item->id != $item->id) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "NCOS pattern already exists for given ncos level",
                     "ncos pattern '$$resource{pattern}' already exists for ncos_level_id '$$resource{ncos_level_id}'");
        return;
    }

    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
