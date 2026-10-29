package NGCP::Panel::Controller::API::Countries;


use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Countries/;

use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Contact;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare/],
});

sub allowed_methods {
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Lists the countries (ISO 3166-1 alpha-2 code and name) that can be used for contacts.';
}

sub query_params {
    return [
        {
            param => 'name',
            description => 'Filter for countries with a name containing the given string (case-insensitive)',
        },
        {
            param => 'q',
            description => 'Filter for countries with a code or name containing the given string (case-insensitive)',
        },
    ];
}

sub get_list{
    my ($self, $c) = @_;
    my $params = $c->request->query_params;
    return NGCP::Panel::Utils::Contact::list_countries($c,
        map { $_ => $params->{$_} } grep { defined $params->{$_} } qw/id name q/
    );
}

sub order_by_cols {
    my ($self, $c) = @_;
    my $cols = {
        'id'   => 'id',
        'name' => 'name',
    };
    return $cols;
}
1;

# vim: set tabstop=4 expandtab:
