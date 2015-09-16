package NGCP::Panel::Role::API::Faxes;
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
use NGCP::Panel::Form::Subscriber::Webfax;
use NGCP::Panel::Utils::Subscriber;

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('fax_journal')->search({
        'voip_subscriber.id' => { '!=' => undef },
    },{
        join => { subscriber => { provisioning_voip_subscriber => 'voip_subscriber' } }
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id
        },{
            join => { subscriber => { provisioning_voip_subscriber => { voip_subscriber => { contract => 'contact' } } } }
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Subscriber::Webfax->new;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

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
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->subscriber->provisioning_voip_subscriber->voip_subscriber->id)),
            Data::HAL::Link->new(relation => 'ngcp:faxrecordings', href => sprintf("/api/faxrecordings/%d", $item->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $resource = $self->resource_from_item($c, $item, $form);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    $form //= $self->get_form($c);

    my %resource = ();
    $resource{id} = int($item->id);
    $resource{time} = "" . $item->the_timestamp;
    $resource{subscriber_id} = int($item->subscriber->provisioning_voip_subscriber->voip_subscriber->id);
    foreach(qw/direction peer_name peer_number reason status quality filename/){
        $resource{$_} = $item->$_;
    }
    foreach(qw/duration pages signal_rate/){
        $resource{$_} = $item->$_->is_int ? $item->$_ : 0;
    }
    return \%resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

1;
# vim: set tabstop=4 expandtab:
