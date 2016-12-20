package NGCP::Panel::Role::API::VoicemailSettings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Voicemail::API;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voicemail_users')->search({ 
        'voip_subscriber.status' => { '!=' => 'terminated' },
    }, {
        join => { provisioning_voip_subscriber => { voip_subscriber => { contract => 'contact' } } },
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ 
            'contact.reseller_id' => $c->user->reseller_id,
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Voicemail::API->new;
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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->provisioning_voip_subscriber->voip_subscriber->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->provisioning_voip_subscriber->voip_subscriber->id)),
            $self->get_journal_relation_link($item->provisioning_voip_subscriber->voip_subscriber->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
    );

    $resource->{id} = int($item->provisioning_voip_subscriber->voip_subscriber->id);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my $resource = { $item->get_inflated_columns };
    $resource->{pin} = delete $resource->{password};
    $resource->{delete} = delete $resource->{delete} eq 'yes' ? 1 : 0; 
    $resource->{attach} = delete $resource->{attach} eq 'yes' ? 1 : 0; 
    $resource->{sms_number} = delete $resource->{pager};

    return $resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find({
        'voip_subscriber.id' => $id,
    },{
        join => { provisioning_voip_subscriber => 'voip_subscriber' },
    });
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    $resource->{email} //= "";
    $resource->{delete} = delete $resource->{delete} ? 'yes' : 'no';
    $resource->{attach} = delete $resource->{attach} ? 'yes' : 'no';
    $resource->{password} = delete $resource->{pin};
    $resource->{pager} = delete $resource->{sms_number};
    $resource->{pager} //= "";

    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
