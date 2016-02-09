package NGCP::Panel::AuthenticationStore::System;
use Sipwise::Base;
use YAML::Tiny;
use Moose;
use namespace::autoclean;
use NGCP::Panel::AuthenticationStore::SystemRole;

with 'MooseX::Emulate::Class::Accessor::Fast';
use Scalar::Util qw( blessed );

__PACKAGE__->mk_accessors(qw/acl user_class/);

sub new {
    my ( $class, $config, $app) = @_;

    die $class." undefined section parameter"
        unless $config->{section};

    my $file = delete $config->{file}
                or die $class.": file is not specified in the config";
    my $yaml = YAML::Tiny->read($file)
                or die $class.": cannot read $file: $!";

    my $ref;
    foreach my $section (split /:/, $config->{section}) {
        $ref = ref $ref ? $ref->{$section} : $yaml->[0]{$section};
        die $class.": malformed config data, check your config file"
            unless $ref && ref $ref;
    }
    my $self = bless {
                    acl        => { $ref->{login} => { %$ref } },
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
