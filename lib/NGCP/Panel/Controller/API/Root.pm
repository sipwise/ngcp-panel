package NGCP::Panel::Controller::API::Root;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use Encode qw(encode);
use Clone qw/clone/;
use HTTP::Headers qw();
use HTTP::Response qw();
use HTTP::Status qw(:constants);
use File::Find::Rule;
use JSON qw(to_json encode_json decode_json);
use YAML::XS qw/Dump/;
use Safe::Isa qw($_isa);
use NGCP::Panel::Utils::API;
use List::Util qw(none all);
use parent qw/Catalyst::Controller NGCP::Panel::Role::API/;

use NGCP::Panel::Utils::Journal qw();
use NGCP::Panel::Utils::License;

#with 'NGCP::Panel::Role::API';

sub dispatch_path{return '/api/';}

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => 'invalid_user',
            AllowedRole => [qw/admin reseller ccareadmin ccare lintercept subscriberadmin subscriber/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
);

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
    return 1;
}

sub GET : Allow {
    my ($self, $c) = @_;

    my $response_type;
    if ($c->req->params->{swagger}) {
        $response_type = 'swagger';
    } elsif ($c->req->header('Accept') && $c->req->header('Accept') eq 'application/json') {
        $response_type = 'plain_json';
    } elsif ($c->req->params->{oldapidoc}) {
        $response_type = 'oldapidoc';
    } else {
        $response_type = 'swaggerui';
    }

    if ($response_type eq 'swaggerui') {
        $c->detach('swaggerui');
    }

    my $blacklist = {
        "DomainPreferenceDefs" => 1,
        "SubscriberPreferenceDefs" => 1,
        "CustomerPreferenceDefs" => 1,
        "ProfilePreferenceDefs" => 1,
        "PeeringServerPreferenceDefs" => 1,
        "ResellerPreferenceDefs" => 1,
        "PbxDevicePreferenceDefs" => 1,
        "PbxDeviceProfilePreferenceDefs" => 1,
        "PbxFieldDevicePreferenceDefs" => 1,
        "MetaConfigDefs" => 1,
        "AuthTokens" => 1,
        "OTPSecret" => 1,
    };

    my $colls = NGCP::Panel::Utils::API::get_collections_files;
    my %user_roles = map {$_ => 1} $c->user->roles;
    foreach my $coll(@$colls) {
        my $mod = $coll;
        $mod =~ s/^.+\/([a-zA-Z0-9_]+)\.pm$/$1/;
        next if(exists $blacklist->{$mod});
        my $rel = lc $mod;
        my $full_mod = 'NGCP::Panel::Controller::API::'.$mod;
        my $full_item_mod = 'NGCP::Panel::Controller::API::'.$mod.'Item';

        my $role = $full_mod->config->{action}->{OPTIONS}->{AllowedRole};
        if($role && ref $role eq "ARRAY") {
            next if none { $user_roles{$_} } @{ $role };
        } elsif ($role) {
            next unless $user_roles{$role};
        }

        if ($full_mod->can('config')) {
            my $allowed_ngcp_types = $full_mod->config->{allowed_ngcp_types} // [];
            if (@{$allowed_ngcp_types}) {
                next if none { $_ eq $c->config->{general}{ngcp_type} }
                    @{$allowed_ngcp_types};
            }

            my $required_licenses = $full_mod->config->{required_licenses} // undef;
            if (ref $required_licenses eq 'ARRAY') {
                if (@{$required_licenses} &&
                    ! all { $c->license($_) } @{$required_licenses}) {
                        next;
                }
            }
        }

        my $query_params = [];
        if($full_mod->can('query_params')) {
            $query_params = $full_mod->query_params;
        }
        my $actions = [];
        if($c->user->read_only) {
            foreach my $m(sort keys %{ $full_mod->config->{action} }) {
                next unless $m =~ /^(GET|HEAD|OPTIONS)$/;
                push @{ $actions }, $m;
            }
        } else {
            $actions = [ sort keys %{ $full_mod->config->{action} } ];
        }

        if ($full_mod->can('config')) {
            my $required_licenses = $full_mod->config->{required_licenses} // undef;
            if (ref $required_licenses eq 'HASH') {
                foreach my $method (qw/GET HEAD OPTIONS POST/) {
                    if (my $method_licenses = $required_licenses->{$method}) {
                        if (@{$method_licenses} &&
                            ! all { $c->license($_) } @{$method_licenses}) {
                                $actions = [grep { $_ ne $method } @{$actions}];
                        }
                    }
                }
            }
        }

        my $uri = "/api/$rel/";
        my $item_actions = [];
        my $journal_resource_config = {};
        if($full_item_mod->can('config')) {
            if($c->user->read_only) {
                foreach my $m(sort keys %{ $full_item_mod->config->{action} }) {
                    next unless $m =~ /^(GET|HEAD|OPTIONS)$/;
                    push @{ $item_actions }, $m;
                }
            } else {
                foreach my $m(sort keys %{ $full_item_mod->config->{action} }) {
                    next unless $m =~ /^(GET|HEAD|OPTIONS|PUT|PATCH|DELETE)$/;
                    push @{ $item_actions }, $m;
                }
            }

            my $required_licenses = $full_item_mod->config->{required_licenses} // undef;
            if (ref $required_licenses eq 'ARRAY') {
                if (@{$required_licenses} &&
                    ! all { $c->license($_) } @{$required_licenses}) {
                        $item_actions = [];
                }
            } elsif (ref $required_licenses eq 'HASH') {
                foreach my $method (qw/GET HEAD OPTIONS PUT PATCH DELETE/) {
                    if (my $method_licenses = $required_licenses->{$method}) {
                        if (@{$method_licenses} &&
                            ! all { $c->license($_) } @{$method_licenses}) {
                                $item_actions = [grep { $_ ne $method } @{$actions}];
                        }
                    }
                }
            }

            if($full_item_mod->can('resource_name')) {
                my @operations = ();
                my $op_config = {};
                my $resource_name = $full_item_mod->resource_name;
                $journal_resource_config = NGCP::Panel::Utils::Journal::get_journal_resource_config($c->config,$resource_name);
                if (exists $full_mod->config->{action}->{POST}) {
                    $op_config = NGCP::Panel::Utils::Journal::get_api_journal_op_config($c->config,$resource_name,NGCP::Panel::Utils::Journal::CREATE_JOURNAL_OP);
                    if ($op_config->{operation_enabled}) {
                        push(@operations,"create (<span>POST $uri</span>)");
                    }
                }
                my $item_action_config = $full_item_mod->config->{action};
                if (exists $item_action_config->{PUT} || exists $item_action_config->{PATCH}) {
                    $op_config = NGCP::Panel::Utils::Journal::get_api_journal_op_config($c->config,$resource_name,NGCP::Panel::Utils::Journal::UPDATE_JOURNAL_OP);
                    if ($op_config->{operation_enabled}) {
                        if (exists $item_action_config->{PUT} && exists $item_action_config->{PATCH}) {
                            push(@operations,"update (<span>PUT/PATCH $uri"."id</span>)");
                        } elsif (exists $item_action_config->{PUT}) {
                            push(@operations,"update (<span>PUT $uri"."id</span>)");
                        } elsif (exists $item_action_config->{PATCH}) {
                            push(@operations,"update (<span>PATCH $uri"."id</span>)");
                        }
                    }
                }
                if (exists $item_action_config->{DELETE}) {
                    $op_config = NGCP::Panel::Utils::Journal::get_api_journal_op_config($c->config,$resource_name,NGCP::Panel::Utils::Journal::CREATE_JOURNAL_OP);
                    if ($op_config->{operation_enabled}) {
                        push(@operations,"delete (<span>DELETE $uri"."id</span>)");
                    }
                }
                $journal_resource_config->{operations} = \@operations;
                $journal_resource_config->{format} = $op_config->{format};
                $journal_resource_config->{uri} = 'api/' . $resource_name . '/id/' . NGCP::Panel::Utils::Journal::API_JOURNAL_RESOURCE_NAME . '/';
                $journal_resource_config->{query_params} = ($full_item_mod->can('journal_query_params') ? $full_item_mod->journal_query_params : []);
                $journal_resource_config->{sorting_cols} = NGCP::Panel::Utils::Journal::JOURNAL_FIELDS;
                $journal_resource_config->{item_uri} = $journal_resource_config->{uri} . 'journalitemid';
                if (length(NGCP::Panel::Utils::Journal::API_JOURNALITEMTOP_RESOURCE_NAME) > 0) {
                    $journal_resource_config->{recent_uri} = $journal_resource_config->{uri} . NGCP::Panel::Utils::Journal::API_JOURNALITEMTOP_RESOURCE_NAME;
                }
            }
        }

        my ($form) = $full_mod->get_form($c);

        my $sorting_cols = [];
        my ($explicit_order_cols, $explicit_order_cols_params);
        if ($full_mod->can('order_by_cols')) {
            ($explicit_order_cols,$explicit_order_cols_params) = $full_mod->order_by_cols($c);
            $sorting_cols = [ sort keys %$explicit_order_cols ];
            $explicit_order_cols_params //= {};
        }
        if (!$explicit_order_cols || $explicit_order_cols_params->{columns_are_additional}) {
            my $item_rs;
            try {
                $item_rs = $full_mod->item_rs($c, "");
            }
            if ($item_rs) {
                if(ref $item_rs eq "ARRAY") {
                    $sorting_cols = [sort (@$sorting_cols, map { $_->{name} } @{ $item_rs })];
                } else {
                    $sorting_cols = [sort (@$sorting_cols, $item_rs->result_source->columns)];
                }
            }
        }
        my ($form_fields,$form_fields_upload) = $form ? $self->get_collection_properties($form) : ([],[]);

        my $documentation_sample = {} ;
        my $documentation_sample_process = sub{
            my $s = shift;
            $s = to_json($s, {pretty => 1}) =~ s/(^\s*{\s*)|(\s*}\s*$)//rg =~ s/\n   /\n/rg;
            return $s;
        };
        if ($full_mod->can('documentation_sample')) {
            $documentation_sample->{sample_orig}->{default} = $full_mod->documentation_sample;
            $documentation_sample->{sample}->{default} = $documentation_sample_process->($documentation_sample->{sample_orig}->{default});
        }
        foreach my $action (qw/create update/){
            my $method = 'documentation_sample_'.$action;
            if ($full_mod->can($method)) {
                $documentation_sample->{sample_orig}->{$action} = $full_mod->$method;
                $documentation_sample->{sample}->{$action} = $documentation_sample_process->($documentation_sample->{sample_orig}->{$action});
            }
        }


        my $entity_name = $mod;
        if($entity_name eq 'Faxes') {
            $entity_name = 'Fax';
        } else {
            $entity_name =~ s/ies$/y/;
            $entity_name =~ s/s$//;
        }

        $c->stash->{collections}->{$rel} = {
            name => $mod,
            entity_name => $entity_name,
            description => $full_mod->api_description,
            fields => $form_fields,
            uploads => $form_fields_upload,
            config => $full_mod->config ,
            ( $full_item_mod && $full_item_mod->can('config') ) ? (item_config => $full_item_mod->config) : () ,
            query_params => $query_params,
            actions => $actions,
            item_actions => $item_actions,
            sorting_cols => $sorting_cols,
            uri => $uri,
            properties => ( $full_mod->can('properties') ?  $full_mod->properties : {} ),#
            %$documentation_sample,
            journal_resource_config => $journal_resource_config,
        };

    }

    if ($user_roles{subscriber} || $user_roles{subscriberadmin}) {
        $c->stash(is_subscriber_api => 1);
    } else {
        $c->stash(is_admin_api => 1);
    }

    if ($response_type eq 'plain_json') {
        my $body = {};
        foreach my $rel(sort keys %{ $c->stash->{collections} }) {
            my $r = $c->stash->{collections}->{$rel};
            foreach my $k(qw/
                    actions item_actions fields sorting_cols
            /) {
                $body->{$rel}->{$k} = $r->{$k};
            }
            $body->{$rel}->{query_params} = [
                map { $_->{param} } @{ $r->{query_params} }
            ];
        }
        $c->response->body(JSON::to_json($body, { pretty => 1 }));
        $c->response->headers(HTTP::Headers->new(
            Content_Language => 'en',
            Content_Type => 'application/json',
        ));
    } elsif ($response_type eq 'swagger') {
        $c->detach('swagger');
    } elsif ($response_type eq 'oldapidoc') {
        $c->stash(template => 'api/root.tt');
        $c->forward($c->view);
        $c->response->headers(HTTP::Headers->new(
            Content_Language => 'en',
            Content_Type => 'application/xhtml+xml',
            #$self->collections_link_headers,
        ));
    } else {
        die 'This should never happen.';
    }

    return;
}

sub swagger :Private {
    my ($self, $c) = @_;

    my $collections = $c->stash->{collections};
    my $user_role = $c->user->roles;

    my $result = NGCP::Panel::Utils::API::generate_swagger_datastructure(
        $collections,
        $user_role,
    );

    my $headers = HTTP::Headers->new(Content_Language => 'en');
    my $response;
    if ($c->req->params->{swagger} eq 'yml') {
        $headers->header(Content_Type => 'application/x-yaml');
        $response = Dump($result);
    }
    else {
        $headers->header(Content_Type => 'application/json');
        $response = encode_json($result);
    }
    $c->response->headers($headers);
    $c->response->body($response);
    $c->response->code(200);
    return;
}

sub swaggerui :Private {
    my ($self, $c) = @_;


    $c->stash(template => 'api/swaggerui.tt');
    $c->forward($c->view);
    # $c->response->headers(HTTP::Headers->new(
    #     Content_Language => 'en',
    #     Content_Type => 'application/xhtml+xml',
    #     #$self->collections_link_headers,
    # ));
}

sub platforminfo :Path('/api/platforminfo') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->response->content_type('application/json');
    unless (uc $c->request->method eq 'GET') {
        $c->response->status(HTTP_METHOD_NOT_ALLOWED);
        $c->response->body(q());
        return;
    }

    $c->stash->{ngcp_api_realm} = $c->request->env->{NGCP_API_REALM} // "";
    $c->stash(template => 'api/platforminfo.tt');
    $c->stash(process_json_file_cb => sub {
        my $json_file = shift;
        my $json = '';
        my $licenses = NGCP::Panel::Utils::License::get_licenses($c);
        my $license_meta = NGCP::Panel::Utils::License::get_license_meta($c);
        open(my $fh, '<', $json_file) || return;
        $json .= $_ while <$fh>;
        close $fh;
        my $data = decode_json($json) || return;
        $data->{licenses} = $licenses // [];
        $data->{license_meta} = $license_meta // {};
        return to_json($data, {pretty => 1, canonical => 1});
    });
    $c->forward($c->view());
}

sub HEAD : Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS : Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        $self->collections_link_headers,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub collections_link_headers : Private {
    my ($self) = @_;

    my $colls = NGCP::Panel::Utils::API::get_collections_files;

    # create Link header for each of the collections
    my @links = ();
    foreach my $mod(@$colls) {
        # extract file base from path (e.g. Foo from lib/something/Foo.pm)
        $mod =~ s/^.+\/([a-zA-Z0-9_]+)\.pm$/$1/;
        my $rel = lc $mod;
        $mod = 'NGCP::Panel::Controller::API::'.$mod;
        my $dp = $mod->dispatch_path;
        push @links, Link => '<'.$dp.'>; rel="collection http://purl.org/sipwise/ngcp-api/#rel-'.$rel.'"';
    }
    return @links;
}

sub invalid_user : Private {
    my ($self, $c, $ssl_client_m_serial) = @_;

    #$self->error($c, HTTP_FORBIDDEN, "Invalid certificate serial number '$ssl_client_m_serial'.");
    $self->error($c, HTTP_FORBIDDEN, "Invalid user");
    return;
}

sub invalid_otp : Private {
    my ($self, $c, $otp) = @_;

    $self->error($c, HTTP_FORBIDDEN, "Invalid OTP");
    return;
}

sub banned_user : Private {
    my ($self, $c, $user) = @_;

    my $log_user = "'$user'" // '';

    $self->error($c, HTTP_FORBIDDEN, "Banned");
    $c->log->warn("banned user $log_user api login from '".$c->qs($c->req->address)."'");

    return;
}

sub field_to_json : Private {
    my ($self, $field) = @_;

    if ($field->$_isa('HTML::FormHandler::Field::Select')) {
        return $self->field_to_select_options($field);
    } # elsif { ... }


    SWITCH: for ($field->type) {
        /Float|Integer|Money|PosInteger|Minute|Hour|MonthDay|Year/ &&
            return "Number";
        /Boolean/ &&
            return "Boolean";
        /Repeatable/ &&
            return "Array";
        /\+NGCP::Panel::Field::Select/ &&
             return $self->field_to_select_options($field);
        /\+NGCP::Panel::Field::Regex/ &&
             return "String";
        /\+NGCP::Panel::Field::DateTime/ &&
             return "String";
        /\+NGCP::Panel::Field::Country/ &&
             return "String";
        /\+NGCP::Panel::Field::EmailList/ &&
             return "String";
        /\+NGCP::Panel::Field::Identifier/ &&
            return "String";
        /\+NGCP::Panel::Field::URI/ &&
            return "String";
        /\+NGCP::Panel::Field::IPAddress/ &&
            return "String";
        /\+NGCP::Panel::Field::E164/ &&
            return "Object";
        /Compound/ &&
            return "Object";
        /\+NGCP::Panel::Field::AliasNumber/ &&
            return "Array";
        /\+NGCP::Panel::Field::PbxGroupAPI/ &&
            return "Array";
        /\+NGCP::Panel::Field::PbxGroupMemberAPI/ &&
            return "Array";
        /\+NGCP::Panel::Field::Interval/ &&
            return "Object";
        /\+NGCP::Panel::Field::DatePicker/ &&
            return "String";
        /\+NGCP::Panel::Field::NumRangeAPI/ &&
            return "String";
        # usually {xxx}{id}
        /\+NGCP::Panel::Field::/ &&
            return "Number";
        # default
        return "String";
    } # SWITCH
}

sub field_to_select_options : Private {
    my ($self, $field) = @_;
    return join('|',map {
        my $value = $_->{value};
        my $label = $_->{label};
        my $s = defined $value ? "'".$value."'" : 'null';
        if (defined $label && length($label)) {
            if (!defined $value || (lc($value) ne lc($label))) {
                $s.=' ('.$label.')';
            }
        }
        $s;
    } @{$field->options});

}

sub get_field_poperties :Private{
    my ($self, $field) = @_;
    my $name = $field->name;

    return () if (
        $field->type eq "Hidden" ||
        $field->type eq "Button" ||
        $field->type eq "Submit" ||
        $field->type eq "AddElement" ||
        $field->type eq "RmElement" ||
        0);
    my @types = ();
    push @types, 'null' unless ($field->required || $field->validate_when_empty);
    my $type;
    if($field->type =~ /^\+NGCP::Panel::Field::/) {
        if($field->type =~ /E164$/) {
            $name = 'primary_number';
        } elsif($field->type =~ /AliasNumber/) {
            $name = 'alias_numbers';
        } elsif($field->type =~ /PbxGroupAPI/) {
            $name = 'pbx_group_ids';
        } elsif($field->type =~ /Country$/) {
            $name = 'country';
        } elsif($field->type =~ /LnpCarrier$/) {
            $name = 'carrier_id';
        } elsif($field->type !~ /Regex|EmailList|Identifier|PosInteger|Interval|Select|DateTime|URI|IPAddress|DatePicker|ProfileNetwork|CFSimpleAPICompound|NumRangeAPI|IntegerList/) { # ...?
            $name .= '_id';
        }
    }
    my $enum;
    push(@types, $self->field_to_json($field));
    if ($field->$_isa('HTML::FormHandler::Field::Select')) {
        $enum = $field->options;
    }
    my $desc = undef;
    if($field->element_attr) {
        $desc = $field->element_attr->{title}->[0];
    }
    unless (defined $desc && length($desc) > 0) {
        $desc = $field->label;
    }
    unless (defined $desc && length($desc) > 0) {
        $desc = 'to be described ...';
    }

    my $subfields;
    if ($field->has_fields && scalar ($field->fields)) {
        my ($firstsub) = $field->fields;
        if ($field->isa('HTML::FormHandler::Field::Repeatable') && $firstsub) {
            ($subfields) = $self->get_collection_properties($firstsub, 1);
        } elsif ($firstsub->type eq '+NGCP::Panel::Field::DataTable' && $name =~ /_id$/) {
            # don't render subfields (only DataTable Field with Button)
        } elsif ($firstsub->type eq '+NGCP::Panel::Field::DataTable' && $name =~ /^(country|timezone)$/) {
            # also don't render subfields of country and timezone (they have no _id ending)
        } elsif ($field->type eq 'String' && $name =~ /^(domain)$/) {
            # another special case, special syntax of domain in subscribers
        } else {
            ($subfields) = $self->get_collection_properties($field, 1);
        }
    }

    return { name => $name, description => $desc, types => \@types, type_original => $field->type,
        readonly => $field->readonly,
        ($enum ? (enum => $enum) : ()),
        ($subfields ? (subfields => $subfields) : ()),
    };
}

sub get_collection_properties {
    my ($self, $form, $is_nested) = @_;

    my $renderlist = $form->form && !$is_nested
        ? $form->form->blocks->{fields}->{render_list}
        : undef;
    my %renderlist = defined $renderlist ? map { $_ => 1 } @{$renderlist} : ();

    my @props = ();
    my @uploads = ();
    foreach my $f($form->fields) {
        my $name = $f->name;
        next if (defined $renderlist && !exists $renderlist{$name});
        my $field_spec = $self->get_field_poperties($f);
        next if !$field_spec;
        push @props, $field_spec;
        push @uploads, $field_spec if $f->type =~/Upload/;
        if (my $spec = $f->element_attr->{implicit_parameter}) {
            my $f_implicit = clone($f);
            foreach my $field_attribute (keys %{$spec}){
                $f_implicit->$field_attribute($spec->{$field_attribute});
            }
            push @props, $self->get_field_poperties($f_implicit);
        }
    }
    @props = sort{$a->{name} cmp $b->{name}} @props;

    return (\@props,\@uploads);
}

sub end : Private {
    my ($self, $c) = @_;

    $c->clear_errors;
    #$self->log_response($c);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
