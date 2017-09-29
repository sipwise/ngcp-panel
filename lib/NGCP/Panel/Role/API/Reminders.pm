package NGCP::Panel::Role::API::Reminders;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Preferences;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_reminder');
    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id
        },{
            join => { subscriber => { voip_subscriber => { contract => 'contact' } } },
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search({
            'contract.id' => $c->user->account_id,
            '-or' => [
                    'voip_subscriber_profile_left.id' => undef,
                    'attribute.attribute' => 'reminder',
                ],
        },{
            join => { subscriber => [
                        { voip_subscriber => 'contract' },
                        { voip_subscriber_profile_left => { profile_attributes => 'attribute' } },
                    ] },
        });
    } elsif ($c->user->roles eq "subscriber") {
        $item_rs = $item_rs->search({
            'subscriber.uuid' => $c->user->uuid,
            '-or' => [
                    'voip_subscriber_profile_left.id' => undef,
                    'attribute.attribute' => 'reminder',
                ],
        },{
            join => { 'subscriber' => { voip_subscriber_profile_left => {profile_attributes => 'attribute' } } },
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Reminder::API", $c);
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

    $form //= $self->get_form($c);
    my $resource = $self->resource_from_item($c, $item, $form);

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
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->subscriber->voip_subscriber->id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );


    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
        exceptions => [ "subscriber_id" ],
    );

    $resource->{id} = int($item->id);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my $resource = { $item->get_inflated_columns };
    $resource->{subscriber_id} = int($item->subscriber->voip_subscriber->id);

    return $resource;
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
        exceptions => [ "subscriber_id" ],
    );
    my $sub = $self->get_subscriber_by_id($c, $resource->{subscriber_id} );
    return unless $sub;

    my $allowed_prefs = NGCP::Panel::Utils::Preferences::get_subscriber_allowed_prefs(
        c => $c,
        prov_subscriber => $sub->provisioning_voip_subscriber,
        pref_list => ['reminder'],
    );
    unless ($allowed_prefs->{reminder}) {
        $c->log->error("Not permitted to edit reminder via subscriber profile");
        $self->error($c, HTTP_FORBIDDEN, "Not permitted to edit reminder");
        return;
    }

    $resource->{subscriber_id} = $sub->provisioning_voip_subscriber->id;

    my $dup = $c->model('DB')->resultset('voip_reminder')->search({
        subscriber_id => $resource->{subscriber_id},
        id => { '!=' => $item->id },
    })->count;
    if($dup) {
        $c->log->error("already existing reminder for subscriber_id '$$resource{subscriber_id}'"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber already has a reminder");
        return;
    }

    $item->update($resource);

    return $item;
}

sub get_subscriber_by_id {
    my ($self, $c, $subscriber_id) = @_;

    my $sub_rs = $c->model('DB')->resultset('voip_subscribers')->search({
        'me.id' =>  $subscriber_id,
    });
    if ($c->user->roles eq "reseller") {
        $sub_rs = $sub_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => { contract => 'contact' },
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $sub_rs = $sub_rs->search({
            'contract.id' => $c->user->account_id,
        },{
            join => 'contract',
        });
    } elsif ($c->user->roles eq "subscriber") {
        # quitely override any given subscriber_id, we don't need it
        $sub_rs = $c->model('DB')->resultset('voip_subscribers')->search({
            'me.uuid' => $c->user->uuid,
        });
    }
    my $sub = $sub_rs->first;
    unless ($sub && $sub->provisioning_voip_subscriber) {
        $c->log->error("invalid subscriber_id '$subscriber_id'"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber does not exist");
        return;
    }
    return $sub;
}

1;
# vim: set tabstop=4 expandtab:
