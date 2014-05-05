package NGCP::Panel::Role::API::SubscriberProfiles;
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
use NGCP::Panel::Form::SubscriberProfile::ApiProfile;

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_subscriber_profiles');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ 'profile_set.reseller_id' => $c->user->reseller_id }, {
            join => 'profile_set',
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::SubscriberProfile::ApiProfile->new;
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
            Data::HAL::Link->new(relation => 'ngcp:subscriberprofilesets', href => sprintf("/api/subscriberprofilesets/%d", $item->set_id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $resource->{attribute} = delete $resource->{attributes};
    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
    );

    $resource->{attributes} = delete $resource->{attribute};
    $resource->{id} = int($item->id);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    $form //= $self->get_form($c);

    my %resource = $item->get_inflated_columns;
    my @att = map { $_->attribute->attribute } $item->profile_attributes->all;
    $resource{attributes} = \@att;
    $resource{profile_set_id} = delete $resource{set_id};

    return \%resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    # delete $resource->{attribute} in case reseller not allowed to update set

    $resource->{attribute} = delete $resource->{attributes};
    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );
    $resource->{set_id} = delete $resource->{profile_set_id};

    my $set = $c->model('DB')->resultset('voip_subscriber_profile_sets');
    if($c->user->roles eq "reseller") {
        $set = $set->search({
            reseller_id => $c->user->reseller_id,
        });
    }
    $set = $set->find($resource->{set_id});

    unless($set) {
        $c->log->error("subscriber profile set id '$$resource{set_id}' does not exist"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'profile_set_id', does not exist");
        return;
    }

    my $dup_item = $set->voip_subscriber_profiles->find({
        name => $resource->{name},
    });
    if($dup_item && $dup_item->id != $item->id) {
        $c->log->error("subscriber profile with name '$$resource{name}' already exists for profile_set_id '$$resource{set_id}'"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber profile with this name already exists for this profile set");
        return;
    }

    my $attributes;
    if($c->user->roles eq "reseller" && !$c->config->{profile_sets}->{reseller_edit}) {
        # don't let reseller update attributes in this case
        $attributes = [ map { $_->attribute->attribute } $item->profile_attributes->all ];
    } else {
        $attributes = $resource->{attribute};
    }
    delete $resource->{attribute};

    if($item->set_default && !$resource->{set_default}) {
        $set->voip_subscriber_profiles->first->update({
            set_default => 1,
        });
    } elsif(!$item->set_default && $resource->{set_default}) {
        $set->voip_subscriber_profiles->update({
            set_default => 0,
        });
    }

    $item->update($resource);

    my %old_attributes = map { $_ => 1 }
        $item->profile_attributes->get_column('attribute_id')->all;

    # TODO: reuse attributes for efficiency reasons?
    $item->profile_attributes->delete;

    my $meta_rs = $c->model('DB')->resultset('voip_preferences')->search({
        -or => [
        {
            usr_pref => 1,
            expose_to_customer => 1,
        },
        {
            attribute => { -in => [qw/cfu cft cfna cfb/] },
        },
        ],
    });
    foreach my $a(@{ $attributes }) {
        my $meta = $meta_rs->find({ attribute => $a });
        next unless $meta;
        # mark as seen, so later we can unprovision the remaining ones,
        # which are the ones not set here:
        delete $old_attributes{$meta->id};

        $item->profile_attributes->create({ attribute_id => $meta->id });
    }
    # go over remaining attributes (those which were set before but are not set anymore)
    # and clear them from usr-preferences
    if(keys %old_attributes) {
        my $cfs = $c->model('DB')->resultset('voip_preferences')->search({
            id => { -in => [ keys %old_attributes ] },
            attribute => { -in => [qw/cfu cfb cft cfna/] },
        });
        my @subs = $c->model('DB')->resultset('provisioning_voip_subscribers')
            ->search({
                profile_id => $item->id,
            })->all;
        foreach my $sub(@subs) {
            $sub->voip_usr_preferences->search({
                attribute_id => { -in => [ keys %old_attributes ] },
            })->delete;
            $sub->voip_cf_mappings->search({
                type => { -in => [ map { $_->attribute } $cfs->all ] },
            })->delete;
        }
    }
        
    return $item;
}

1;
# vim: set tabstop=4 expandtab:
