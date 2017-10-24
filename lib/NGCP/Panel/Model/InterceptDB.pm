package NGCP::Panel::Model::InterceptDB;

use strict;
use warnings;

use base 'Catalyst::Model::DBIC::Schema';

__PACKAGE__->config(
    connect_info => [],
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
