package NGCP::Panel::Role::API::ProfilePackages;
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

    my @profile_links = ();
    my @network_links = ();
    foreach my $mapping ($item->profiles->all) {
        push(@profile_links,Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $mapping->profile_id)));
        if ($mapping->network_id) {
            push(@profile_links,Data::HAL::Link->new(relation => 'ngcp:billingnetworks', href => sprintf("/api/billingnetworks/%d", $mapping->network_id)));
        }
    }
    
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

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('profile_packages')->search_rs({ 'me.status' => { '!=' => 'terminated' } });
    my $search_xtra = {
            '+select' => [ { '' => \[ NGCP::Panel::Utils::ProfilePackages::get_contract_count_stmt() ] , -as => 'contract_cnt' },
                           #{ '' => \[ NGCP::Panel::Utils::ProfilePackages::get_package_count_stmt() ] , -as => 'package_cnt' },
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

    if ($item->status eq 'terminated') {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'Profile package is already terminated and cannot be changed.');
        return;
    }
    
    delete $resource->{id};
    my $schema = $c->model('DB');
    
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
    
    if(exists $resource->{status} && $resource->{status} eq 'terminated') {
        unless($item->get_column('contract_cnt') == 0) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                         "Cannnot terminate profile_package that is still assigned to contracts");
            return;
        }
        #unless($item->get_column('contract_cnt') == 0) {
        #    $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
        #                 "Cannnot terminate billing_network that is still used in profile sets of profile packages");
        #    return;
        #}        
    }
    
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
