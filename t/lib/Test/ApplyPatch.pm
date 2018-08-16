package Test::ApplyPatch;

use strict;
use warnings;
use Exporter qw'import';

our @EXPORT      = qw//;
our @EXPORT_OK   = qw/&apply_patch/;
our %EXPORT_TAGS = ( 
    DEFAULT => [qw/&apply_patch/],
    all    =>  [qw/&apply_patch/]
);

use JSON qw();
use JSON::Pointer;
use JSON::Pointer::Exception qw();
use TryCatch;
use Data::Dumper;

sub apply_patch {
    my ($entity, $patch, $optional_field_code_ref) = @_;
    for my $op (@{ $patch }) {
        my $coderef = JSON::Pointer->can($op->{op});
        die "invalid op '".$op->{op}."' despite schema validation" unless $coderef;
        for ($op->{op}) {
            if ('add' eq $_ or 'replace' eq $_) {
                try {
                    $entity = $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                } catch($pe) {
                    if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                        if (blessed($pe) && $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                            &$optional_field_code_ref(substr($op->{path},1),$entity,$op);
                            $entity = $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                        }
                    } else {
                        die($pe); #->rethrow;
                    }
                }
            } elsif ('remove' eq $_) {
                try {
                    $entity = $coderef->('JSON::Pointer', $entity, $op->{path});
                } catch($pe) {
                    if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                        if (blessed $pe && $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                            &$optional_field_code_ref(substr($op->{path},1),$entity);
                            $entity = $coderef->('JSON::Pointer', $entity, $op->{path});
                        }
                    } else {
                        die($pe); #->rethrow;
                    }
                }
            } elsif ('move' eq $_ or 'copy' eq $_) {
                try {
                    $entity = $coderef->('JSON::Pointer', $entity, $op->{from}, $op->{path});
                } catch($pe) {
                    if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                        if (blessed $pe && $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                            &$optional_field_code_ref(substr($op->{path},1),$entity);
                            $entity = $coderef->('JSON::Pointer', $entity, $op->{from}, $op->{path});
                        }
                    } else {
                        die($pe); #->rethrow;
                    }
                }
            } elsif ('test' eq $_) {
                try {
                    die "test failed - path: $op->{path} value: $op->{value}\n"
                        unless $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                } catch($pe) {
                    if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                        if (blessed $pe && $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                            &$optional_field_code_ref(substr($op->{path},1),$entity);
                            die "test failed - path: $op->{path} value: $op->{value}\n"
                                unless $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                        }
                    } else {
                        die($pe); #->rethrow;
                    }
                }
            }
        }
    }
    return $entity;
}
1;