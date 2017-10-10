use strict;
use warnings;

use Data::Dumper;

my $cdr_hash1 = {
  field1 => "value1",
  field2 => "value2",
  field3 => "value3",
};
my $cdr_hash2 = {
  field1 => "value4",
  field2 => "value5",
  field3 => "value6",
};

my $item1 = hash2obj(
  hash => $cdr_hash1,
  classname => "myCDRItem",
  private => {},
  accessors => {
    source_user => sub {
      my $self = shift;
      return $self->{field1};
    },
    destination_user_in => sub {
      my $self = shift;
      return $self->{field2};
    },
    start_time => sub {
      my $self = shift;
      return $self->{field2};
    },
  }
);
my $item2 = hash2obj(
  hash => $cdr_hash2,
  #classname => "myCDRItem",
  private => {},
  accessors => {
    source_user => sub {
      my $self = shift;
      return $self->{field1};
    },
    destination_user_in => sub {
      my $self = shift;
      return $self->{field2} . 'xx';
    },
    start_time => sub {
      my $self = shift;
      return $self->{field2};
    },
  }
);

print $item1->destination_user_in;
print $item2->destination_user_in;
print $item2->field1;
exit;

sub hash2obj {
  #my $self = shift;
  my %params = @_;
  my ($hash,$classname,$accessors) = @params{qw/hash classname accessors/};

  my $obj;
  $obj = $hash if 'HASH' eq ref $hash;
  $obj //= {};
  unless (defined $classname and length($classname) > 0) {
    my @chars = ('A'..'Z');
    $classname //= '';
    $classname .= $chars[rand scalar @chars] for 1..8;
  }
  $classname = __PACKAGE__ . '::' . $classname unless $classname =~ /::/;
  bless($obj,$classname);
  no strict "refs"; # for below and to register new methods in package
  return $obj if scalar %{$classname . '::'};
  print "registering class $classname\n";
  $accessors //= {};
  my %accessors = ( (map { $_ => undef; } keys %$obj), %$accessors); # create accessors for fields too
  for my $accessor (keys %accessors) {
    print "registering accessor $classname::$accessor\n";
    # see http://search.cpan.org/~gsar/perl-5.6.1/pod/perltootc.pod
    # accessor can be a coderef ...
    *{$classname . '::' . $accessor} = sub {
      my $self = shift;
      &{$accessors{$accessor}}($self,shift) if scalar @_; #setter
      return &{$accessors{$accessor}}($self); #getter
    } if 'CODE' eq ref $accessors{$accessor};
    # ... or hash field name:
    *{$classname . '::' . $accessor} = sub {
      my $self = shift;
      $self->{$accessors{$accessor}} = shift if scalar @_; #setter
      return $self->{$accessors{$accessor}}; #getter
    } if '' eq ref $accessors{$accessor};
  }
  return $obj;
}