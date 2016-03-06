package NGCP::Panel::Model::InterceptDB;

use strict;
use File::ShareDir 'dist_file';
use Moose;
use MooseX::Types::Moose;
extends 'Catalyst::Model::DBIC::Schema';

use Module::Runtime qw(use_module);

has 'testing' => (is => 'rw', isa => 'Bool', default => 0);

sub setup {
    my ($self) = @_;
    if ($self->testing) {
        my $config_location = dist_file('NGCP-Schema', 'test.conf');
        use_module('NGCP::Schema::Config')->instance
            ->config_file($config_location);
    }
}

__PACKAGE__->config(
    connect_info => [],
    schema_class => 'NGCP::InterceptSchema',
);

sub set_transaction_isolation {
    my ($self,$level) = @_;
    return $self->storage->dbh_do(
        sub {
          my ($storage, $dbh, @args) = @_;
          $dbh->do("SET TRANSACTION ISOLATION LEVEL " . $args[0]);
        },
        $level,
    );
}

1;
