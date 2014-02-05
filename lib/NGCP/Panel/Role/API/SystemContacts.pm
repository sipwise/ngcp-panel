package NGCP::Panel::Role::API::SystemContacts;
use Moose::Role;
use Sipwise::Base;

use boolean qw(true);
use Try::Tiny;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Contact::Reseller;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Contact::Reseller->new;
}

sub hal_from_contact {
    my ($self, $c, $contact, $form) = @_;
    my %resource = $contact->get_inflated_columns;


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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $contact->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    # TODO: i'd expect reseller to be removed automatically
    delete $resource{reseller_id};
    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
    );

    $resource{id} = int($contact->id);
    $hal->resource({%resource});
    return $hal;
}

sub contact_by_id {
    my ($self, $c, $id) = @_;

    # we only return system contacts, that is, a contact without reseller
    my $contact_rs = $c->model('DB')->resultset('contacts')
        ->search({ reseller_id => undef });
    return $contact_rs->find($id);
}

sub update_contact {
    my ($self, $c, $contact, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    delete $resource->{reseller_id};
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $now = NGCP::Panel::Utils::DateTime::current_local;
    $resource->{modify_timestamp} = $now;

    $contact->update($resource);

    return $contact;
}

1;
# vim: set tabstop=4 expandtab:
