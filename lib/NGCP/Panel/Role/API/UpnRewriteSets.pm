package NGCP::Panel::Role::API::UpnRewriteSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('upn_rewrite_set')
        ->search_rs({
            'voip_subscriber.id' => { '!=' => undef },
            'voip_subscriber.status' => { '!=' => 'terminated' },
        }, {
            join => { subscriber => 'voip_subscriber' },
            prefetch => 'upn_rewrite_sources'
        });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id
        },{
            join =>{ subscriber => { voip_subscriber => { contract => 'contact' } } },
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::UpnRewriteSet", $c);
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

    $form //= $self->get_form($c);
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
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->subscriber->voip_subscriber->id)),
            $self->get_journal_relation_link($c, $item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
    );

    $resource->{id} = int($item->id);

    $self->expand_fields($c, $resource);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my $resource = { $item->get_inflated_columns };
    $resource->{upn_rewrite_sources} = [ map { { pattern => $_->pattern }; } $item->upn_rewrite_sources->all ];
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
    );

    my $sub_rs = $c->model('DB')->resultset('voip_subscribers')->search({
        'me.id' => $resource->{subscriber_id},
    });
    if($c->user->roles eq "reseller") {
        $sub_rs = $sub_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => { contract => 'contact' },
        });
    }
    my $sub = $sub_rs->first;
    unless($sub && $sub->provisioning_voip_subscriber) {
        my $debug_sid = $resource->{subscriber_id} // '(undef)';
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber does not exist",
                     "invalid subscriber_id '$debug_sid'");
        return;
    }
    $resource->{subscriber_id} = $sub->provisioning_voip_subscriber->id;

    unless($resource->{subscriber_id} == $item->subscriber_id) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "subscriber_id cannot be changed",
                     "cannot edit subscriber_id '$$resource{subscriber_id}'");
        return;
    }

    if ($item->new_cli ne $resource->{new_cli}) {
        $item->update({ new_cli => $resource->{new_cli}});
    }
    $item->upn_rewrite_sources->delete_all;
    for my $s (@{ $resource->{upn_rewrite_sources} }) {
        $item->upn_rewrite_sources->create({
                pattern => $s->{pattern},
            });
    }
    $item->discard_changes;

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
