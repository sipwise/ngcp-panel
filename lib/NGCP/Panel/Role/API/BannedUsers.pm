package NGCP::Panel::Role::API::BannedUsers;
use Moose::Role;
with 'NGCP::Panel::Role::API';

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use Test::More;

sub item_name {
    return 'bannedusers';
}

sub get_item_id{
    my($self, $c, $item, $resource, $form) = @_;
    return $item->{username};
}

sub item_by_id{
    my ($self, $c, $id) = @_;
    return $id;
}

sub get_form{
    my($self, $c) = @_;
    return ();
}

sub resource_from_item{
    my($self, $c, $item) = @_;
    my $res;
    if('HASH' eq ref $item){
        $res = $item;
    }else{
        $res = { $item->get_inflated_columns };
    }
    return $res;
}
sub process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    return $resource;
}
sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;
    return [];
}
sub hal_from_item {
    my ($self, $c, $item, $form, $params) = @_;
    my ($form_exceptions) = @$params{qw/form_exceptions/};
    my $resource = $self->resource_from_item($c, $item, $form);

    $resource = $self->process_hal_resource($c, $item, $resource, $form);
    my $links = $self->hal_links($c, $item, $resource, $form) // [];
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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%s", $self->dispatch_path, $self->get_item_id($c, $item))),
            @$links
        ],
        relation => 'ngcp:'.$self->resource_name,
    );
    if(!$form){
        ($form,$form_exceptions) = $self->get_form($c);
    }
    if($form){
        $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            run => 0,
        );
    }
    $resource->{id} = $self->get_item_id($c, $item);
    $hal->resource({%$resource});
    return $hal;
}

1;
# vim: set tabstop=4 expandtab:
