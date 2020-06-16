package NGCP::Test::Patch;
use strict;
use warnings;

use Moose;
use JSON;
use JSON::Pointer;
use Try::Tiny;


sub apply_patch {
    my ($self, $entity, $json, $optional_field_code_ref) = @_;
    my $patch = JSON::decode_json($json);
    try {
        for my $op (@{ $patch }) {
            my $coderef = JSON::Pointer->can($op->{op});
            die "invalid op '".$op->{op}."' despite schema validation" unless $coderef;
            for my $op_name ($op->{op}) {
                if ('add' eq $op_name or 'replace' eq $op_name) {
                    try {
                        $entity = $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                    } catch {
                        my $pe = $_;
                        if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                            if (blessed($pe) && $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                                &$optional_field_code_ref(substr($op->{path},1),$entity,$op);
                                $entity = $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                            }
                        } else {
                            die($pe); #->rethrow;
                        }
                    };
                } elsif ('remove' eq $op_name) {
                    try {
                        $entity = $coderef->('JSON::Pointer', $entity, $op->{path});
                    } catch {
                        my $pe = $_;
                        if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                            if (blessed($pe) && $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                                &$optional_field_code_ref(substr($op->{path},1),$entity);
                                $entity = $coderef->('JSON::Pointer', $entity, $op->{path});
                            }
                        } else {
                            die($pe); #->rethrow;
                        }
                    };
                } elsif ('move' eq $op_name or 'copy' eq $op_name) {
                    try {
                        $entity = $coderef->('JSON::Pointer', $entity, $op->{from}, $op->{path});
                    } catch {
                        my $pe = $_;
                        if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                            if (blessed($pe) && $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                                &$optional_field_code_ref(substr($op->{path},1),$entity);
                                $entity = $coderef->('JSON::Pointer', $entity, $op->{from}, $op->{path});
                            }
                        } else {
                            die($pe); #->rethrow;
                        }
                    };
                } elsif ('test' eq $op_name) {
                    try {
                        die "test failed - path: $op->{path} value: $op->{value}\n"
                            unless $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                    } catch {
                        my $pe = $_;
                        if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                            if (blessed($pe) && $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                                &$optional_field_code_ref(substr($op->{path},1),$entity);
                                die "test failed - path: $op->{path} value: $op->{value}\n"
                                    unless $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                            }
                        } else {
                            die($pe); #->rethrow;
                        }
                    };
                }
            }
        }
    } catch {
        my $e = $_;
        die "Failed to patch json data: $e\n";
        return;
    };
    return $entity;
}

1;
