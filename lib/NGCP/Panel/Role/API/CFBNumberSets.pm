package NGCP::Panel::Role::API::CFBNumberSets;
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

sub resource_name {
    return 'cfbnumbersets';
}

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "subscriber") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFBNumberSetSubAPI", $c);
    } elsif($c->user->roles eq "subscriberadmin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFBNumberSetSubAPI", $c);
    } else {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFBNumberSetAPI", $c);
    }
}

sub hal_links{
    my($self, $c, $item, $resource, $form) = @_;
    return [
        Data::HAL::Link->new(relation => "ngcp:subscribers", href => sprintf("/api/subscribers/%d", $resource->{subscriber_id})),
    ];
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    if($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('voip_cf_bnumber_sets');
    } elsif ($c->user->roles eq "reseller") {
        my $reseller_id = $c->user->reseller_id;
        $item_rs = $c->model('DB')->resultset('voip_cf_bnumber_sets')
            ->search_rs({
                    'reseller_id' => $reseller_id,
                } , {
                    join => {'subscriber' => {'contract' => 'contact'} },
                });
    # TODO: do we want subscriberadmins to update other subs' entries?
    } elsif($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $item_rs = $c->model('DB')->resultset('voip_cf_bnumber_sets')
            ->search_rs({
                    'subscriber_id' => $c->user->id,
                });
    }

    return $item_rs;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my $resource = { $item->get_inflated_columns };
    my $psub = $item->subscriber;
    if ($psub && $psub->voip_subscriber) {
        $resource->{subscriber_id} = int($psub->voip_subscriber->id);
    } else {
        delete $resource->{subscriber_id};
    }

    my @bnumbers;
    for my $dest ($item->voip_cf_bnumbers->all) {
        push @bnumbers, { $dest->get_inflated_columns, };
        delete @{$bnumbers[-1]}{'bnumber_set_id', 'id'};
    }
    $resource->{bnumbers} = \@bnumbers;

    return $resource;
}

sub check_resource {
    my($self, $c, $item, $old_resource, $resource, $form) = @_;

    my $schema = $c->model('DB');

    if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $resource->{subscriber_id} = $c->user->voip_subscriber->id;
    } elsif(!defined $resource->{subscriber_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing mandatory field 'subscriber_id'");
        return;
    }

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
    if (! exists $resource->{bnumbers} ) {
        $resource->{bnumbers} = [];
    }
    if (ref $resource->{bnumbers} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'bnumbers'. Must be an array.");
        return;
    }

    return 1; # all good
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

    return unless $self->check_resource($c, $item, $old_resource, $resource, $form);
    # no checks, they are in check_resource, disadvantage: subscriber is searched twice
    my $b_subscriber = $schema->resultset('voip_subscribers')->find($resource->{subscriber_id});
    my $subscriber = $b_subscriber->provisioning_voip_subscriber;

    try {
        $item->update({
                name => $resource->{name},
                mode => $resource->{mode},
                (defined $resource->{is_regex} ? (is_regex => $resource->{is_regex}) : ()),
                subscriber_id => $subscriber->id,
            })->discard_changes;
        $item->voip_cf_bnumbers->delete;
        for my $s ( @{$resource->{bnumbers}} ) {
            $item->create_related("voip_cf_bnumbers", {
                    bnumber => $s->{bnumber},
                });
        }
        $item->discard_changes;
        die unless $self->add_update_journal_item_hal($c,sub {
            my ($self, $c) = @_;
            return $self->hal_from_item($c, $item);
        });
    } catch($e) {
        $c->log->error("failed to create cfbnumberset: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cfbnumberset.");
        return;
    };

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
