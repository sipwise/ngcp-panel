package NGCP::Panel::Utils::Generic;
use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(is_int is_integer is_decimal merge compare is_false is_true get_inflated_columns_all);
%EXPORT_TAGS = ( DEFAULT => [qw(&is_int &is_integer &is_decimal &merge &compare &is_false &is_true)],
                 all    =>  [qw(&is_int &is_integer &is_decimal &merge &compare &is_false &is_true &get_inflated_columns_all)]);

use Hash::Merge;
use Data::Compare qw//;

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
            if(exists $hash->{$key} || $params{force_array}){
                if('ARRAY' eq ref $hash->{$key}){
                    push @{$hash->{$key}}, $value;
                }else{
                    $hash->{$key} = [$hash->{$key}, $value];
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

1;
