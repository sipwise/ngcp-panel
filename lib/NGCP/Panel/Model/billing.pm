package NGCP::Panel::Model::billing;
use Sipwise::Base;
use Module::Runtime qw(use_module);

extends 'Catalyst::Model::DBIC::Schema';

__PACKAGE__->config(
    connect_info =>
        use_module(NGCP::Panel->config->{'Model::billing'}{schema_class})->config->as_hash->{billingdb}
);
