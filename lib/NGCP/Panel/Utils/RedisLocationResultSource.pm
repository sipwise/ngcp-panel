package NGCP::Panel::Utils::RedisLocationResultSource;

use Moose;

has _data => (
    is => 'ro',
    isa => 'HashRef',
    default => sub {{}},
);

sub BUILD {
    my ($self) = @_;
    foreach my $k (keys %{ $self->_data }) {
        $self->meta->add_attribute(
            $k => (accessor => $k)
        );
        $self->$k($self->_data->{$k});
    }
}

sub get_inflated_columns {
    my ($self) = @_;
    return %{ $self->_data };
}

sub columns {
    
}

sub has_column {
    my ($self, $column) = @_;
    return 1;
    return exists $self->_data->{$column};
}


1;
