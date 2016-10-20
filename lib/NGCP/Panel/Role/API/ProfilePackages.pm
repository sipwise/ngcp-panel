package NGCP::Panel::Role::API::ProfilePackages;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::Reseller qw();
use NGCP::Panel::Form::ProfilePackage::PackageAPI;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::ProfilePackage::PackageAPI->new;
}

sub _get_profiles_mappings {
    my ($item,$field) = @_;
    my @mappings = ();
    for my $mapping ($item->$field()->all) {
        my %elem = $mapping->get_inflated_columns;
        delete $elem{id};
        delete $elem{package_id};
        delete $elem{discriminator};
        push @mappings, \%elem;
    }
    return \@mappings;
}   

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;

    my %resource = $item->get_inflated_columns;
    $resource{initial_profiles} = _get_profiles_mappings($item,'initial_profiles');
    $resource{topup_profiles} = _get_profiles_mappings($item,'topup_profiles');
    $resource{underrun_profiles} = _get_profiles_mappings($item,'underrun_profiles');
    
    #$resource{initial_balance} /= 100.0 if exists $resource{initial_balance} && defined $resource{initial_balance}; #prevent auto-vivivication..
    #$resource{service_charge} /= 100.0 if exists $resource{service_charge} && defined $resource{service_charge};
    #$resource{underrun_lock_threshold} /= 100.0 if exists $resource{underrun_lock_threshold} && defined $resource{underrun_lock_threshold};
    #$resource{underrun_profile_threshold} /= 100.0 if exists $resource{underrun_profile_threshold} && defined $resource{underrun_profile_threshold};

    my @profile_links = ();
    my @network_links = ();
    foreach my $mapping ($item->profiles->all) {
        push(@profile_links,NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $mapping->profile_id)));
        if ($mapping->network_id) {
            push(@profile_links,NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:billingnetworks', href => sprintf("/api/billingnetworks/%d", $mapping->network_id)));
        }
    }
    
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
            NGCP::Panel::Utils::DataHalLink->new(relation => "ngcp:$type", href => sprintf("/api/%s/%d", $type, $item->id)),
            @profile_links,
            @network_links,
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
        exceptions => [ "reseller_id" ],
    );
    $hal->resource(\%resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('profile_packages')->search_rs(); #{ 'me.status' => { '!=' => 'terminated' } });
    my $search_xtra = {
            '+select' => [ { '' => \[ NGCP::Panel::Utils::ProfilePackages::get_contract_count_stmt() ] , -as => 'contract_cnt' },
                           { '' => \[ NGCP::Panel::Utils::ProfilePackages::get_voucher_count_stmt() ] , -as => 'voucher_cnt' },
                           ],
            };       
    if($c->user->roles eq "admin") {
        $item_rs = $item_rs->search(undef,
                                    $search_xtra);         
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ 'me.reseller_id' => $c->user->reseller_id },
                                    $search_xtra);
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
    
    #$resource{initial_balance} *= 100.0 if exists $resource{initial_balance} && defined $resource{initial_balance}; #prevent auto-vivivication..
    #$resource{service_charge} *= 100.0 if exists $resource{service_charge} && defined $resource{service_charge};
    #$resource{underrun_lock_threshold} *= 100.0 if exists $resource{underrun_lock_threshold} && defined $resource{underrun_lock_threshold};
    #$resource{underrun_profile_threshold} *= 100.0 if exists $resource{underrun_profile_threshold} && defined $resource{underrun_profile_threshold};
    
    $form //= $self->get_form($c);
    ## TODO: for some reason, formhandler lets missing reseller slip thru
    $resource->{reseller_id} //= undef;
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        exceptions => [ "reseller_id" ],
    );
    
    return unless NGCP::Panel::Utils::Reseller::check_reseller_update_item($c,$resource->{reseller_id},$old_resource->{reseller_id},sub {
        my ($err) = @_;
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
    });
    
    return unless NGCP::Panel::Utils::ProfilePackages::check_package_update_item($c,$resource,$item,sub {
        my ($err) = @_;
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
    });
    
    my $mappings_to_create = [];
    return unless NGCP::Panel::Utils::ProfilePackages::prepare_profile_package(
            c => $c,
            resource => $resource,
            mappings_to_create => $mappings_to_create,
            err_code => sub {
                my ($err) = @_;
                #$c->log->error($err);
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
            });
    
    try {
        $item->update($resource);
        $item->profiles->delete;        
        foreach my $mapping (@$mappings_to_create) {
            $item->profiles->create($mapping); 
        }
        $item->discard_changes;
    } catch($e) {
        $c->log->error("failed to create profilepackage: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create profilepackage.");
        return;
    };
    
    return $item;
}

1;
# vim: set tabstop=4 expandtab:
