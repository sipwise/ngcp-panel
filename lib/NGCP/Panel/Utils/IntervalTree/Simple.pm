package NGCP::Panel::Utils::IntervalTree::Simple;

#use 5.006;
#use POSIX qw(ceil); 
#use List::Util qw(max min);
use strict;
use warnings;
#no warnings 'once';

use NGCP::Panel::Utils::IntervalTree::Node;

#our $VERSION = '0.05';

sub new {
  my ($class) = @_;
  my $self = {};
  $self->{root} = undef;
  return bless $self, $class;
}
    
sub insert {
  my ($self, $start, $end, $value) = @_;
  if (!defined $self->{root}) {
    $self->{root} = NGCP::Panel::Utils::IntervalTree::Node->new($start, $end, $value);
  } else {
    $self->{root} = $self->{root}->insert($start, $end, $value);
  }
}

#*add = \&insert;

sub find {
  my ( $self, $start, $end ) = @_;
  if (!defined $self->{root}) {
    return [];
  }
  return $self->{root}->intersect($start, $end);
}

1;
