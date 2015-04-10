package NGCP::Panel::Utils::Reseller;
use strict;
use warnings;

use Sipwise::Base;

sub create_email_templates{
    my %params = @_;
    my($c, $reseller) = @params{qw/c reseller/};
    
    foreach ( $c->model('DB')->resultset('email_templates')->search_rs({ 'reseller_id' => undef })->all){
        my $email_template =  { $_->get_inflated_columns };
        delete $email_template->{id};
        $email_template->{reseller_id} = $reseller->id;
        $c->model('DB')->resultset('email_templates')->create($email_template);
    }
}
1;

=head1 NAME

NGCP::Panel::Utils::Reseller

=head1 DESCRIPTION

A temporary helper to manipulate resellers data

=head1 METHODS

=head2 create_email_templates

Apply default email templates to newly created reseller

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
