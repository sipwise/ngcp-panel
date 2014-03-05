package NGCP::Panel::Model::DB::Base;
use base 'Catalyst::Model::Adaptor';
use NGCP::Panel::Model::DB;
use Moose;

__PACKAGE__->config( 
    class => __PACKAGE__ ,
    args  => {},
);

has 'schema' => (
    is  => 'rw',
    isa => 'NGCP::Panel::Model::DB',
);
1;