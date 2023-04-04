package NGCP::Panel::Role::API::BillingProfiles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Reseller qw();
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::Billing qw();

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('billing_profiles');
    my $search_xtra = {
            '+select' => [ { '' => \[ NGCP::Panel::Utils::Billing::get_contract_count_stmt(1000) ] , -as => 'contract_cnt' },
                           { '' => \[ NGCP::Panel::Utils::Billing::get_contract_exists_stmt() ] , -as => 'contract_exists' },
                           { '' => \[ NGCP::Panel::Utils::Billing::get_package_count_stmt() ] , -as => 'package_cnt' }, ],
            };
    if($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
        $item_rs = $item_rs->search({
            'me.status' => { '!=' => 'terminated' },
        }, $search_xtra);
    } elsif($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $item_rs = $item_rs->search({
            reseller_id => $c->user->reseller_id,
            'me.status' => { '!=' => 'terminated' },
        }, $search_xtra);
    } else {
        $item_rs = $item_rs->search({
            reseller_id => $c->user->contract->contact->reseller_id,
            'me.status' => { '!=' => 'terminated' },
        }, $search_xtra);
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::BillingProfile::PeaktimeAPI", $c);
}

sub resource_from_item {
    my ($self, $c, $profile, $form) = @_;

    my %resource = $profile->get_inflated_columns;

    my $weekday_peaktimes = NGCP::Panel::Utils::Billing::resource_from_peaktime_weekdays($profile);
    my $special_peaktimes = NGCP::Panel::Utils::Billing::resource_from_peaktime_specials($profile);

    # TODO: we should return the fees in an embedded field,
    # if the structure is returned for one single item
    # (make it a method flag)

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    $resource{id} = int($profile->id);
    $resource{peaktime_weekdays} = $weekday_peaktimes;
    $resource{peaktime_special} = $special_peaktimes;

    return \%resource;
}

sub hal_from_item {
    my ($self, $c, $item, $resource, $form) = @_;

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf('/api/%s/', $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:billingfees', href => sprintf("/api/billingfees/?billing_profile_id=%d", $item->id ) ),
            Data::HAL::Link->new(relation => 'ngcp:billingzones', href => sprintf("/api/billingzones/?billing_profile_id=%d", $item->id )),
            $self->get_journal_relation_link($c, $item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $self->expand_fields($c, $resource);
    $hal->resource($resource);
    return $hal;
}

sub profile_by_id {
    my ($self, $c, $id) = @_;

    my $profiles = $self->item_rs($c);
    return $profiles->find($id);
}

sub lock_profile {
    my ($self,$c,$profile_id) = @_;
    return $c->model('DB')->resultset('billing_profiles')->find({
                id => $profile_id
                },{for => 'update'});
}

sub update_profile {
    my ($self, $c, $profile, $old_resource, $resource, $form) = @_;

    #if ($profile->status eq 'terminated') {
    #    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'Billing profile is already terminated and cannot be changed.');
    #    return;
    #}

    $form //= $self->get_form($c);
    if ($c->user->roles eq "reseller") {
        $resource->{reseller_id} = $c->user->reseller_id;
    } else {
        # TODO: for some reason, formhandler lets missing reseller slip thru
        $resource->{reseller_id} //= undef;
    }
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    return unless NGCP::Panel::Utils::Reseller::check_reseller_update_item($c,$resource->{reseller_id},$old_resource->{reseller_id},sub {
        my ($err) = @_;
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
    });

    return unless NGCP::Panel::Utils::Billing::check_profile_update_item($c,$resource,$profile,sub {
        my ($err) = @_;
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
    });

    my $weekday_peaktimes_to_create = [];
    return unless NGCP::Panel::Utils::Billing::prepare_peaktime_weekdays(c => $c,
        resource => $resource,
        peaktimes_to_create => $weekday_peaktimes_to_create,
        err_code => sub {
            my ($err) = @_;
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
        }
    );

    my $special_peaktimes_to_create = [];
    return unless NGCP::Panel::Utils::Billing::prepare_peaktime_specials(c => $c,
        resource => $resource,
        peaktimes_to_create => $special_peaktimes_to_create,
        err_code => sub {
            my ($err) = @_;
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
        }
    );

    my $old_prepaid = $profile->prepaid;

    try {
        $profile = $self->lock_profile($c,$profile->id);
        $profile->update($resource);
        $profile->billing_peaktime_weekdays->delete;
        foreach my $weekday_peaktime (@$weekday_peaktimes_to_create) {
            $profile->billing_peaktime_weekdays->create($weekday_peaktime);
        }
        $profile->billing_peaktime_specials->delete;
        foreach my $special_peaktime (@$special_peaktimes_to_create) {
            $profile->billing_peaktime_specials->create($special_peaktime);
        }
        NGCP::Panel::Utils::Billing::switch_prepaid(c => $c,
            profile_id => $profile->id,
            old_prepaid => $old_prepaid,
            new_prepaid => $profile->prepaid,
        );
    } catch($e) {
        $c->log->error("Failed to update billing profile '".$profile->id."': $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
        return;
    };

    return $profile;
}

1;
# vim: set tabstop=4 expandtab:
