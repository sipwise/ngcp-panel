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
use NGCP::Panel::Form::CFSourceSetAPI;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::CFSourceSetAPI->new;
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;

    my %resource = $item->get_inflated_columns;
    my @sources;
    for my $dest ($item->voip_cf_sources->all) {
        push @sources, { $dest->get_inflated_columns, };
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
            Data::HAL::Link->new(relation => "ngcp:$type", href => sprintf("/api/%s/%d", $type, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:subscribers", href => sprintf("/api/subscribers/%d", $b_subs_id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
        exceptions => [ "subscriber_id" ],
    );
    $hal->resource(\%resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    if($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('voip_cf_source_sets');
    } elsif ($c->user->roles eq "reseller") {
        my $reseller_id = $c->user->reseller_id;
        $item_rs = $c->model('DB')->resultset('voip_cf_source_sets')
            ->search_rs({
                    'reseller_id' => $reseller_id,
                } , {
                    join => {'subscriber' => {'contract' => 'contact'} },
                });
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};
    my $schema = $c->model('DB');

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        exceptions => [ "subscriber_id" ],
    );

    if (! exists $resource->{sources} ) {
        $resource->{sources} = [];
    }
    if (ref $resource->{sources} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'sources'. Must be an array.");
        return;
    }

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

    try {
        $item->update({
                name => $resource->{name},
                subscriber_id => $subscriber->id,
            })->discard_changes;
        $item->voip_cf_sources->delete;
        for my $s ( @{$resource->{sources}} ) {
            # delete $s->{source_set_id};
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

1;
# vim: set tabstop=4 expandtab:
