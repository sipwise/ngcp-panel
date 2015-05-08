package NGCP::Panel::Utils::Form;

use Sipwise::Base;

sub validate_password {
    my %params = @_;
    my $c = $params{c};
    my $field = $params{field};
    my $r = $c->config->{security};
    my $pass = $field->value;

    my $minlen = $r->{password_min_length} // 6;
    my $maxlen = $r->{password_max_length} // 40;

    if(length($pass) < $minlen) {
        $field->add_error($c->loc('Must be at minimum [_1] characters long', $minlen));
    }
    if(length($pass) > $maxlen) {
        $field->add_error($c->loc('Must be at maximum [_1] characters long', $maxlen));
    }
    if($r->{password_musthave_lowercase} && $pass !~ /[a-z]/) {
        $field->add_error($c->loc('Must contain lower-case characters'));
    }
    if($r->{password_musthave_uppercase} && $pass !~ /[A-Z]/) {
        $field->add_error($c->loc('Must contain upper-case characters'));
    }
    if($r->{password_musthave_digit} && $pass !~ /[0-9]/) {
        $field->add_error($c->loc('Must contain digits'));
    }
    if($r->{password_musthave_specialchar} && $pass !~ /[^0-9a-zA-Z]/) {
        $field->add_error($c->loc('Must contain special characters'));
    }
}

sub validate_entities {
    my (%params) = @_;
    
    #usage:
    #1. last unless validate_entities(c => $c, contracts => 4711, customers => 4712);
    #2. return unless validate_entities(c => $c, resource => $json, contract_id => 'contracts');
    #3. my $entities = {}; last unless validate_entities(c => $c, resource => $json,
    #    parent_id => $c->user->reseller_id,
    #    profile_id => { resultset => 'billing_profiles',
    #                    optional => 1,
    #                    parent_field => 'reseller_id',
    #                    deleted_field => 'status',
    #                    deleted_value => 'terminated'},
    #    entities => $entities);
    #4. last unless validate_entities(..., error => sub { $self->error($c, HTTP_UNPROCESSABLE_ENTITY, shift); });
    #5. validation in form handlers...
    
    my @args = qw/c resource parent_id error entities/;
    my ($c,$res,$parent_id,$err_code,$entities) = delete @params{@args};    

    my $schema = $c->model('DB');
    if ('CODE' ne ref $err_code) {
        $err_code = sub { return undef; };
    }
    
    my $validate_field = sub {
        my $name = shift;
        my $field = $params{$name}; # { id, resultset, optional, deleted_field, deleted_value, parent_field }
        my $is_res = 'HASH' eq ref $res;
        if ('HASH' ne ref $field) {
            $field = { ($is_res ? 'resultset' : 'id'), $field };
        }
        if ($is_res) {
            $field->{id} = $res->{$name} if !exists $field->{id};
            $field->{label} //= "'" . $name . "'";
        } else {
            $field->{resultset} //= $name;
            $field->{label} //= $name . ' ID';
        }
        $field->{optional} //= 0;
        $field->{hfh_field} //= $name;
        if (!$field->{optional} && !defined $field->{id}) {
            return 0 unless &{$err_code}("Invalid $field->{label}, not defined.",$field->{hfh_field});
        }
        my $entity = undef;
        eval {
            $entity = (defined $field->{id} ? $schema->resultset($field->{resultset})->find($field->{id}) : undef);
        };
        if ($@) {
            return 0 unless &{$err_code}($@,$field->{hfh_field});
        }
        if (defined $field->{id} && !defined $entity) {
            return 0 unless &{$err_code}("Invalid $field->{label} ($field->{id}).",$field->{hfh_field});
        }
        if (defined $field->{deleted_field} && defined $field->{deleted_value} && defined $entity) {
            my $deleted_accessor = $field->{deleted_field};
            if (defined $entity->$deleted_accessor() && $field->{deleted_value} eq $entity->$deleted_accessor()) {
                return 0 unless &{$err_code}("Invalid $field->{label} ($field->{id}), $field->{deleted_value}.",$field->{hfh_field});
            }
        }
        if (defined $parent_id && defined $field->{parent_field} && defined $entity) {
            my $parent_accessor = $field->{parent_field};
            if (defined $entity->$parent_accessor() && $parent_id != $entity->$parent_accessor()) {
                return 0 unless &{$err_code}("The $field->{parent} of $field->{label} (" . $entity->$parent_accessor() . ") doesn't match.",$field->{hfh_field});
            }
        }
        if ('HASH' eq ref $entities) {
            $entities->{$name} = $entity;
        }
        return 1;
    };

    foreach my $name (keys %params) {
        return 0 unless &$validate_field($name);
    }  
    
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
