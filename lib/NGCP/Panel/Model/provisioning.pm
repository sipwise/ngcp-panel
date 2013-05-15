package NGCP::Panel::Model::provisioning;
use Sipwise::Base;
use Module::Runtime qw(use_module);

extends 'Catalyst::Model::DBIC::Schema';

__PACKAGE__->config(
    connect_info =>
        use_module(NGCP::Panel->config->{'Model::provisioning'}{schema_class})->config->as_hash->{provisioningdb}
);
