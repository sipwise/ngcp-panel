package NGCP::Panel::Utils::RedisLocationResultSource;

use Moo;

our $AUTOLOAD;

has _data => (
    is => 'ro',
    isa => sub { die "$_[0] must be HASHREF" unless $_[0] && ref $_[0] eq 'HASH' },
    default => sub {{}},
);

sub AUTOLOAD {
    my $self = shift;
    my $col = $AUTOLOAD;
    $col = (split '::', $col)[-1];
    return $self->_data->{$col};
}

sub get_inflated_columns {
    my ($self) = @_;
    return %{ $self->_data };
}

sub columns { }

1;
