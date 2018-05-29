package NGCP::Panel::Model::Storage;
use Sipwise::Base;
use Moose;
use XML::Simple;
use NGCP::Schema;
use Data::Dumper;

use parent 'Catalyst::Component';

__PACKAGE__->config(
    connectors => [],
);

has connectors => (
    is => 'rw',
);

sub COMPONENT {
    my ($class, $app, $args) = @_;
    $args = $class->merge_config_hashes($class->config, $args);
    my $self = $class->new($app, $args);
    $self->connect_storage();
    return $self;
}

sub get_config_filename {
    return '/etc/ngcp-panel/provisioning.conf';
}

sub add_connector {
    my ($self, $conn) = @_;

    $self->connectors([@{$self->connectors // []},
                       NGCP::Schema->connect($conn)]);

    return;
}

sub connect_storage {
    my ($self, $c) = @_;

    unless (@{$self->config->{connectors}}) {
        my $conf = XML::Simple->new->XMLin(get_config_filename(), ForceArray => 1);
        if ($conf && $conf->{ngcp_storage_info}) {
            my $connectors = $conf->{ngcp_storage_info}->[0]->{connectors} // [];
            map { $self->add_connector($_); } @$connectors;
        }
    }

    return;
}

sub resultset {
    my ($self, $rs) = @_;

    return unless $self->connectors->[0];

    # TODO: only one is used now, support multiple storages at once
    return $self->connectors->[0]->resultset($rs);
}

1;

# vim: set tabstop=4 expandtab
