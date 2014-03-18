package NGCP::Panel::Role::API::CustomerContacts;
use Moose::Role;
use Sipwise::Base;
with 'NGCP::Panel::Role::API' => {
    -alias       =>{ item_rs  => '_item_rs', },
    -excludes    => [ 'item_rs' ],
};

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Contact::Admin;
use NGCP::Panel::Form::Contact::Reseller;

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('contacts')
        ->search({ reseller_id => { '-not' => undef } });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            reseller_id => $c->user->reseller_id,
        });
    } else {
        $item_rs = $item_rs->search({
            reseller_id => $c->user->contract->contact->reseller_id,
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::Contact::Admin->new;
    } elsif($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::Contact::Reseller->new;
    }
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

    my $contact_rs = $self->item_rs($c);
    return $contact_rs->find($id);
}

sub update_contact {
    my ($self, $c, $contact, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    # TODO: for some reason, formhandler lets missing reseller_id slip thru
    $resource->{reseller_id} //= undef; 
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $now = NGCP::Panel::Utils::DateTime::current_local;
    $resource->{modify_timestamp} = $now;

    if($old_resource->{reseller_id} != $resource->{reseller_id}) {
        my $reseller = $c->model('DB')->resultset('resellers')->find($resource->{reseller_id});
        unless($reseller) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'reseller_id'");
            return;
        }
    }

    $contact->update($resource);

    return $contact;
}

1;
# vim: set tabstop=4 expandtab:
