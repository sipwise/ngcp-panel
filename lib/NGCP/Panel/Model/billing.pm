package NGCP::Panel::Model::billing;

use strict;
use base 'Catalyst::Model::DBIC::Schema';

__PACKAGE__->config(
    schema_class => 'NGCP::Schema::billing',
    
    connect_info => {
        dsn => 'dbi:mysql:dbname=billing',
        user => 'root',
    }
);
