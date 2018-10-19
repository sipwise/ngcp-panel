package NGCP::Panel::Utils::Generic;
use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(is_int is_integer is_decimal merge compare is_false is_true get_inflated_columns_all hash2obj mime_type_to_extension extension_to_mime_type);
%EXPORT_TAGS = ( DEFAULT => [qw(&is_int &is_integer &is_decimal &merge &compare &is_false &is_true &mime_type_to_extension &extension_to_mime_type)],
    all    =>  [qw(&is_int &is_integer &is_decimal &merge &compare &is_false &is_true &get_inflated_columns_all &hash2obj &mime_type_to_extension &extension_to_mime_type)]);

use Hash::Merge;
use Data::Compare qw//;

my $MIME_TYPES = {
    #first extension is default, others are for extension 2 mime_type detection
    'audio/x-wav' => ['wav'],
    'audio/mpeg'  => ['mp3'], 
    'audio/ogg'   => ['ogg'],
};

sub is_int {
    my $val = shift;
    if($val =~ /^[+-]?[0-9]+$/) {
        return 1;
    }
    return;
}

sub is_integer {
    return is_int(@_);
}

sub is_decimal {
    my $val = shift;
    # TODO: also check if only 0 or 1 decimal point
    if($val =~ /^[+-]?\.?[0-9\.]+$/) {
        return 1;
    }
    return;
}

sub merge {
    my ($a, $b) = @_;
    return Hash::Merge::merge($a, $b);
}

sub is_true {
    my ($v) = @_;
    my $val;
    if(ref $v eq "") {
        $val = $v;
    } else {
        $val = ${$v};
    }
    return 1 if(defined $val && $val == 1);
    return;
}

sub is_false {
    my ($v) = @_;
    my $val;
    if(ref $v eq "") {
        $val = $v;
    } else {
        $val = ${$v};
    }
    return 1 unless(defined $val && $val == 1);
    return;
}
# 0 if different, 1 if equal
sub compare {
    return Data::Compare::Compare(@_);
}

sub get_inflated_columns_all{
    my ($rs,%params) = @_;
    #params = {
    #    hash   => result will be hash, with key, taken from the column with name, stored in this param,
    #    column => if hash param exists, value of the hash will be taken from the column with, stored in the param "column"
    #    force_array => hash values always will be an array ref
    #}
    my ($res);
    $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    if(my $hashkey_column = $params{hash}){
        my %lres;
        my $register_value = sub {
            my($hash,$key,$value) = @_;
            if( $params{force_array} || exists $hash->{$key} ){
                if('ARRAY' eq ref $hash->{$key}){
                    push @{$hash->{$key}}, $value;
                }else{
                    if( exists $hash->{$key}){
                        $hash->{$key} = [$hash->{$key}, $value];
                    }else{
                        $hash->{$key} = [$value];
                    }
                }
            }else{
                $hash->{$key} = $value;
            }
        };
        my $hashvalue_column = $params{column};
        foreach($rs->all){
            $register_value->(\%lres,$_->{$hashkey_column}, $hashvalue_column ? $_->{$hashvalue_column} : $_);
        }
        $res = \%lres;
    }else{
        $res = [$rs->all];
    }
    return $res;
    #return [ map { { $_->get_inflated_columns }; } $rs->all ];
}

sub hash2obj {
    my %params = @_;
    my ($hash,$private,$classname,$accessors) = @params{qw/hash private classname accessors/};

    my $obj;
    $obj = $hash if 'HASH' eq ref $hash;
    $obj //= {};
    $obj = { %$obj, %$private } if 'HASH' eq ref $private;
    unless (defined $classname and length($classname) > 0) {
        my @chars = ('A'..'Z');
        $classname //= '';
        $classname .= $chars[rand scalar @chars] for 1..8;
    }
    $classname = __PACKAGE__ . '::' . $classname unless $classname =~ /::/;
    bless($obj,$classname);
    no strict "refs";  ## no critic (ProhibitNoStrict)
    return $obj if scalar %{$classname . '::'};
    use strict "refs";
    #print "registering class $classname\n";
    $accessors //= {};
    foreach my $accessor (keys %$accessors) {
        #print "registering accessor $classname::$accessor\n";
        no strict "refs";  ## no critic (ProhibitNoStrict)
        *{$classname . '::' . $accessor} = sub {
            my $self = shift;
            return &{$accessors->{$accessor}}($self,@_);
        } if 'CODE' eq ref $accessors->{$accessor};
        *{$classname . '::' . $accessor} = sub {
            my $self = shift;
            return $self->{$accessors->{$accessor}};
        } if '' eq ref $accessors->{$accessor};
    }
    return $obj;
}

sub mime_type_to_extension {
    my ($mime_type) = @_;
    return $MIME_TYPES->{$mime_type}->[0];
}

sub extension_to_mime_type {
    my ($extension) = @_;
    my $mime_type;
    $extension = lc($extension);
    foreach my $k (keys %$MIME_TYPES) {
        if (grep {$_ eq $extension} @{$MIME_TYPES->{$k}}) {
            $mime_type = $k;
            last;
        }
    }
    return $mime_type;
}

1;
