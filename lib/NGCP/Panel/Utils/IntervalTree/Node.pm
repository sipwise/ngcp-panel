package NGCP::Panel::Utils::IntervalTree::Node;

use strict;
use warnings;

use List::Util qw(min max);

my $EMPTY_NODE = __PACKAGE__->new(0, 0, undef);

sub _nlog {
  return -1.0 / log(0.5);
}

sub left_node {
  my ($self) = @_;
  return $self->{cleft} != $EMPTY_NODE ? $self->{cleft} : undef;
}

sub right_node {
  my ($self) = @_;
  return $self->{cright} != $EMPTY_NODE ? $self->{cright}  : undef;
}

sub root_node {
  my ($self) = @_;
  return $self->{croot} != $EMPTY_NODE ? $self->{croot} : undef;
}
    
#sub str {
#  my ($self) = @_;
#  return "Node($self->{start}, $self->{end})";
#}

sub new {
  my ($class, $start, $end, $interval) = @_;
  # Perl lacks the binomial distribution, so we convert a
  # uniform into a binomial because it naturally scales with
  # tree size.  Also, perl's uniform is perfect since the
  # upper limit is not inclusive, which gives us undefined here.
  my $self = {};
  $self->{priority} = POSIX::ceil(_nlog() * log(-1.0/(1.0 * rand() - 1)));
  $self->{start}    = $start;
  $self->{end}      = $end;
  $self->{interval} = $interval;
  $self->{maxend}   = $end;
  $self->{minstart} = $start;
  $self->{minend}   = $end;
  $self->{cleft}    = $EMPTY_NODE;
  $self->{cright}   = $EMPTY_NODE;
  $self->{croot}    = $EMPTY_NODE;
  return bless $self, $class;
}

sub insert {
  my ($self, $start, $end, $interval) = @_;
  my $croot = $self;
  # If starts are the same, decide which to add interval to based on
  # end, thus maintaining sortedness relative to start/end
  my $decision_endpoint = $start;
  if ($start == $self->{start}) {
    $decision_endpoint = $end;
  }

  if ($decision_endpoint > $self->{start}) {
    # insert to cright tree
    if ($self->{cright} != $EMPTY_NODE) {
      $self->{cright} = $self->{cright}->insert( $start, $end, $interval );
    }
    else {
      $self->{cright} = __PACKAGE__->new( $start, $end, $interval );
    }
    # rebalance tree
    if ($self->{priority} < $self->{cright}{priority}) {
      $croot = $self->rotate_left();
    }
  }
  else {
    # insert to cleft tree
    if ($self->{cleft} != $EMPTY_NODE) {
      $self->{cleft} = $self->{cleft}->insert( $start, $end, $interval);
    }
    else {
      $self->{cleft} = __PACKAGE__->new( $start, $end, $interval);
    }
    # rebalance tree
    if ($self->{priority} < $self->{cleft}{priority}) {
      $croot = $self->rotate_right();
    }
  }

  $croot->set_ends();
  $self->{cleft}{croot}  = $croot;
  $self->{cright}{croot} = $croot;
  return $croot;
}

sub rotate_right {
  my ($self) = @_;
  my $croot = $self->{cleft};
  $self->{cleft}  = $self->{cleft}{cright};
  $croot->{cright} = $self;
  $self->set_ends();
  return $croot;
}

sub rotate_left {
  my ($self) = @_;
  my $croot = $self->{cright};
  $self->{cright} = $self->{cright}{cleft};
  $croot->{cleft}  = $self;
  $self->set_ends();
  return $croot;
}

sub set_ends {
  my ($self) = @_;
  if ($self->{cright} != $EMPTY_NODE && $self->{cleft} != $EMPTY_NODE) {
    $self->{maxend} = max($self->{end}, $self->{cright}{maxend}, $self->{cleft}{maxend});
    $self->{minend} = min($self->{end}, $self->{cright}{minend}, $self->{cleft}{minend});
    $self->{minstart} = min($self->{start}, $self->{cright}{minstart}, $self->{cleft}{minstart});
  }
  elsif ( $self->{cright} != $EMPTY_NODE) {
    $self->{maxend} = max($self->{end}, $self->{cright}{maxend});
    $self->{minend} = min($self->{end}, $self->{cright}{minend});
    $self->{minstart} = min($self->{start}, $self->{cright}{minstart});
  }
  elsif ( $self->{cleft} != $EMPTY_NODE) {
    $self->{maxend} = max($self->{end}, $self->{cleft}{maxend});
    $self->{minend} = min($self->{end}, $self->{cleft}{minend});
    $self->{minstart} = min($self->{start}, $self->{cleft}{minstart});
  }
}

sub intersect {
  my ( $self, $start, $end, $sort ) = @_;
  $sort = 1 if !defined $sort;
  my $results = [];
  $self->_intersect( $start, $end, $results );
  return $results;
}

#*find = \&intersect;

sub _intersect {
  my ( $self, $start, $end, $results) = @_;
  # Left subtree
  if ($self->{cleft} != $EMPTY_NODE && $self->{cleft}{maxend} > $start) {
    $self->{cleft}->_intersect( $start, $end, $results );
  }
  # This interval
  if (( $self->{end} > $start ) && ( $self->{start} < $end )) {
    push @$results, $self->{interval};
  }
  # Right subtree
  if ($self->{cright} != $EMPTY_NODE && $self->{start} < $end) {
    $self->{cright}->_intersect( $start, $end, $results );
  }
}
    
1;
