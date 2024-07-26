package NGCP::Panel::Utils::Admin;
use strict;
use warnings;

use Sipwise::Base;

use NGCP::Panel::Utils::Generic qw(:all);

use DBIx::Class::Exception;
use NGCP::Panel::Utils::Auth;

use HTTP::Status qw(:constants);

sub insert_password_journal {
    my ($c, $admin, $password) = @_;

    my $bcrypt_cost = 6;
    my $keep_last_used = $c->config->{security}{password}{web_keep_last_used} // return;

    my $rs = $admin->last_passwords->search({
    },{
        order_by => { '-desc' => 'created_at' },
    });

    my @delete_ids = ();
    my $idx = 0;
    foreach my $row ($rs->all) {
        $idx++;
        $idx >= $keep_last_used ? push @delete_ids, $row->id : next;
    }

    my $del_rs = $rs->search({
        id => { -in => \@delete_ids },
    });

    $del_rs->delete;

    $admin->last_passwords->create({
        admin_id => $admin->id,
        value => NGCP::Panel::Utils::Auth::generate_salted_hash($password, $bcrypt_cost),
    });
    $admin->update({ saltedpass_modify_timestamp => \'current_timestamp()' });
}

1;

=head1 NAME

NGCP::Panel::Utils::Admin

=head1 DESCRIPTION

A temporary helper to manipulate admin data

=head1 AUTHOR

Sipwise Development Team <support@sipwise.com>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
