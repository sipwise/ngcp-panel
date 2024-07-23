package NGCP::Panel::ActionRole::License;
use Moose::Role;
use namespace::autoclean;

sub BUILD { }

after BUILD => sub {
    my $class = shift;
    my ($args) = @_;

    my $attr = $args->{attributes};

    unless (exists $attr->{RequiresLicense} || exists $attr->{AllowedLicense}) {
        Catalyst::Exception->throw(
            "Action '$args->{reverse}' requires at least one RequiresLicense or AllowedLicense attribute");
    }
    unless (exists $attr->{LicenseDetachTo} && $attr->{LicenseDetachTo}) {
        Catalyst::Exception->throw(
            "Action '$args->{reverse}' requires the LicenseDetachTo(<action>) attribute");
    }

};

around execute => sub {
    my $orig = shift;
    my $self = shift;
    my ($controller, $c) = @_;

    if ($self->check_license($c)) {
        return $self->$orig(@_);
    }

    my $denied = $self->attributes->{ACLDetachTo}[0];

    $c->detach($denied);
};

sub check_license {
    my ($self, $c) = @_;

    my $required = $self->attributes->{RequiresLicense};
    my $allowed = $self->attributes->{AllowedLicense};

    if ($required && $allowed) {
        for my $license (@$required) {
            return unless $c->license($license);
        }
        for my $license (@$allowed) {
            return 1 if $c->license($license);
        }
        return;
    }
    elsif ($required) {
        for my $license (@$required) {
            return unless $c->license($license);
        }
        return 1;
    }
    elsif ($allowed) {
        for my $license (@$allowed) {
            return 1 if $c->license($license);
        }
        return;
    }

    return;
}

1;

__END__
=pod

=head1 NAME

NGCP::Panel::ActionRole::License

=head1 DESCRIPTION

A helper to check NGCP License info

=head1 AUTHOR

Sipwise Development Team <support@sipwise.com>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:

