package NGCP::Panel::Role::API::NcosLevels;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::NCOS;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('ncos_levels');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ reseller_id => $c->user->reseller_id });
    } elsif($c->user->roles eq "subscriberadmin") {
        my $contract = $c->model('DB')->resultset('contracts')->find($c->user->account_id);
        $item_rs = $item_rs->search({
            reseller_id => $contract->contact->reseller_id,
            expose_to_customer => 1
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::NCOS::AdminLevelAPI", $c);
    } elsif($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::NCOS::ResellerLevelAPI", $c);
    } elsif($c->user->roles eq "subscriberadmin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::NCOS::SubAdminLevelAPI", $c);
    }
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my %resource = $item->get_inflated_columns;

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
            Data::HAL::Link->new(relation => 'ngcp:resellers', href => sprintf("/api/resellers/%d", $item->reseller_id)),
            Data::HAL::Link->new(relation => 'ngcp:ncospatterns', href => sprintf("/api/ncospatterns/?ncos_level_id=%d", $item->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
    );

    $resource{id} = int($item->id);

    $self->expand_fields($c, \%resource);
    $hal->resource({%resource});
    return $hal;
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
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $resource->{reseller_id} = $c->user->reseller_id;
    }

    if ($resource->{time_set_id}) {
        my $time_set = $c->model('DB')->resultset('voip_time_sets')->find({
            id => $resource->{time_set_id},
            reseller_id => $c->user->reseller_id
        });
        if (!$time_set) {
            my $err = "Time set with id '$resource->{time_set_id}' does not exist or does not belong to this reseller";
            $c->log->error($err);
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
            return;
        }
    }

    my $dup_item = $c->model('DB')->resultset('ncos_levels')->find({
        reseller_id => $resource->{reseller_id},
        level => $resource->{level},
    });
    if($dup_item && $dup_item->id != $item->id) {
        $c->log->error("ncos level '$$resource{level}' already exists for reseller_id '$$resource{reseller_id}'"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "NCOS level already exists for this reseller");
        return;
    }

    $item->update($resource);

    if ($old_resource->{expose_to_customer} && !$resource->{expose_to_customer}) {
        NGCP::Panel::Utils::NCOS::revoke_exposed_ncos_level($c, $item->id);
    }

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
