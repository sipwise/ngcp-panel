package NGCP::Panel::Role::API::LnpNumbers;
use NGCP::Panel::Utils::Generic qw(:all);

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Lnp::Number;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('lnp_numbers');
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Lnp::Number->new(ctx => $c);
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
            Data::HAL::Link->new(relation => 'ngcp:lnpcarriers', href => sprintf("/api/lnpcarriers/%d", $item->lnp_provider_id)),
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
    $resource{carrier_id} = delete $resource{lnp_provider_id};
    $resource{start} =~ s/T\d{2}:\d{2}:\d{2}(\+.+)?$//;
    $resource{end} =~ s/T\d{2}:\d{2}:\d{2}(\+.+)?$//;
    $hal->resource({%resource});
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item) = @_;
    my $r = { $item->get_inflated_columns };
    $r->{carrier_id} = delete $r->{lnp_provider_id};
    $r->{start} =~ s/T\d{2}:\d{2}:\d{2}(\+.+)?$//;
    $r->{end} =~ s/T\d{2}:\d{2}:\d{2}(\+.+)?$//;
    return $r;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    $resource->{lnp_provider_id} = delete $resource->{carrier_id};
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $carrier = $c->model('DB')->resultset('lnp_providers')->find($resource->{lnp_provider_id});
    unless($carrier) {
        $c->log->error("invalid carrier_id '$$resource{lnp_provider_id}'"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "LNP carrier_id does not exist");
        return;
    }

=pod
    # for now numbers can be inserted duplicated, so don't check
    my $dup_item = $c->model('DB')->resultset('lnp_numbers')->find({
        lnp_provider_id => $resource->{lnp_provider_id},
        number => $resource->{number},
    });
    if($dup_item && $dup_item->id != $item->id) {
        $c->log->error("lnp number with number '$$resource{number}' already exists for carrier_id '$$resource{lnp_provider_id}'"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "LNP number with this number already exists for this carrier");
        return;
    }
=cut

    $resource->{start} ||= undef;
    if($resource->{start} && $resource->{start} =~ /^\d{4}-\d{2}-\d{2}$/) {
        $resource->{start} .= 'T00:00:00';
    }
    $resource->{end} ||= undef;
    if($resource->{end} && $resource->{end} =~ /^\d{4}-\d{2}-\d{2}$/) {
        $resource->{end} .= 'T23:59:59';
    }

    $item->update($resource);
    $item->discard_changes; # agranig: otherwise start/end is not updated!?

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
