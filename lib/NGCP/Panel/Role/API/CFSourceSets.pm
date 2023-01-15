package NGCP::Panel::Role::API::CFSourceSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::Subscriber;

use NGCP::Panel::Form;

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "subscriber") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFSourceSetSubAPI", $c);
    } elsif($c->user->roles eq "subscriberadmin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFSourceSetSubAPI", $c);
    } else {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFSourceSetAPI", $c);
    }
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;

    my %resource = $item->get_inflated_columns;
    my @sources;
    for my $dest ($item->voip_cf_sources->all) {
        push @sources, { $dest->get_inflated_columns, };
        delete @{$sources[-1]}{'source_set_id', 'id'};
    }
    $resource{sources} = \@sources;

    my $b_subs_id = $item->subscriber->voip_subscriber->id;
    $resource{subscriber_id} = $b_subs_id;

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:subscribers", href => sprintf("/api/subscribers/%d", $b_subs_id)),
            $self->get_journal_relation_link($c, $item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    $self->expand_fields($c, \%resource);
    $hal->resource(\%resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
        $item_rs = $c->model('DB')->resultset('voip_cf_source_sets');
    } elsif ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        my $reseller_id = $c->user->reseller_id;
        $item_rs = $c->model('DB')->resultset('voip_cf_source_sets')->search_rs({
            'reseller_id' => $reseller_id,
        },{
            join => {'subscriber' => {'contract' => 'contact'} },
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $c->model('DB')->resultset('voip_cf_source_sets')->search_rs({
            'subscriber.account_id' => $c->user->account_id,
        },{
            join => 'subscriber',
        });
    } elsif ($c->user->roles eq "subscriber") {
        $item_rs = $c->model('DB')->resultset('voip_cf_source_sets')->search_rs({
            '-or' => [
                'me.subscriber_id' => $c->user->id,
                'voip_cf_mappings.subscriber_id' => $c->user->id,
            ]
        },{
            join => 'voip_cf_mappings',
        });
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub check_subscriber_can_update_item {
    my ($self, $c, $item) = @_;

    if ($c->user->roles eq 'subscriber' && $c->user->id != $item->subscriber_id) {
        $self->error($c, HTTP_FORBIDDEN, "This source set does not belong to the user");
        return;
    }

    return 1;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};
    my $schema = $c->model('DB');

    return unless $self->check_subscriber_can_update_item($c, $item);

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    if (! exists $resource->{sources} ) {
        $resource->{sources} = [];
    }
    if (ref $resource->{sources} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'sources'. Must be an array.");
        return;
    }

    if($c->user->roles eq "subscriber" || $c->user->roles eq "subscriberadmin") {
        $resource->{subscriber_id} = $c->user->voip_subscriber->id;
    }
    # elsif($c->user->roles eq "subscriberadmin") {
    #    $resource->{subscriber_id} //= $c->user->id;
    #}

    my $b_subscriber = $schema->resultset('voip_subscribers')->find($resource->{subscriber_id});
    unless ($b_subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'.");
        return;
    }
    my $subscriber = $b_subscriber->provisioning_voip_subscriber;
    unless($subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
        last;
    }
    #if($c->user->roles eq "subscriberadmin" && $subscriber->account_id != $c->user->account_id) {
    #    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
    #    last;
    #}

    return unless $self->process_form_resource($c, $item, $old_resource, $resource, $form);
    return unless $self->check_duplicate($c, $item, $old_resource, $resource, $form);
    return unless $self->check_resource($c, $item, $old_resource, $resource, $form);

    try {
        $item->update({
                name => $resource->{name},
                mode => $resource->{mode},
                (defined $resource->{is_regex} ? (is_regex => $resource->{is_regex}) : ()),
                subscriber_id => $subscriber->id,
            })->discard_changes;
        $item->voip_cf_sources->delete;
        for my $s ( @{$resource->{sources}} ) {
            $item->create_related("voip_cf_sources", {
                    source => $s->{source},
                });
        }
        $item->discard_changes;
    } catch($e) {
        $c->log->error("failed to create cfsourceset: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cfsourceset.");
        return;
    };

    return $item;
}

sub process_form_resource{
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $resource->{subscriber_id} = $c->user->voip_subscriber->id;
    } elsif(!defined $resource->{subscriber_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing mandatory field 'subscriber_id'");
        return;
    }

    return $resource;
}

sub check_resource {
    my($self, $c, $item, $old_resource, $resource, $form) = @_;

    my $schema = $c->model('DB');

    my $b_subscriber = $schema->resultset('voip_subscribers')->find({
        id => $resource->{subscriber_id},
    });
    unless($b_subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'.");
        return;
    }
    my $subscriber = $b_subscriber->provisioning_voip_subscriber;
    unless($subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
        return;
    }
    if (! exists $resource->{sources} ) {
        $resource->{sources} = [];
    }
    if (ref $resource->{sources} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'sources'. Must be an array.");
        return;
    }

    return 1; # all good
}

sub check_duplicate {
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $schema = $c->model('DB');

    my $b_subscriber = $schema->resultset('voip_subscribers')->find({
        id => $resource->{subscriber_id},
    });
    unless($b_subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'.");
        return;
    }
    my $subscriber = $b_subscriber->provisioning_voip_subscriber;
    unless($subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
        return;
    }

    my $existing_item = $schema->resultset('voip_cf_source_sets')->search({
        name => $resource->{name},
        subscriber_id => $subscriber->id
    })->first;
    if ($existing_item && (!$item || $item->id != $existing_item->id)) {
        $c->log->error("source_set name '$$resource{name}' already exists");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "A Sourceset with this name already exists");
        return;
    }
    return 1;
}

1;
# vim: set tabstop=4 expandtab:
