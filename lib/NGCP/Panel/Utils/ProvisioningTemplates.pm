package NGCP::Panel::Utils::ProvisioningTemplates;

use Sipwise::Base;

use NGCP::Panel::Form::ProvisioningTemplate qw();
use DateTime::TimeZone qw();
#use MIME::Base64 qw(decode_base64);
use String::MkPasswd qw();
use Eval::Closure qw(eval_closure);
use Tie::IxHash;
use Data::Dumper;
$Data::Dumper::Sortkeys = sub {
    my ($hash) = @_;
    my @keys = ();
    foreach my $k (keys %$hash) {
        next if grep { ref $hash->{$k} eq $_; } qw(
            DateTime
        );
        push(@keys,$k);
    }
    return \@keys;
};
use Text::CSV_XS qw();
use NGCP::Panel::Utils::DateTime qw();
use NGCP::Panel::Utils::BillingMappings qw();
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::Subscriber qw();
use NGCP::Panel::Utils::Preferences qw();
use NGCP::Panel::Utils::Kamailio qw();

my $IDENTIFIER_FNAME = 'identifier';
my $CODE_SUFFIX_FNAME = '_code';
my $FIELD_TYPE_ATTRIBUTE = 'type';
my $FIELD_VALUE_ATTRIBUTE = 'value';
my @INIT_FIELD_NAMES = qw(cc_ac_map default_cc);
my $PURGE_FIELD_NAME = 'purge';

my $strict_closure = 1;

sub create_provisioning_template_form {

    my %params = @_;
    my ($c,
        $base_uri) = @params{qw/
            c
            base_uri
        /};

    my $template = $c->stash->{provisioning_template_name};

    my $fields = _get_fields($c,0);
    my $form;

    try {
        $form = NGCP::Panel::Form::ProvisioningTemplate->new({
            ctx => $c,
            fields_config => [ values %$fields ],
        });
        $form->create_structure([ keys %$fields ]);
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $fields,
            desc  => $c->loc("Provisioning template '[_1]' failed: [_2]", $template, $e),
        );
        $c->response->redirect($base_uri);
        return 1;
    }

    my $params = {};
    my $posted = ($c->request->method eq 'POST');
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        my %log_data = %{$c->request->params};
        try {
            my $context = provision_begin(
                c => $c,
            );
            provision_commit_row(
                c => $c,
                context => $context,
                'values' => $form->values,
            );
            provision_finish(
                c => $c,
                context => $context,
            );
            NGCP::Panel::Utils::Message::info(
                c => $c,
                data => \%log_data,
                desc => $c->loc("Provisioning template '[_1]' done: subscriber [_2] created", $template, $context->{subscriber}->{username} . '@' . $context->{domain}->{domain}),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                data  => \%log_data,
                desc  => $c->loc("Provisioning template '[_1]' failed: [_2]", $template, $e),
            );
            $c->response->redirect($base_uri);
            return 1;
        }
        $c->response->redirect($base_uri);
        return 1;

    }

    $form->process if ($posted && $form->validated);
    $c->stash(form => $form);

    return 1;

}

sub process_csv {

    my(%params) = @_;
    my ($c,
        $data,
        $purge) = @params{qw/
        c
        data
        purge
    /};

    my $template = $c->stash->{provisioning_template_name};
    $c->log->debug("provisioning template $template - processing csv");
    my $csv = Text::CSV_XS->new({
        allow_whitespace => 1,
        binary => 1,
        keep_meta_info => 1
    });
    my $fields = _get_fields($c,0);
    my @cols = keys %$fields;
    my @fails = ();
    my $linenum = 0;
    my $context = provision_begin(
        c => $c,
        purge => $purge,
    );
    open(my $fh, '<:encoding(utf8)', $data);
    while ( my $line = <$fh> ){
        ++$linenum;
        next unless length $line;
        unless($csv->parse($line)) {
            push(@fails,{ linenum => $linenum, });
            next;
        }
        my $row = {};
        @{$row}{keys %$fields} = $csv->fields();
        try {
            provision_commit_row(
                c => $c,
                context => $context,
                'values' => $row,
            );
        } catch($e) {
            push(@fails,{ linenum => $linenum, msg => $e });
        }
    }

    provision_finish(
        c => $c,
        context => $context,
    );

    $c->log->debug("provisioning template $template - csv done");

    return ($linenum,\@fails);
}

sub provision_begin {

    my %params = @_;
    my ($c,
        $purge) = @params{qw/
            c
            purge
        /};

    my $schema = $c->model('DB');
    $schema->set_transaction_isolation('READ COMMITTED');

    my $context = {};
    $context->{dfrd} = {};
    $context->{now} = NGCP::Panel::Utils::DateTime::current_local();
    $context->{schema} = $schema;
    $context->{purge} = $purge // 0;

    my $fields = _get_fields($c,1);
    my $init_values = {};
    foreach my $fname (@INIT_FIELD_NAMES) {
        next unless exists $fields->{$fname};
        my ($k,$v) = _calculate_field($init_values, $fname, $fields);
        $init_values->{$k} = $v;
    }

    if (exists $init_values->{cc_ac_map} and not exists $context->{split_number}) {
        my $cc_ac_map = $init_values->{cc_ac_map};
        die("invalid cc ac map") unless ('HASH' eq ref $cc_ac_map);
        my $ac_len = {};
        my $default_cc = $init_values->{default_cc}; #undef
        my $cc_len_min = ~0;
        my $cc_len_max = 0;
        foreach my $cc (keys %$cc_ac_map) {
            my $ac_map = $cc_ac_map->{$cc};
            $cc_len_min = length($cc) if length($cc) < $cc_len_min;
            $cc_len_max = length($cc) if length($cc) > $cc_len_max;
            $ac_len->{$cc} = { min => ~0, max => 0, };
            if ('HASH' ne ref $ac_map) {
                die("invalid $cc ac map");
            } else {
                foreach my $ac (keys %$ac_map) {
                    if ($ac_map->{$ac}) { # ac enabled
                        $ac_len->{$cc}->{min} = length($ac) if length($ac) < $ac_len->{$cc}->{min};
                        $ac_len->{$cc}->{max} = length($ac) if length($ac) > $ac_len->{$cc}->{max};
                    } else {
                        delete $ac_map->{$ac};
                    }
                }
            }
        }
        $context->{split_number} = sub {
            my ($dn) = @_;
            my ($cc,$ac,$sn) = ('','',$dn);

            if ($default_cc) {
                $cc = $default_cc;
                $dn =~ s/^0//;
                $sn = $dn;
            } else {
                foreach my $cc_length ($cc_len_min .. $cc_len_max) {
                    my ($_cc,$_dn) = (substr($dn,0,$cc_length), substr($dn,$cc_length));
                    if (exists $cc_ac_map->{$_cc}) {
                        $cc = $_cc;
                        $sn = $_dn;
                        $dn = $_dn;
                        last;
                    }
                }
            }
            if (exists $cc_ac_map->{$cc}) {
                my $ac_map = $cc_ac_map->{$cc};
                foreach my $ac_length ($ac_len->{$cc}->{min} .. $ac_len->{$cc}->{max}) {
                    my ($_ac,$_sn) = (substr($dn,0,$ac_length), substr($dn,$ac_length));
                    if (exists $ac_map->{$_ac}) {
                        $ac = $_ac;
                        $sn = $_sn;
                        #$dn = '';
                        last;
                    }
                }
            }

            return {cc => $cc, ac => $ac, sn => $sn};
        };
    }

    foreach my $sub (qw(debug info warn error)) {
        $context->{$sub} = sub {
            return $c->log->$sub(@_);
        };
    }

    return $context;

}

sub provision_commit_row {

    my %params = @_;
    my ($c,
        $context,
        $values) = @params{qw/
            c
            context
            values
        /};

    my $template = $c->stash->{provisioning_template_name};
    my $schema = $c->model('DB');
    _init_row_context(
        $c,
        $context,
        $schema,
        $values,
    );

    my $guard = $schema->txn_scope_guard;
    _init_contract_context(
        $c,
        $context,
        $schema,
        $c->stash->{provisioning_templates}->{$template},
    );
    _create_contract_contact(
        $c,
        $context,
        $schema,
    );
    _create_contract(
        $c,
        $context,
        $schema,
    );
    _init_contract_preferences_context(
        $c,
        $context,
        $schema,
        $c->stash->{provisioning_templates}->{$template},
    );
    _create_contract_preferences(
        $c,
        $context,
        $schema,
    );

    my $purge = $context->{purge} || $values->{$PURGE_FIELD_NAME};
    try {
        _init_subscriber_context(
            $c,
            $context,
            $schema,
            $c->stash->{provisioning_templates}->{$template},
        );
        _create_subscriber(
            $c,
            $context,
            $schema,
        );
    } catch(DBIx::Class::Exception $e where { /Duplicate entry/ }) {
        my ($msg, $subscriber) = _get_duplicate_subs(
            $c,
            $context,
            $schema,
            $e,
            $purge,
        );
        if ($purge) {
            if ($subscriber) {
                $c->log->debug("provisioning template - terminating subscriber id " . $subscriber->id);
                NGCP::Panel::Utils::Subscriber::terminate(c => $c, subscriber => $subscriber);
                _create_subscriber(
                    $c,
                    $context,
                    $schema,
                );
            } else {
                die $msg;
            }
        } else {
            die $msg;
        }
    } catch($e where { /Subscriber already exists/ }) {
        my ($msg, $subscriber) = _get_duplicate_subs(
            $c,
            $context,
            $schema,
            $e,
            $purge,
        );
        if ($purge) {
            if ($subscriber) {
                $c->log->debug("provisioning template - terminating subscriber id " . $subscriber->id);
                NGCP::Panel::Utils::Subscriber::terminate(c => $c, subscriber => $subscriber);
                _init_subscriber_context(
                    $c,
                    $context,
                    $schema,
                    $c->stash->{provisioning_templates}->{$template},
                );
                _create_subscriber(
                    $c,
                    $context,
                    $schema,
                );
            } else {
                die $msg;
            }
        } else {
            die $msg;
        }
    }

    _init_subscriber_preferences_context(
        $c,
        $context,
        $schema,
        $c->stash->{provisioning_templates}->{$template},
    );
    _create_subscriber_preferences(
        $c,
        $context,
        $schema,
    );
    _init_registrations_context(
        $c,
        $context,
        $schema,
        $c->stash->{provisioning_templates}->{$template},
    );
    _create_registrations(
        $c,
        $context,
        $schema,
    );
    _init_trusted_sources_context(
        $c,
        $context,
        $schema,
        $c->stash->{provisioning_templates}->{$template},
    );
    _create_trusted_sources(
        $c,
        $context,
        $schema,
    );

    #die();
    $guard->commit;

    $c->log->debug("provisioning template $template done: " . $context->{subscriber}->{username} . '@' . $context->{domain}->{domain});

}

sub provision_finish {

    my %params = @_;
    my ($c,
        $context) = @params{qw/
            c
            context
        /};

    if (exists $context->{dfrd}->{kamailio_trusted_reload}
        and $context->{dfrd}->{kamailio_trusted_reload} > 0) {
        my (undef, $xmlrpc_res) = NGCP::Panel::Utils::Kamailio::trusted_reload($c);
        delete $context->{dfrd}->{kamailio_trusted_reload};
    }

    if (exists $context->{dfrd}->{kamailio_flush}
        and $context->{dfrd}->{kamailio_flush} > 0) {
        NGCP::Panel::Utils::Kamailio::flush($c);
        delete $context->{dfrd}->{kamailio_flush};
    }

}

sub _init_row_context {

    my ($c, $context, $schema, $values) = @_;

    delete $context->{contract_contact};
    delete $context->{contract};
    delete $context->{contract_preferences};
    delete $context->{billing_mappings};
    delete $context->{subscriber};
    delete $context->{subscriber_preferences};

    $context->{registrations} = [];
    $context->{trusted_sources} = [];

    delete $context->{reseller};
    delete $context->{billing_profile};
    delete $context->{profile_package};
    delete $context->{domain};
    delete $context->{provisioning_domain};
    delete $context->{product};

    delete $context->{cp};
    delete $context->{cs};

    delete $context->{row};

    my $fields = _get_fields($c,1);
    my %row = ();
    $row{sip_username} = _generate_username(10);
    $row{sip_password} = String::MkPasswd::mkpasswd(
        -length => 12,
        -minnum => 1, -minlower => 1, -minupper => 1, -minspecial => 1,
        -distribute => 1, -fatal => 1,
    );
    $row{web_username} = _generate_username(10);
    $row{web_password} = String::MkPasswd::mkpasswd(
        -length => 12,
        -minnum => 1, -minlower => 1, -minupper => 1, -minspecial => 1,
        -distribute => 1, -fatal => 1,
    );
    %row = (%row, %$values);
    $context->{row} = \%row;
    foreach my $fname (keys %$fields) {
        next if grep { $fname eq $_; } @INIT_FIELD_NAMES;
        my ($k,$v) = _calculate_field($context, $fname, $fields);
        $row{$k} = $v;
    }

    $c->log->debug("provisioning template - row: " . Dumper($context->{row}));

}

sub _init_contract_context {

    my ($c, $context, $schema, $template) = @_;

    if (exists $template->{contract_contact}) {
        my %contract_contact = ();
        my @identifiers = _get_identifiers($template->{contract_contact});
        foreach my $col (keys %{$template->{contract_contact}}) { #no inter-field dependecy
            next if $col eq $IDENTIFIER_FNAME;
            my ($k,$v) = _calculate($context,$col, $template->{contract_contact}->{$col});
            $contract_contact{$k} = $v;
        }
        if (exists $contract_contact{reseller}) {
            $context->{r_c} //= {};
            if (exists $context->{r_c}->{$contract_contact{reseller}}
                or ($context->{r_c}->{$contract_contact{reseller}} = $schema->resultset('resellers')->search_rs({
                name => $contract_contact{reseller},
                status => { '!=' => 'terminated' },
            })->first)) {
                $contract_contact{reseller_id} = $context->{r_c}->{$contract_contact{reseller}}->id;
                $context->{reseller} = { $context->{r_c}->{$contract_contact{reseller}}->get_inflated_columns };
            } else {
                die("unknown reseller $contract_contact{reseller}");
            }
            delete $contract_contact{reseller};
        }
        $context->{contract_contact} = \%contract_contact;
        if (scalar @identifiers) {
            if (my $e = $schema->resultset('contacts')->search_rs({
                    map { $_ => $contract_contact{$_}; } @identifiers
                })->first) {
                $contract_contact{id} = $e->id;
            } else {
                delete $contract_contact{id};
            }
        } else {
            delete $contract_contact{id};
        }
        $contract_contact{create_timestamp} //= $context->{now};
        $contract_contact{modify_timestamp} //= $context->{now};
        if (exists $contract_contact{timezone} and $contract_contact{timezone}) {
            die("invalid timezone $contract_contact{timezone}") unless DateTime::TimeZone->is_valid_name($contract_contact{timezone});
        }

        $c->log->debug("provisioning template - contract contact: " . Dumper($context->{contract_contact}));
    }

    {
        my %contract = ();
        my @identifiers = _get_identifiers($template->{contract});
        foreach my $col (keys %{$template->{contract}}) {
            next if $col eq $IDENTIFIER_FNAME;
            my ($k,$v) = _calculate($context,$col, $template->{contract}->{$col});
            $contract{$k} = $v;
        }
        if (exists $contract{profile_package}) {
            $context->{pp_c} //= {};
            if (exists $context->{pp_c}->{$contract{profile_package}}
                or ($context->{pp_c}->{$contract{profile_package}} = $schema->resultset('profile_packages')->search_rs({
                name => $contract{profile_package},
                #reseller_id
                #status => { '!=' => 'terminated' },
            })->first)) {
                $contract{profile_package_id} = $context->{pp_c}->{$contract{profile_package}}->id;
                $context->{profile_package} = { $context->{pp_c}->{$contract{profile_package}}->get_inflated_columns };
            } else {
                die("unknown profile package $contract{profile_package}");
            }
            delete $contract{profile_package};
        }
        if (exists $contract{billing_profile}) {
            $context->{bp_c} //= {};
            if (exists $context->{bp_c}->{$contract{billing_profile}}
                or ($context->{bp_c}->{$contract{billing_profile}} = $schema->resultset('billing_profiles')->search_rs({
                name => $contract{billing_profile},
                #todo: reseller_id
                status => { '!=' => 'terminated' },
            })->first)) {
                $contract{billing_profile_id} = $context->{bp_c}->{$contract{billing_profile}}->id;
                $context->{billing_profile} = { $context->{bp_c}->{$contract{billing_profile}}->get_inflated_columns };
            } else {
                die("unknown billing profile $contract{billing_profile}");
            }
            delete $contract{billing_profile};
        }
        if (exists $contract{product}) {
            $context->{pr_c} //= {};
            if (exists $context->{pr_c}->{$contract{product}}
                or ($context->{pr_c}->{$contract{product}} = $schema->resultset('products')->search_rs({
                name => $contract{product},
            })->first)) {
                $contract{product_id} = $context->{pr_c}->{$contract{product}}->id;
                $context->{product} = { $context->{pr_c}->{$contract{product}}->get_inflated_columns };
            } else {
                die("unknown product $contract{product}");
            }
            delete $contract{product};
        }
        #todo: subscriber_email_template_id
        #todo: passreset_email_template_id
        #todo: invoice_email_template_id
        #todo: invoice_template_id

        $context->{contract} = \%contract;
        if (scalar @identifiers) {
            if (my $e = $schema->resultset('contracts')->search_rs({
                    map { $_ => $contract{$_}; } @identifiers
                })->first) {
                $contract{id} = $e->id;
            } else {
                delete $contract{id};
            }
        } else {
            delete $contract{id};
        }
        $contract{create_timestamp} //= $context->{now};
        $contract{modify_timestamp} //= $context->{now};

        $context->{billing_mappings} = [];
        NGCP::Panel::Utils::BillingMappings::prepare_billing_mappings(
            c => $c,
            resource => $context->{contract},
            old_resource => undef,
            mappings_to_create => $context->{billing_mappings},
            err_code => sub {
                my ($err) = @_;
                die($err);
        });

        $c->log->debug("provisioning template - contract: " . Dumper($context->{contract}));

    }

}

sub _init_subscriber_context {

    my ($c, $context, $schema, $template) = @_;

    {
        my %subscriber = ();
        foreach my $col (keys %{$template->{subscriber}}) {
            my ($k,$v) = _calculate($context,$col, $template->{subscriber}->{$col});
            $subscriber{$k} = $v;
        }
        if (exists $subscriber{domain}) {
            $context->{bd_c} //= {};
            if (exists $context->{bd_c}->{$subscriber{domain}}
                or ($context->{bd_c}->{$subscriber{domain}} = $schema->resultset('domains')->search_rs({
                    domain => $subscriber{domain},
                    #todo: reseller_id
                    #status => { '!=' => 'terminated' },
            })->first)) {
                $subscriber{domain_id} = $context->{bd_c}->{$subscriber{domain}}->id;
                $context->{domain} = { $context->{bd_c}->{$subscriber{domain}}->get_inflated_columns };
                $context->{provisioning_domain} = { $schema->resultset('voip_domains')->find(
                    {domain => $subscriber{domain}})->get_inflated_columns };
            } else {
                die("unknown domain $subscriber{domain}");
            }
            delete $subscriber{domain};
        }
        #todo: profile_id
        #todo: profile_set_id

        $context->{subscriber} = \%subscriber;

        $context->{subscriber}->{customer_id} //= $context->{contract}->{id};

        $context->{cs} = NGCP::Panel::Utils::Subscriber::prepare_resource(
            c => $c,
            schema => $schema,
            resource => $context->{subscriber},
            err_code => sub {
                my ($code, $msg) = @_;
                die($msg);
            },
            validate_code => sub {
                my ($r) = @_;
                return 1;
            },
            getcustomer_code => sub {
                my ($cid) = @_;
                return $schema->resultset('contracts')->find($cid);
            },
        );

        $c->log->debug("provisioning template - subscriber: " . Dumper($context->{subscriber}));
    }
}

sub _init_subscriber_preferences_context {

    my ($c, $context, $schema, $template) = @_;

    if (exists $template->{subscriber_preferences}) {
        $context->{cp} = NGCP::Panel::Utils::Preferences::prepare_resource(
            c => $c,
            schema => $schema,
            item => $schema->resultset('voip_subscribers')->find({
                id => $context->{subscriber}->{id},
            }),
            type => 'subscribers',
        );

        my %subscriber_preferences = %{$context->{cp}}; #merge
        foreach my $col (keys %{$template->{subscriber_preferences}}) {
            my ($k,$v) = _calculate($context,$col, $template->{subscriber_preferences}->{$col});
            $subscriber_preferences{$k} = $v;
        }
        $context->{subscriber_preferences} = \%subscriber_preferences;

        $c->log->debug("provisioning template - subscriber preferences: " . Dumper($context->{subscriber_preferences}));
    }


}


sub _init_contract_preferences_context {

    my ($c, $context, $schema, $template) = @_;

    if (exists $template->{contract_preferences}) {
        $context->{cp} = NGCP::Panel::Utils::Preferences::prepare_resource(
            c => $c,
            schema => $schema,
            item => $schema->resultset('contracts')->find({
                id => $context->{contract}->{id},
            }),
            type => 'contracts',
        );

        my %contract_preferences = %{$context->{cp}}; #merge
        foreach my $col (keys %{$template->{contract_preferences}}) {
            my ($k,$v) = _calculate($context,$col, $template->{contract_preferences}->{$col});
            $contract_preferences{$k} = $v;
        }
        $context->{contract_preferences} = \%contract_preferences;

        $c->log->debug("provisioning template - contract preferences: " . Dumper($context->{contract_preferences}));

    }


}

sub _init_registrations_context {

    my ($c, $context, $schema, $template) = @_;

    foreach my $template_registration (@{$template->{registrations} // []}) {
        my %registration = ();
        foreach my $col (keys %$template_registration) {
            my ($k,$v) = _calculate($context,$col, $template_registration->{$col});
            $registration{$k} = $v;
        }

        push(@{$context->{registrations}}, \%registration);

        $registration{flags} = 0;
        $registration{cflags} = 0;
        $registration{cflags} |= 64 if($registration{nat});

    }

    $c->log->debug("provisioning template - registrations: " . Dumper($context->{registrations}));

}

sub _init_trusted_sources_context {

    my ($c, $context, $schema, $template) = @_;

    my $subscriber = $schema->resultset('voip_subscribers')->find({
        id => $context->{subscriber}->{id},
    });

    foreach my $template_trusted_source (@{$template->{trusted_sources} // []}) {
        my %trusted_source = ();
        foreach my $col (keys %$template_trusted_source) {
            my ($k,$v) = _calculate($context,$col, $template_trusted_source->{$col});
            $trusted_source{$k} = $v;
        }

        push(@{$context->{trusted_sources}}, \%trusted_source);

        $trusted_source{subscriber_id} = $subscriber->provisioning_voip_subscriber->id;
        $trusted_source{uuid} = $subscriber->uuid;

    }

    $c->log->debug("provisioning template - trusted sources: " . Dumper($context->{trusted_sources}));

}


sub _create_contract_contact {

    my ($c, $context, $schema) = @_;

    unless ($context->{contract_contact}->{id}) {
        my $contact = $schema->resultset('contacts')->create(
            $context->{contract_contact},
        );
        $context->{contract_contact}->{id} = $contact->id;
        #$context->{contract}->{contact_id} = $context->{contract_contact}->{id};

        $c->log->debug("provisioning template - contract contact id $context->{contract_contact}->{id} created");
    }

}

sub _create_contract {

    my ($c, $context, $schema) = @_;

    unless ($context->{contract}->{id}) {
        $context->{contract}->{contact_id} //= $context->{contract_contact}->{id};
        die("contact_id for contract required") unless $context->{contract}->{contact_id};
        my $contract = $schema->resultset('contracts')->create(
            $context->{contract},
        );
        $context->{contract}->{id} = $contract->id;
        NGCP::Panel::Utils::BillingMappings::append_billing_mappings(c => $c,
            contract => $contract,
            mappings_to_create => $context->{billing_mappings},
        );
        NGCP::Panel::Utils::ProfilePackages::create_initial_contract_balances(c => $c,
             contract => $contract,
        );
        $c->log->debug("provisioning template - contract id $context->{contract}->{id} created");
    }

}

sub _create_subscriber {

    my ($c, $context, $schema) = @_;

    my $error_info = { extended => {} };

    my @events_to_create = ();
    my $event_context = { events_to_create => \@events_to_create };
    my $subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
        c             => $c,
        schema        => $schema,
        contract      => $context->{cs}->{customer},
        params        => $context->{cs}->{resource},
        preferences   => $context->{cs}->{preferences},
        admin_default => 0,
        event_context => $event_context,
        error         => $error_info,
    );
    $context->{subscriber}->{id} = $subscriber->id;
    if($context->{cs}->{resource}->{status} eq 'locked') {
        NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
            c => $c,
            prov_subscriber => $subscriber->provisioning_voip_subscriber,
            level => $context->{cs}->{resource}->{lock} || 4,
        );
    } else {
        NGCP::Panel::Utils::ProfilePackages::underrun_lock_subscriber(c => $c, subscriber => $subscriber);
    }
    NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
        c              => $c,
        schema         => $schema,
        alias_numbers  => $context->{cs}->{alias_numbers},
        reseller_id    => $context->{cs}->{customer}->contact->reseller_id,
        subscriber_id  => $subscriber->id,
    );
    $subscriber->discard_changes; # reload row because of new number
    NGCP::Panel::Utils::Subscriber::manage_pbx_groups(
        c            => $c,
        schema       => $schema,
        groups       => $context->{cs}->{groups},
        groupmembers => $context->{cs}->{groupmembers},
        customer     => $context->{cs}->{customer},
        subscriber   => $subscriber,
    );
    NGCP::Panel::Utils::Events::insert_deferred(
        c => $c, schema => $schema,
        events_to_create => \@events_to_create,
    );

    $c->log->debug("provisioning template - subscriber id $context->{subscriber}->{id} created");

}

sub _create_subscriber_preferences {

    my ($c, $context, $schema) = @_;

    if (exists $context->{subscriber_preferences}) {
        NGCP::Panel::Utils::Preferences::update_preferences(
            c => $c,
            schema => $schema,
            item => $schema->resultset('voip_subscribers')->find({
                id => $context->{subscriber}->{id},
            }),
            old_resource => $context->{cp},
            resource => $context->{subscriber_preferences},
            type => 'subscribers',
            replace => 0,
            err_code => sub {
                my ($code, $msg) = @_;
                die($msg);
            },
        );
    }

}

sub _create_contract_preferences {

    my ($c, $context, $schema) = @_;

    if (exists $context->{contract_preferences}) {
        NGCP::Panel::Utils::Preferences::update_preferences(
            c => $c,
            schema => $schema,
            item => $schema->resultset('contracts')->find({
                id => $context->{contract}->{id},
            }),
            old_resource => $context->{cp},
            resource => $context->{contract_preferences},
            type => 'contracts',
            replace => 0,
            err_code => sub {
                my ($code, $msg) = @_;
                die($msg);
            },
        );
    }

}

sub _create_registrations {

    my ($c, $context, $schema) = @_;

    my $subscriber = $schema->resultset('voip_subscribers')->find({
        id => $context->{subscriber}->{id},
    });

    foreach my $registration (@{$context->{registrations}}) {
        my $ret = NGCP::Panel::Utils::Kamailio::create_location($c,
            $subscriber->provisioning_voip_subscriber,
            $registration
        );
        die("failed to create registration") unless $ret->[0]->[1];
        $context->{dfrd}->{kamailio_flush} //= 0;
        $context->{dfrd}->{kamailio_flush} += 1;
    }

}

sub _create_trusted_sources {

    my ($c, $context, $schema) = @_;

    foreach my $trusted_source (@{$context->{trusted_sources}}) {
        $schema->resultset('voip_trusted_sources')->create($trusted_source);
        $context->{dfrd}->{kamailio_trusted_reload} //= 0;
        $context->{dfrd}->{kamailio_trusted_reload} += 1;
    }

}

sub _calculate_field {

    my ($context,$fname,$fields) = @_;
    my ($f, $col, $cr) = ($fields->{$fname}, undef, undef);
    if (exists $f->{$FIELD_VALUE_ATTRIBUTE}) {
        ($col, $cr) = ($fname, $f->{$FIELD_VALUE_ATTRIBUTE});
    } elsif (exists $f->{$FIELD_VALUE_ATTRIBUTE . $CODE_SUFFIX_FNAME}) {
        ($col, $cr) = ($fname . $CODE_SUFFIX_FNAME, $f->{$FIELD_VALUE_ATTRIBUTE . $CODE_SUFFIX_FNAME});
    }
    return _calculate($context, $col, $cr);
}

sub _calculate {

    my ($context,$f,$c) = @_;
    $context->{cr_c} //= {};
    if ($f =~ /^([a-z0-9_]+)$CODE_SUFFIX_FNAME$/) {
        my $cl;
        if ($strict_closure) {
            $cl = eval_closure(
                source      => $c,
                environment => {
                    map { if ('ARRAY' eq ref $context->{$_}) {
                            ('@' . $_) => $context->{$_};
                          } elsif ('HASH' eq ref $context->{$_}) {
                            ('%' . $_) => $context->{$_};
                          } elsif ('CODE' eq ref $context->{$_}) {
                            ('&' . $_) => $context->{$_};
                          } elsif (ref $context->{$_}) {
                            ('$' . $_) => \$context->{$_};
                          } else {
                            ('$' . $_) => \$context->{$_};
                          } } keys %$context
                },
                terse_error => 0,
                description => $f,
                alias => 0,
            );
        } else {
            if (exists $context->{cr_c}->{$c}) {
                $cl = $context->{cr_c}->{$c};
            } else {
                ## no critic (BuiltinFunctions::ProhibitStringyEval)
                #$context->{cr_c}->{$c} = eval(decode_base64($c));
                $cl = eval($c);
                $context->{cr_c}->{$c} = $cl;
            }
        }
        die("$f: " . $@) if $@;
        my $v;
        eval {
            $v = $cl->($context);
        };
        if ($@) {
            die("$f: " . $@);
        }
        return ($1 => $v);
    } elsif ('HASH' eq ref $c) {
        my %data = ();
        foreach my $col (keys %$c) {
            my ($k,$v) = _calculate($context,$col, $c->{$col});
            $data{$k} = $v;
        }
        return ($f => \%data);
    } elsif ('ARRAY' eq ref $c) {
        my @data = ();
        my $i = 0;
        foreach my $el (@$c) {
            my ($k,$v) = _calculate($context, $f . '[' . $i . ']', $el);
            push(@data,$v);
            $i++;
        }
        return ($f => \@data);
    } else {
        return ($f => $c);
    }

}

sub _generate_username {

    my ($length, @chars) = @_;
    return unless $length;
    @chars = ("A".."Z", "a".."z", "0".."9") unless scalar @chars;
    my $username = '';
    $username .= $chars[rand @chars] for 1..$length;
    return $username;

}

sub _get_fields {

    my ($c, $calculated) = @_;
    my $template = $c->stash->{provisioning_template_name};
    my %fields = ();
    my $fields_tied = tie(%fields, 'Tie::IxHash');
    foreach my $f (@{$c->stash->{provisioning_templates}->{$template}->{fields} // []}) {
        next unless ($f->{$FIELD_TYPE_ATTRIBUTE} =~ /calculated/i ? $calculated : not $calculated);
        $fields{$f->{name}} = { %$f };
    }
    return \%fields;

}

sub _get_duplicate_subs {

    my ($c, $context, $schema, $e, $get) = @_;
    my $idx;
    my $val;
    my $msg;
    my $subscriber;
    if ($e =~ /Duplicate entry '([^']+)' for key '([^']+)'/) {
        $idx = $2;
        $val = $1;
    }
    if ($idx and 'number_idx' eq $idx) {
        $msg = "number already exists: $e";
        if ($get) {
            $c->log->debug("provisioning template - $msg");
            my %flt;
            @flt{qw(cc ac sn)} = split(/-/,$val);
            $subscriber = $c->model('DB')->resultset('voip_numbers')->find({
                %flt
            })->subscriber;
        }
    } elsif (not $idx or ($idx and 'user_dom_idx' eq $idx)) {
        $msg = "username already exists: $e";
        if ($get) {
            $c->log->debug("provisioning template - $msg");
            $subscriber = $schema->resultset('provisioning_voip_subscribers')->find({
                username => $context->{subscriber}->{username},
                domain_id => $context->{provisioning_domain}->{id},
            })->voip_subscriber;
        }
    } elsif ($idx and 'webuser_dom_idx' eq $idx) {
        $msg = "webusername already exists: $e";
        if ($get) {
            $c->log->debug("provisioning template - $msg");
            $subscriber = $schema->resultset('provisioning_voip_subscribers')->find({
                webusername => $context->{subscriber}->{webusername},
                domain_id => $context->{provisioning_domain}->{id},
            })->voip_subscriber;
        }
    } else {
        $msg = "$e";
    }

    return ($msg, $subscriber);

}

sub _get_identifiers {

    my ($template_item) = @_;
    my $identifier = (exists $template_item->{$IDENTIFIER_FNAME} ? $template_item->{$IDENTIFIER_FNAME} : undef);
    my @identifiers = ();
    if (length($identifier)) {
        @identifiers = map { $_ =~ s/^\s|\s$//gr; } split(/[,; \t]+/,$identifier);
    }
    return @identifiers;

}

1;