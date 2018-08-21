package NGCP::Panel::Role::API::SystemContacts;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

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
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Contact::Reseller", $c);
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
            $self->get_journal_relation_link($c, $contact->id),

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
