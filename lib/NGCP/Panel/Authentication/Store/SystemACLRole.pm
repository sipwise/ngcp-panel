package NGCP::Panel::Authentication::Store::SystemACLRole;
use Sipwise::Base;

my $instance;

sub new {
    my $class = shift;
    $instance ||= bless {}, $class;
}

sub id {-1};
sub role {'system'};

1;