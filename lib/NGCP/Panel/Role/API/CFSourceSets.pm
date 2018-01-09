package NGCP::Panel::Role::API::CFSourceSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
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
    my $adm = $c->user->roles eq "admin" || $c->user->roles eq "reseller";

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => "ngcp:subscribers", href => sprintf("/api/subscribers/%d", $b_subs_id)),
            $adm ? $self->get_journal_relation_link($item->id) : (),
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
    # TODO: do we want subscriberadmins to update other subs' entries?
    } elsif($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $item_rs = $c->model('DB')->resultset('voip_cf_source_sets')
            ->search_rs({
                    'subscriber_id' => $c->user->id,
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

    try {
        $item->update({
                name => $resource->{name},
                mode => $resource->{mode},
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

1;
# vim: set tabstop=4 expandtab:
