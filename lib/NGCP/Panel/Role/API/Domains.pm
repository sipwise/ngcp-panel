package NGCP::Panel::Role::API::Domains;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::Prosody;

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Domain::Admin", $c);
    } elsif($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Domain::Reseller", $c);
    }
    return;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource = $item->get_inflated_columns;

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
    );

    $resource{id} = int($item->id);

    if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
        $resource{reseller_id} = $item->reseller_id;
    }

    return \%resource;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

    my $resource = $self->resource_from_item($c, $item, $form);

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
            #( map { $_->attribute->internal ? () : Data::HAL::Link->new(relation => 'ngcp:domainpreferences', href => sprintf("/api/domainpreferences/%d", $_->id), name => $_->attribute->attribute) } $item->provisioning_voip_domain->voip_dom_preferences->all ),
            Data::HAL::Link->new(relation => 'ngcp:domainpreferences', href => sprintf("/api/domainpreferences/%d", $item->id)),
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

    my $item_rs;
    if($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
        $item_rs = $c->model('DB')->resultset('domains');
    } elsif($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $item_rs = $c->model('DB')->resultset('domains')->search({
            reseller_id => $c->user->reseller_id,
        });
    }
    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub xmpp_domain_reload {
    my ($self, $c, $domain) = @_;
    NGCP::Panel::Utils::Prosody::activate_domain($c, $domain);
}

sub xmpp_domain_disable {
    my ($self, $c, $domain) = @_;
    NGCP::Panel::Utils::Prosody::deactivate_domain($c, $domain);
}

=pod
# you can't update a domain per se, only its preferences!
sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    $item->update($resource);

    return $item;
}
=cut

1;

__END__

=head1 NAME

NGCP::Panel::Role::API::Domains

=head1 DESCRIPTION

A role to manipulate the domains data via API

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
