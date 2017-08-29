package NGCP::Panel::Role::API::Numbers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';
use NGCP::Panel::Form;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Prosody;

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Number::AdminAPI", $c);
    } elsif($c->user->roles eq "reseller") {
        #return NGCP::Panel::Form::get("NGCP::Panel::Form::Number::ResellerAPI", $c);
        # there is currently no difference in the form
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Number::SubadminAPI", $c);
    } elsif($c->user->roles eq "subscriberadmin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Number::SubadminAPI", $c);
    }
    return;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my %resource = $item->get_inflated_columns;

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
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->subscriber_id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
        exceptions => [ qw/subscriber_id/ ],
    );

    $resource{id} = int($item->id);
    if($c->user->roles eq "admin") {
        $resource{reseller_id} = int($item->reseller_id);
    }

    $hal->resource({%resource});
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_numbers')->search({
        'me.reseller_id' => { '!=' => undef },
        'me.subscriber_id' => { '!=' => undef },

    },{
        '+select' => [\'if(me.id=subscriber.primary_number_id,1,0)'],
        '+as' => ['is_primary'],
        join => 'subscriber'
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'me.reseller_id' => $c->user->reseller_id,
        });
    } elsif($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search({
            'subscriber.contract_id' => $c->user->account_id,
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

    foreach my $field(qw/cc ac sn is_primary/) {
        unless($old_resource->{$field} eq $resource->{$field}) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Field '$field' is not allowed to be updated via this API endpoint, use /api/subscriber/\$id instead.");
            return;
        }
    }

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        exceptions => [ qw/subscriber_id is_primary/ ],
    );

    my $sub = $c->model('DB')->resultset('voip_subscribers')
        ->find($resource->{subscriber_id});
    unless($sub) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id', does not exist.");
        return;
    }
    if($c->user->roles eq "subscriberadmin" && $sub->contract_id != $c->user->account_id) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id', does not exist.");
        return;
    }
    my $old_sub = $c->model('DB')->resultset('voip_subscribers')->find($old_resource->{subscriber_id});
    if($old_sub->primary_number_id == $old_resource->{id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Cannot reassign primary number, already at subscriber ".$old_sub->id);
        return;
    }

    my $num = $$old_resource{cc} . ($$old_resource{ac} // "") . $$old_resource{sn};
    my $dbalias = $old_sub->provisioning_voip_subscriber->voip_dbaliases->find({
        username => "$$old_resource{cc}$$old_resource{ac}$$old_resource{sn}"
    });
    unless($dbalias) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Failed to find dbalias entry");
        return;
    } 
    $item->update({ subscriber_id => $resource->{subscriber_id} });
    $dbalias->update({
        subscriber_id => $sub->provisioning_voip_subscriber->id
    });

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
