package NGCP::Panel::Role::API::LnpNumbers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Lnp::Number;
use NGCP::Panel::Utils::Lnp qw();

sub _item_rs {
    my ($self, $c, $now, $number) = @_;
    return NGCP::Panel::Utils::Lnp::get_lnpnumber_rs($c, $now, $number);
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Lnp::Number->new(ctx => $c); #no bottleneck
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my %resource = $item->get_inflated_columns; #no bottleneck

    my $hal = NGCP::Panel::Utils::DataHal->new(
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
    $resource{start} =~ s/T\d{2}:\d{2}:\d{2}(\+.+)?$// if $resource{start};
    $resource{end} =~ s/T\d{2}:\d{2}:\d{2}(\+.+)?$// if $resource{end};
    $hal->resource({%resource});
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item) = @_;
    my $r = { $item->get_inflated_columns };
    $r->{carrier_id} = delete $r->{lnp_provider_id};
    $r->{start} =~ s/T\d{2}:\d{2}:\d{2}(\+.+)?$// if $r->{start};
    $r->{end} =~ s/T\d{2}:\d{2}:\d{2}(\+.+)?$// if $r->{end};
    return $r;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c); #no bottleneck
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

    $resource->{start} ||= undef;
    if($resource->{start} && $resource->{start} =~ /^\d{4}-\d{2}-\d{2}$/) {
        $resource->{start} .= 'T00:00:00';
    }
    $resource->{end} ||= undef;
    if($resource->{end} && $resource->{end} =~ /^\d{4}-\d{2}-\d{2}$/) {
        $resource->{end} .= 'T23:59:59';
    }

    $item->update($resource);
    $item->discard_changes;

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
