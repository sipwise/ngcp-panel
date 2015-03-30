package Test::DeepHashUtils;

use 5.006;
use strict;
use warnings;
use Data::Dumper;

require Exporter;

our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw( reach slurp nest deepvalue ) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = ();
our $VERSION = '0.03';


my $C;

# Recursive version of C<each>;
sub reach {
    my $ref = shift;
    if (ref $ref eq 'HASH') {

        if (defined $C->{$ref}{v}) {
            if (ref $C->{$ref}{v} eq 'HASH' || ref $C->{$ref}{v} eq 'ARRAY') {
                if (my @rec = reach($C->{$ref}{v})) {
                    if (defined $C->{$ref}{k}) {
                        return ($C->{$ref}{k},@rec);
                    }
                    if (defined $C->{$ref}{i}) {
                        return ($C->{$ref}{i},@rec);
                    }
                    return @rec;
                }
            }
            undef $C->{$ref}{v};
        }


        if (my ($k,$v) = each %$ref) {
            $C->{$ref}{v} = $v;
            $C->{$ref}{k} = $k;
            return ($k,reach($v));
        }
        return ();

    } elsif (ref $ref eq 'ARRAY') {

        if (defined $C->{$ref}{v}) {
            if (ref $C->{$ref}{v} eq 'HASH' ||
                ref $C->{$ref}{v} eq 'ARRAY') {

                if (my @rec = reach($C->{$ref}{v})) {
                    if (defined $C->{$ref}{i}) {
                        return $C->{$ref}{i},@rec;
                    }
                    if (defined $C->{$ref}{k}) {
                        return $C->{$ref}{k},@rec;
                    }
                    return @rec;
                }
            }
            undef $C->{$ref}{v};
        }

        if(!(defined $C->{$ref}{i})){
            $C->{$ref}{i} = 0;
        }else{
            $C->{$ref}{i}++;
        }
        if (my $v = $ref->[$C->{$ref}{i}]) {
            $C->{$ref}{v} = $v;
            return ($C->{$ref}{i}, reach($v));
        }

        return ();
    }
    return $ref;
}


# run C<reach> over entire hash and return the final list of values at once
sub slurp {
    my $ref = shift;
    my @h;
    while (my @a = reach($ref)) {
        push @h,\@a;
    }
    return @h;
}


# Define nested hash keys from the given list of values
sub nest {
    my $hr = shift;
    my $ref = $hr;
    while ( @_ ) {
        my $key = shift @_;
        if (@_ > 1) {
            $ref = ('HASH' eq ref $ref ? $ref->{$key} : ('ARRAY' eq ref $ref ? $ref->[$key]:undef) ) ;
            $ref ||= {};
        } else {
            my $value = shift;
            if('HASH' eq ref $ref){
                $ref->{$key} = $value;
            }elsif('ARRAY' eq ref $ref){
                $ref->[$key] = $value;
            }
        }
    }
    return $hr;
}



# Return value at the end of the given nested hash keys and/or array indexes
sub deepvalue {
    my $hr = shift;
    while (@_) {
        my $key = shift;
        if (ref $hr eq 'HASH') {
            return unless ($hr = $hr->{$key});
        } elsif (ref $hr eq 'ARRAY') {
            return unless ($hr = $hr->[$key]);
        } else {
            return;
        }
    }
    return $hr;
}


1;
__END__


=head1 NAME

Test::DeepHashUtils - functions for iterating over and working with nested hashes

=head1 SYNOPSIS

    use Deep::Hash::Utils qw(reach slurp nest deepvalue);

    my %hash = (
          A => {
               B => {
                    W => 1,
                    X => 2,
                   },
               C => {
                    Y => 3,
                    Z => 4,
                   },
              }
         );

    while (my @list = reach(\%hash)) {
        print "@list";
    }

    for my $a (sort {$a->[2] cmp $b->[2]} slurp(\%hash)) {
        print "@$a";
    }



    my %new_hash = ();

    nest(\%new_hash,1,2,3,4,5);

    my $value = deepvalue(\%new_hash,1,2,3,4);



=head1 DESCRIPTION

This module provides functions for accessing and modifying values in deeply nested data structures


=head3 C<reach>

reach HASHREF

Iterate over each nested data structure contained in the given hash. Returns an array of each nested key/value set.

Just as C<each> lets you iterate over the keys and values in a single hash, C<reach> provides an iterator over any recursively nested data structures.

This helps avoid the need to use layers of nested loops in order to iterate over all entities in nested hashes and arrays.

The reference passed to C<reach> can contain any combination of nested hashes and arrays.  Hash keys and values will be ordered in the same manner as when using C<each>, C<keys>, or C<values>.

    use Deep::Hash::Utils qw(reach slurp nest);
    $\ = "\n";

    my %hash = (
        A => {
            B => {
                W => 1,
                X => 2,
                },
            C => {
                Y => 3,
                Z => 4,
                },
            }
        );

    while (my @list = reach(\%hash)) {
        print "@list";
    }

    __END__

    Outputs:

    A C Z 4
    A C Y 3
    A B W 1
    A B X 2



=head3 C<slurp>

slurp HASHREF

Returns a list of arrays generated by C<reach> at once.
Use this if you want the same result of C<reach> with the ability to sort each layer of keys.

    for my $a (sort {$a->[2] cmp $b->[2]} slurp(\%hash)) {
        print "@$a";
    }

    __END__

    Output:

    A B W 1
    A B X 2
    A C Y 3
    A C Z 4



=head3 C<nest>

nest HASHREF, LIST

define nested hash keys with a given list

    use Data::Dumper;

    my %new_hash = ();
    nest(\%new_hash,1,2,3,4,5);

    print Dumper \%new_hash;

    __END__

    Output:

    $VAR1 = {
              '1' => {
                       '2' => {
                                '3' => {
                                         '4' => 5
                                       }
                              }
                     }
            };


=head3 C<deepvalue>

deepvalue HASHREF, LIST

retrieve deeply nested values with a list of keys:

    my %new_hash = (
              '1' => {
                       '2' => {
                                '3' => {
                                         '4' => 5
                                       }
                              }
                     }
            );

    print Dumper deepvalue(\%new_hash,1,2,3,4);

    print Dumper deepvalue(\%new_hash,1,2);

    __END__

    Output:

    $VAR1 = 5;

    $VAR1 = {
              '3' => {
                       '4' => 5
                     }
            };


=head2 EXPORT

None by default.

=head1 REPOSITORY

L<https://github.com/neilbowers/perl-deep-hash-utils>

=head1 AUTHOR

Chris Becker, E<lt>clbecker@gmail.com<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Chris Becker

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.5 or,
at your option, any later version of Perl 5 you may have available.




=cut
