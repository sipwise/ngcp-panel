package NGCP::Panel::Widget;
use Moose;
with 'MooseX::Object::Pluggable';

sub handle {
    my ($self, $c) = @_;
    return;
}

sub list_plugins {
    my ($self) = @_;
    return map { $_ = s/^.*:://r } $self->_plugin_locator->plugins;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
# vim: set tabstop=4 expandtab:
