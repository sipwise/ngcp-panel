package NGCP::Panel::Role::API::Voicemails;
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
use NGCP::Panel::Form::Voicemail::Meta;

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voicemail_spool')->search({
        duration => { '!=' => '' },
        'voip_subscriber.id' => { '!=' => undef },
    },{
            join => { mailboxuser => { provisioning_voip_subscriber => 'voip_subscriber' } }
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ 
            'contact.reseller_id' => $c->user->reseller_id 
        },{
            join => { mailboxuser => { provisioning_voip_subscriber => { voip_subscriber => { contract => 'contact' } } } }
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Voicemail::Meta->new;
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
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->mailboxuser->provisioning_voip_subscriber->voip_subscriber->id)),
            Data::HAL::Link->new(relation => 'ngcp:voicemailrecordings', href => sprintf("/api/voicemailrecordings/%d", $item->id)),
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
    $resource{duration} = $item->duration->is_int ? int($item->duration) : 0;
    $resource{time} = "" . $item->origtime;
    $resource{caller} = $item->callerid;
    $resource{subscriber_id} = int($item->mailboxuser->provisioning_voip_subscriber->voip_subscriber->id);

    # type is last item of path like /var/spool/asterisk/voicemail/default/uuid/INBOX
    my @p = split '/', $item->dir;
    $resource{folder} = pop @p;

    return \%resource;
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

    my $f = $resource->{folder};
    my $upresource = {};
    $upresource->{dir} = $item->dir;
    $upresource->{dir} =~ s/\/[^\/]+$/\/$f/;

    $item->update($upresource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
