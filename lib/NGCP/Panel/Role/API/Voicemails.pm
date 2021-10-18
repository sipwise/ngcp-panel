package NGCP::Panel::Role::API::Voicemails;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::API::Calllist qw();

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voicemail_spool')->search({
        duration => { '!=' => '' },
        'voip_subscriber.id' => { '!=' => undef },
    },{
            join => { mailboxuser => { provisioning_voip_subscriber => 'voip_subscriber' } }
    });
    if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
    } elsif ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id
        },{
            join => { mailboxuser => { provisioning_voip_subscriber => { voip_subscriber => { contract => 'contact' } } } }
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search({
            'contract.id' => $c->user->account_id,
        },{
            join => { mailboxuser => { provisioning_voip_subscriber => { voip_subscriber => 'contract' } } }
        });
    } elsif ($c->user->roles eq "subscriber") {
        $item_rs = $item_rs->search({
            'voip_subscriber.uuid' => $c->user->uuid,
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Voicemail::Meta", $c);
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

    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T',
    );

    my %resource = ();
    $resource{id} = int($item->id);
    $resource{duration} = is_int($item->duration) ? int($item->duration) : 0;
    $resource{time} = "" . NGCP::Panel::Utils::API::Calllist::apply_owner_timezone($self,$c,$item->origtime,
        NGCP::Panel::Utils::API::Calllist::get_owner_data($self,$c, undef, undef, 1)
    );
    $resource{caller} = $item->callerid;
    $resource{subscriber_id} = int($item->mailboxuser->provisioning_voip_subscriber->voip_subscriber->id);

    # type is last item of path like /var/spool/asterisk/voicemail/default/uuid/INBOX
    my @p = split /\//, $item->dir;
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
    my $dir_old = $item->dir;
    $upresource->{dir} =~ s/\/[^\/]+$/\/$f/;

    $item->update($upresource);

    my $cli  = $item->mailboxuser->provisioning_voip_subscriber->username;
    my $uuid = $item->mailboxuser->provisioning_voip_subscriber->uuid;

    if ($dir_old ne $upresource->{dir}) {
        NGCP::Panel::Utils::Subscriber::vmnotify(c => $c, cli => $cli, uuid => $uuid);
    }

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
