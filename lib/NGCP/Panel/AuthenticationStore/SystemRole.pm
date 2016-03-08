package NGCP::Panel::AuthenticationStore::SystemRole;
use Sipwise::Base;
use parent 'Catalyst::Authentication::User::Hash';

sub roles  {
    my $self = shift;

    # return only first role for now
    return ref($self->{roles}) eq "ARRAY" ? $self->{roles}[0]
                                          : $self->{roles};
}

1;

# vim ts=4 sw=4 et
