package NGCP::Panel::Role::API::BillingProfiles;
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
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Reseller qw();
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Form::BillingProfile::Admin qw();
use NGCP::Panel::Utils::Billing qw();

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('billing_profiles');
    my $search_xtra = {
            '+select' => [ { '' => \[ NGCP::Panel::Utils::Billing::get_contract_count_stmt() ] , -as => 'contract_cnt' },
                           { '' => \[ NGCP::Panel::Utils::Billing::get_package_count_stmt() ] , -as => 'package_cnt' }, ],
            };
    if($c->user->roles eq "admin") {
        $item_rs = $item_rs->search({ 'me.status' => { '!=' => 'terminated' } },
                                    $search_xtra);
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ reseller_id => $c->user->reseller_id,
                                      'me.status' => { '!=' => 'terminated' } },
                                      $search_xtra);
    } else {
        $item_rs = $item_rs->search({ reseller_id => $c->user->contract->contact->reseller_id,
                                      'me.status' => { '!=' => 'terminated' } },
                                      $search_xtra);
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::BillingProfile::Admin->new;
}

sub hal_from_profile {
    my ($self, $c, $profile, $form) = @_;

    my %resource = $profile->get_inflated_columns;

    # TODO: we should return the fees in an embedded field,
    # if the structure is returned for one single item
    # (make it a method flag)

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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $profile->id)),
            Data::HAL::Link->new(relation => 'ngcp:billingfees', href => sprintf("/api/billingfees/?billing_profile_id=%d", $profile->id ) ),
            Data::HAL::Link->new(relation => 'ngcp:billingzones', href => sprintf("/api/billingzones/?billing_profile_id=%d", $profile->id )),
            $self->get_journal_relation_link($profile->id),
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

    $resource{id} = int($profile->id);
    $hal->resource({%resource});
    return $hal;
}

sub profile_by_id {
    my ($self, $c, $id) = @_;

    my $profiles = $self->item_rs($c);
    return $profiles->find($id);
}

sub update_profile {
    my ($self, $c, $profile, $old_resource, $resource, $form) = @_;

    if ($profile->status eq 'terminated') {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'Billing profile is already terminated and cannot be changed.');
        return;
    }

    $form //= $self->get_form($c);
    # TODO: for some reason, formhandler lets missing reseller slip thru
    $resource->{reseller_id} //= undef;
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    return unless NGCP::Panel::Utils::Reseller::check_reseller_update_item($c,$resource->{reseller_id},$old_resource->{reseller_id},sub {
        my ($err) = @_;
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
    });

    #if(exists $resource->{status} && $resource->{status} eq 'terminated') {
        unless($profile->get_column('contract_cnt') == 0) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                         "Cannnot modify or terminate billing_profile that is still used in profile mappings of contracts");
            return;
        }
        unless($profile->get_column('package_cnt') == 0) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                         "Cannnot modify or terminate billing_profile that is still used in profile sets of profile packages");
            return;
        }
    #}

    my $old_prepaid = $profile->prepaid;
    $profile->update($resource);

    # if prepaid flag changed, update all subscribers for customers
    # who currently have the billing profile active
    my $rs = $c->model('DB')->resultset('billing_mappings')->search({
        billing_profile_id => $profile->id,
    });
    my $contract_rs = NGCP::Panel::Utils::Contract::get_contract_rs(
schema => $c->model('DB'));
    if($old_prepaid && !$profile->prepaid) {
        foreach my $map($rs->all) {
            my $contract = $map->contract;
            next unless($contract->contact->reseller_id); # skip non-customers
            my $chosen_contract = $contract_rs->find({id => $contract->id});
            next unless( defined $chosen_contract && $chosen_contract->get_column('billing_mapping_id') == $map->id ); # is not current mapping
            foreach my $sub($contract->voip_subscribers->all) {
                my $prov_sub = $sub->provisioning_voip_subscriber;
                next unless($sub->provisioning_voip_subscriber);
                my $pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, attribute => 'prepaid', prov_subscriber => $prov_sub);
                if($pref->first) {
                    $pref->first->delete;
                }
            }
        }
    } elsif(!$old_prepaid && $profile->prepaid) {
        foreach my $map($rs->all) {
            my $contract = $map->contract;
            next unless($contract->contact->reseller_id); # skip non-customers
            my $chosen_contract = $contract_rs->find({id => $contract->id});
            next unless( defined $chosen_contract && $chosen_contract->get_column('billing_mapping_id') == $map->id ); # is not current mapping
            foreach my $sub($contract->voip_subscribers->all) {
                my $prov_sub = $sub->provisioning_voip_subscriber;
                next unless($prov_sub);
                my $pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, attribute => 'prepaid', prov_subscriber => $prov_sub);
                if($pref->first) {
                    $pref->first->update({ value => 1 });
                } else {
                    $pref->create({ value => 1 });
                }
            }
        }
    }

    return $profile;
}

1;
# vim: set tabstop=4 expandtab:
