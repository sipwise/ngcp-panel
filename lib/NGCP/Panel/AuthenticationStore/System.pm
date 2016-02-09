package NGCP::Panel::AuthenticationStore::System;
use Sipwise::Base;
use Moose;
use namespace::autoclean;
use NGCP::Panel::AuthenticationStore::SystemRole;

with 'MooseX::Emulate::Class::Accessor::Fast';
use Scalar::Util qw( blessed );

__PACKAGE__->mk_accessors(qw/acl user_class/);

sub new {
    my ( $class, $config, $app) = @_;

    my $group = $config->{group}
                    or die $class.": group is undefined in the config";
    my $file = delete $config->{file}
                    or die $class.": file is not specified in the config";
    open(my $fh, "<", $file)
        or die $class.": cannot read $file: $!";

    my %data;
    while (<$fh>) {
        chomp $_;
        next unless $_ =~ /^${group}_(\w+)=(\S+)$/i;
        my ($key,$val) = (lc($1),$2);
        foreach my $t (qw(login password roles)) {
            $key eq $t and $data{$key} = $val;
        }
    }
    close $fh;

    unless ($data{login} && $data{password} && $data{roles}) {
        die $class.": undefined $group login/password/roles parameter";
    }

    my $self = bless {
                    acl => { $data{login} =>
                                {
                                    login    => $data{login},
                                    password => $data{password},
                                    roles    => $data{roles},
                                } },
                    user_class => $config->{user_class} ||
                        "NGCP::Panel::AuthenticationStore::SystemRole",
               }, $class;

    return $self;
}

sub find_user {
    my ( $self, $authinfo, $c ) = @_;

    my $user = $authinfo->{stored} ||
                $self->acl->{$authinfo->{login}} || return;
    my $username = $user->{login} || return;

    return unless exists $self->acl->{$username};

    if (ref($user) eq "HASH") {
        return $self->user_class->new($user);
    } elsif (ref($user) && blessed($user) &&
                $user->isa('NGCP::Panel::AuthenticationStore::SystemRole')) {
        return $user;
    } else {
        Catalyst::Exception->throw(
            "The user '$username' must be a hash reference or an " .
            "object of class NGCP::Panel::AuthenticationStore::SystemRole");
    }

    return;
}

sub from_session {
    my ( $self, $c, $stored ) = @_;

    return $self->find_user( { stored => $stored } );
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;

# vim ts=4 sw=4 et
