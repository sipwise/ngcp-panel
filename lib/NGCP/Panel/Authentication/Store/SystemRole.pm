package NGCP::Panel::Authentication::Store::SystemRole;
use Sipwise::Base;
use parent 'Catalyst::Authentication::User::Hash';

sub roles  {
    my $self = shift;

    # return only first role for now
    return ref($self->{roles}) eq "ARRAY" ? $self->{roles}[0]
                                          : $self->{roles};
}

sub id               { 0 };
sub is_system        { 1 };
sub is_master        { 1 };
sub is_superuser     { 1 };
sub is_ccare         { 0 };
sub is_readonly      { 0 };
sub show_passwords   { 1 };
sub call_data        { 1 };
sub billing_data     { 1 };
sub lawful_intercept { 0 };

1;

# vim ts=4 sw=4 et
