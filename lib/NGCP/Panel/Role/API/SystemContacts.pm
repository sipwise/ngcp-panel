package NGCP::Panel::Role::API::SystemContacts;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Contact::Reseller;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('contacts')->search({
        reseller_id => undef,
        'me.status' => { '!=' => 'terminated' },
    });
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Contact::Reseller->new;
}

sub hal_from_contact {
    my ($self, $c, $contact, $form) = @_;
    my %resource = $contact->get_inflated_columns;


    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $contact->id)),
            $self->get_journal_relation_link($contact->id),

        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $resource{country}{id} = delete $resource{country};
    $resource{timezone}{name} = delete $resource{timezone};
    $form //= $self->get_form($c);

    # TODO: i'd expect reseller to be removed automatically
    delete $resource{reseller_id};
    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
    );
    $resource{country} = $resource{country}{id};
    $resource{timezone} = $resource{timezone}{name};

    $resource{id} = int($contact->id);
    $hal->resource({%resource});
    return $hal;
}

sub contact_by_id {
    my ($self, $c, $id) = @_;
    my $contact_rs = $self->item_rs($c);
    return $contact_rs->find($id);
}

sub update_contact {
    my ($self, $c, $contact, $old_resource, $resource, $form) = @_;

    $resource->{country}{id} = delete $resource->{country};
    $resource->{timezone}{name} = delete $resource->{timezone};
    $form //= $self->get_form($c);
    delete $resource->{reseller_id};
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );
    $resource->{country} = $resource->{country}{id};
    $resource->{timezone} = $resource->{timezone}{name};

    my $now = NGCP::Panel::Utils::DateTime::current_local;
    $resource->{modify_timestamp} = $now;

    $contact->update($resource);

    return $contact;
}

1;
# vim: set tabstop=4 expandtab:
