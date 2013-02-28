package NGCP::Panel::Widget;
use Moose;
with 'MooseX::Object::Pluggable';

use Data::Dumper;

sub handle {
    my ($self, $c) = @_;
    return;
}

sub filter {
    my ($self, $c) = @_;
    return;
}

sub instantiate_plugins {
    my ($self, $c) = @_;
    my @plugins = map { s/^.*:://; $_; } $self->_plugin_locator->plugins;

    my @instances = ();
    foreach(@plugins) {
        my $inst = NGCP::Panel::Widget->new;
        $inst->load_plugin($_);
        if($inst->filter($c)) {
            push @instances, $inst;
        }
    }
    return @instances;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
# vim: set tabstop=4 expandtab:
