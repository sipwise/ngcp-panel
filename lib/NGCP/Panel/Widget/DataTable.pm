package NGCP::Panel::Widget::DataTable;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/data_table.tt'
);

#around handle => sub {
#    my ($foo, $self, $c) = @_;
#
#    print "++++ AdminBillingOverview::handle\n";
#    return;
#};

#around filter => sub {
#    my ($foo, $self, $c) = @_;

#    return $self if(
#        $c->check_user_roles(qw/administrator/) &&
#        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
#    );
#    return;
#};

1;
# vim: set tabstop=4 expandtab:
