package NGCP::Panel::Controller::API::BannedUsers;


use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::BannedUsers/;


use NGCP::Panel::Utils::Peering;
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Security;

__PACKAGE__->set_config();

sub allowed_methods {
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Defines banned users.';
}

sub get_list{
    my ($self, $c) = @_;
    return NGCP::Panel::Utils::Security::list_banned_users($c);
}

sub order_by_cols {
    my ($self, $c) = @_;
    my $cols = {
        'auth_count' => 'auth_count',
        'last_auth'  => 'last_auth',
        'id'         => 'id',
        'username'   => 'username',
    };
    return $cols;
}
1;

# vim: set tabstop=4 expandtab:
