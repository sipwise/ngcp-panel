package NGCP::Panel::Role::API::CallForwards;
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
use NGCP::Panel::Form::CFSimpleAPI;
use NGCP::Panel::Utils::Subscriber;

sub get_form {
    my ($self, $c, $type) = @_;

    return NGCP::Panel::Form::CFSimpleAPI->new(ctx => $c);
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;
    my $rwr_form = $self->get_form($c, "rules");
    
    my %resource = (subscriber_id => $item->subscriber_id);

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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%s", $self->dispatch_path, $item->subscriber_id)),
            Data::HAL::Link->new(relation => "ngcp:$type", href => sprintf("/api/%s/%s", $type, $item->subscriber_id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->subscriber->voip_subscriber->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );
    
    for my $cf_type (qw/cfu cfb cft cfna/) {
        my $mapping = $c->model('DB')->resultset('voip_cf_mappings')->search({
                subscriber_id => $item->subscriber_id,
                type => $cf_type,
            })->first;
        if ($mapping) {
            $resource{$cf_type} = $self->_contents_from_cfm($c, $mapping);
        } else {
            $resource{$cf_type} = {};
        }
    }

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

sub item_rs {
    my ($self, $c, $type) = @_;
    my $item_rs;

    if($type eq "callforwards") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('voip_cf_mappings')
                ->search_rs(undef,{ 
                    columns => ['subscriber_id'],
                    group_by => ['subscriber_id']});
        } else {
            return;
        }
    } else {
        die "You should not reach this";
    }
    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id, $type) = @_;

    my $item_rs = $self->item_rs($c, $type);
    return $item_rs->search_rs({subscriber_id => $id})->first;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};

    if ($resource->{rewriterules}) {
        $item->voip_rewrite_rules->delete;
        my $i = 30;
        for my $rule (@{ $resource->{rewriterules} }) {
            $item->voip_rewrite_rules->create({
                %{ $rule },
                priority => $i++,
            });
        }
    }

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );
    #TODO: priority not accessible here
    $item->update($resource);

    return $item;
}

sub _contents_from_cfm {
    my ($self, $c, $cfm_item) = @_;
    my (@times, @destinations);
    my $timeset_item = $cfm_item->time_set;
    my $dset_item = $cfm_item->destination_set;
    for my $time ($timeset_item ? $timeset_item->voip_cf_periods->all : () ) {
        push @times, {$time->get_inflated_columns};
    }
    for my $dest ($dset_item ? $dset_item->voip_cf_destinations->all : () ) {
        my ($d, $duri) = NGCP::Panel::Utils::Subscriber::destination_to_field($dest->destination);
        $d = $duri if $d eq "uri";
        push @destinations, {$dest->get_inflated_columns,
                destination => $d,
            };
    }
    return {times => \@times, destinations => \@destinations};
}

1;
# vim: set tabstop=4 expandtab:
