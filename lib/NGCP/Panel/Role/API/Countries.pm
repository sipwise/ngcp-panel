package NGCP::Panel::Role::API::Countries;

use Sipwise::Base;


use parent qw/NGCP::Panel::Role::API/;

use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Contact;

sub item_name {
    return 'country';
}

sub resource_name{
    return 'countries';
}

sub get_item_id{
    my($self, $c, $item, $resource, $form) = @_;
    return $item->{id};
}

sub valid_id {
    my ($self, $c, $id) = @_;
    return 1 if $id =~ /^[A-Za-z]{2}$/;
    $self->error($c, HTTP_BAD_REQUEST, "Invalid id in request URI. Should be a two-letter ISO 3166-1 country code.");
    return;
}

sub item_by_id{
    my ($self, $c, $id) = @_;
    my $list = NGCP::Panel::Utils::Contact::list_countries($c, id => $id);
    return ref $list eq 'ARRAY' ? $list->[0] : undef;
}

1;
# vim: set tabstop=4 expandtab:
