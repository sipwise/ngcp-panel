package NGCP::Panel::Model::provisioning;
use Sipwise::Base;
use Module::Runtime qw(use_module);

extends 'Catalyst::Model::DBIC::Schema';

my $connect_info = use_module(NGCP::Panel->config->{'Model::provisioning'}{schema_class})->config->as_hash->{provisioningdb};
$connect_info->{mysql_enable_utf8} = 1;

__PACKAGE__->config(
    connect_info => $connect_info,
);
