package NGCP::Panel::Utils::ProvisioningTemplates;

use Sipwise::Base;

use NGCP::Panel::Form::ProvisioningTemplate::ProvisioningTemplate qw();
use DateTime::TimeZone qw();
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
use YAML::XS qw();
use NGCP::Panel::Utils::DateTime qw();
use NGCP::Panel::Utils::BillingMappings qw();
use NGCP::Panel::Utils::Contract qw();
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::Subscriber qw();
use NGCP::Panel::Utils::Preferences qw();
use NGCP::Panel::Utils::Kamailio qw();
use NGCP::Panel::Utils::CallForwards qw();

use JE::Destroyer qw();
use JE qw();
use JSON qw();
use NGCP::Panel::Utils::Generic qw(escape_js);

my $IDENTIFIER_FNAME = 'identifier';
my $CODE_SUFFIX_FNAME = '_code';
my $FIELD_TYPE_ATTRIBUTE = 'type';
my $FIELD_VALUE_ATTRIBUTE = 'value';
my @INIT_FIELD_NAMES = qw(cc_ac_map default_cc);
my $PURGE_FIELD_NAME = 'purge';

my $JE_ANON_CLASS = 'je_anon';
sub je_anon::TO_JSON {
    return _unbless(@_);
};
my $STRICT_CLOSURE = 1;

my @DISABLED_CORE_FUNCTIONS = qw(
    binmode close closedir dbmclose dbmopen eof fileno flock format getc read
    readdir rewinddir say seek seekdir select syscall sysread sysseek
    syswrite tell telldir truncate write print printf

    chdir chmod chown chroot fcntl glob ioctl link lstat mkdir open opendir readlink
    rename rmdir stat symlink sysopen umask unlink utime

    alarm exec fork getpgrp getppid getpriority kill pipe setpgrp setpriority sleep
    system times wait waitpid

    accept bind connect getpeername getsockname getsockopt listen recv send setsockopt
    shutdown socket socketpair

    msgctl msgget msgrcv msgsnd semctl semget semop shmctl shmget shmread shmwrite

    endgrent endhostent endnetent endpwent getgrent getgrgid getgrnam getlogin getpwent
    getpwnam getpwuid setgrent setpwent

    endprotoent endservent gethostbyaddr gethostbyname gethostent getnetbyaddr
    getnetbyname getnetent getprotobyname getprotobynumber getprotoent getservbyname
    getservbyport getservent sethostent setnetent setprotoent setservent

    exit goto
);

my @SUPPORTED_LANGS = qw(perl js);

my $PERL_ENV = 'use subs qw(' . join(' ', @DISABLED_CORE_FUNCTIONS) . ");\n";
foreach my $sub (@DISABLED_CORE_FUNCTIONS) {
    $PERL_ENV .= 'sub ' . $sub . " { die('$sub called'); }\n";
}

my $JS_ENV = '';

sub load_template_map {

    my $c = shift;
    my $templates = { %{$c->config->{provisioning_templates} // {}} };
    map {
        $templates->{$_}->{name} = $_;
        $templates->{$_}->{static} = 1;
        $templates->{$_}->{id} = undef;
        $templates->{$_}->{reseller} = undef;
    } keys %$templates;

    my $rs = $c->model('DB')->resultset('provisioning_templates')->search_rs();
    if($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
    } elsif($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $rs = $rs->search_rs({ -or => [
                                reseller_id => $c->user->reseller_id,
                                reseller_id => undef
                             ], },);
    } else {
        $rs = $rs->search_rs({ -or => [
                                reseller_id => $c->user->contract->contact->reseller_id,
                                reseller_id => undef
                             ], },);
    }
    $c->stash->{template_rs} = $rs;
    foreach my $db_template ($rs->all) {
        my $template = { $db_template->get_inflated_columns };
        eval {
            %$template = ( %{parse_template($c, $template->{id}, $template->{name}, $template->{yaml})}, %$template );
            #use Data::Dumper;
            #$c->log->error(Dumper($template));
            delete $template->{yaml};
        };
        if ($@) {
            die $@;
            next;
        }
        $template->{static} = 0;
        if ($db_template->reseller) {
            $template->{reseller} = $db_template->reseller->name;
            $templates->{$template->{reseller} . '/' . $template->{name}} = $template;
        } else {
            $templates->{$template->{name}} = $template;
        }
    }
    $c->stash->{provisioning_templates} = $templates;

}

sub validate_template {

    my ($data,$prefix) = @_;
    $prefix //= 'template: ';
    die($prefix . "not a hash\n") unless 'HASH' eq ref $data;
    foreach my $section (qw/contract subscriber/) {
        die($prefix . "section '$section' required\n") unless exists $data->{$section};
        die($prefix . "section '$section' is not a hash\n") unless 'HASH' eq ref $data->{$section};
    }

}

sub validate_template_name {

    my ($c,$name,$old_name,$reseller,$old_reseller) = @_;
    unless ($name =~ /^[a-zA-Z0-9 -]+$/) {
        die("template name contains invalid characters\n");
    }

    if (not defined $old_name
        or $old_name ne $name) {
        unless ($c->stash->{provisioning_templates}) {
            load_template_map($c);
        }
        die("a provisioning template with name '" . $name . "' already exists\n")
            if exists $c->stash->{provisioning_templates}->{$reseller ? ($reseller->name . '/' . $name) : $name};
    }

}

sub dump_template {

    my ($c,$id,$name,$template) = @_;
    my $yaml;
    eval {
        $yaml = YAML::XS::Dump($template);
    };
    if ($@) {
        $c->log->error("error parsing provisioning_template id $id '$name': " . $@) if $c;
        die($@);
    }
    return $yaml;

}

sub parse_template {

    my ($c,$id,$name,$yaml) = @_;
    my $template;
    #die ("yaml: " . $yaml);
    eval {
        $template = YAML::XS::Load($yaml);
    };
    if ($@) {
        $c->log->error("error parsing provisioning_template id $id '$name': " . $@) if $c;
        die($@);
    }
    return $template;

}

sub get_provisioning_template_form {

    my ($c,$fields) = @_;
    $fields //= get_fields($c,0);
    my $form = NGCP::Panel::Form::ProvisioningTemplate::ProvisioningTemplate->new({
        ctx => $c,
        fields_config => [ values %$fields ],
    });
    $form->create_structure([ keys %$fields ]);
    return $form;

}

sub create_provisioning_template_form {

    my %params = @_;
    my ($c,
        $base_uri) = @params{qw/
            c
            base_uri
        /};

    my $template = $c->stash->{provisioning_template_name};

    my $fields = get_fields($c,0);
    my $form;

    try {
        $form = get_provisioning_template_form($c,$fields);
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
        my $context;
        try {
            $context = provision_begin(
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
            provision_cleanup($c, $context);
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
    my $fields = get_fields($c,0);
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

    my $template = $c->stash->{provisioning_template_name};
    my $schema = $c->model('DB');
    $schema->set_transaction_isolation('READ COMMITTED');

    my $context = {};
    $context->{_dfrd} = {};
    $context->{_purge} = $purge // 0;

    my $fields = get_fields($c,1);
    my $init_values = {};
    foreach my $fname (@INIT_FIELD_NAMES) {
        next unless exists $fields->{$fname};
        my ($k,$v) = _calculate_field($init_values, $fname, $fields);
        $init_values->{$k} = $v;
    }

    my %subs = ();

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
        $subs{split_number} = sub {
            my ($dn) = @_;
            $dn //= '';
            $dn = '' . $dn; #force JE:: unboxing
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

            return bless { ac => $ac, cc => $cc, sn => $sn, }, $JE_ANON_CLASS;
        };
    }

    foreach my $sub (qw(debug info warn error)) {
        $subs{$sub} = sub {
            return $c->log->$sub(( map { ($_ // '') . ''; } @_));
        };
    }

    _switch_lang(
        $context,
        $context->{_lang} = $c->stash->{provisioning_templates}->{$template}->{lang},
        perl => sub {
            $context->{now} = NGCP::Panel::Utils::DateTime::current_local();
            $context->{schema} = $schema;
            @{$context}{keys %subs} = values %subs;
        },
        js => sub {
            $context->{_je} = JE->new();
            $context->{_je}->eval($JS_ENV . "\nvar _func;\nvar now = new Date('" .
                NGCP::Panel::Utils::DateTime::current_local() . "');\n");
            $subs{'quotemeta'} = sub {
                return quotemeta(_unbox_je_value(shift @_));
            };
            $subs{'sprintf'} = sub {
                return sprintf(_unbox_je_value(shift @_), map {
                    _unbox_je_value($_);
                } @_);
            };
            while (each %subs) {
                $context->{_je}->new_function($_ => $subs{$_});
            }
            $context->{_je_env} = {};
        }
    );

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

    my $purge = $context->{_purge} || $values->{$PURGE_FIELD_NAME};

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
        if ($purge && $subscriber) {
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
    } catch($e where { /Subscriber already exists/ }) {
        my ($msg, $subscriber) = _get_duplicate_subs(
            $c,
            $context,
            $schema,
            $e,
            $purge,
        );
        if ($purge && $subscriber) {
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
    } catch($e where { /alias '([^']+)' already exists/ }) {
        my ($msg, $subscriber) = _get_duplicate_subs(
            $c,
            $context,
            $schema,
            $e,
            $purge,
        );
        if ($purge && $subscriber && scalar @$subscriber) {
            foreach (@$subscriber) {
                $subscriber = $_;
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
    _init_cf_mappings_context(
        $c,
        $context,
        $schema,
        $c->stash->{provisioning_templates}->{$template},
    );
    _create_cf_mappings(
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

    provision_cleanup($c, $context);

    if (exists $context->{_dfrd}->{kamailio_trusted_reload}
        and $context->{_dfrd}->{kamailio_trusted_reload} > 0) {
        my (undef, $xmlrpc_res) = NGCP::Panel::Utils::Kamailio::trusted_reload($c);
        delete $context->{_dfrd}->{kamailio_trusted_reload};
    }

    if (exists $context->{_dfrd}->{kamailio_flush}
        and $context->{_dfrd}->{kamailio_flush} > 0) {
        NGCP::Panel::Utils::Kamailio::flush($c);
        delete $context->{_dfrd}->{kamailio_flush};
    }

}

sub provision_cleanup {

    my ($c, $context) = @_;

    return unless $context;

    if ($context->{_je}) {
        JE::Destroyer::destroy($context->{_je}); # break circular refs
        undef $context->{_je};
        undef $context->{_je_env};
    }

}

sub _init_row_context {

    my ($c, $context, $schema, $values) = @_;

    delete $context->{contract_contact};
    delete $context->{contract};
    delete $context->{contract_preferences};
    delete $context->{subscriber};
    delete $context->{subscriber_preferences};

    $context->{registrations} = [];
    $context->{trusted_sources} = [];
    delete $context->{cf_mappings};

    delete $context->{reseller};
    delete $context->{billing_profile};
    delete $context->{profile_package};
    delete $context->{domain};
    delete $context->{provisioning_domain};
    delete $context->{product};

    delete $context->{_bm};
    delete $context->{_cp};
    delete $context->{_cs};

    delete $context->{row};

    my $fields = get_fields($c,1);
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
        foreach my $col (keys %{$template->{contract_contact}}) { #no inter-field dependency
            next if $col eq $IDENTIFIER_FNAME;
            my ($k,$v) = _calculate($context,$col, $template->{contract_contact}->{$col});
            $contract_contact{$k} = $v;
        }
        if (exists $contract_contact{reseller}) {
            $context->{_r_c} //= {};
            if (exists $context->{_r_c}->{$contract_contact{reseller}}
                or ($context->{_r_c}->{$contract_contact{reseller}} = $schema->resultset('resellers')->search_rs({
                name => $contract_contact{reseller},
                status => { '!=' => 'terminated' },
            })->first)) {
                $contract_contact{reseller_id} = $context->{_r_c}->{$contract_contact{reseller}}->id;
                $context->{reseller} = { $context->{_r_c}->{$contract_contact{reseller}}->get_inflated_columns };
            } else {
                die("unknown reseller $contract_contact{reseller}");
            }
            delete $contract_contact{reseller};
        }
        $context->{contract_contact} = \%contract_contact;
        if (scalar @identifiers) {
            my $e = $schema->resultset('contacts')->search_rs({
                map { $_ => $contract_contact{$_}; } @identifiers
            })->first;
            if ($e and 'terminated' ne $e->status) {
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
            $context->{_pp_c} //= {};
            if (exists $context->{_pp_c}->{$contract{profile_package}}
                or ($context->{_pp_c}->{$contract{profile_package}} = $schema->resultset('profile_packages')->search_rs({
                name => $contract{profile_package},
                #reseller_id
                #status => { '!=' => 'terminated' },
            })->first)) {
                $contract{profile_package_id} = $context->{_pp_c}->{$contract{profile_package}}->id;
                $context->{profile_package} = { $context->{_pp_c}->{$contract{profile_package}}->get_inflated_columns };
            } else {
                die("unknown profile package $contract{profile_package}");
            }
            delete $contract{profile_package};
        }
        if (exists $contract{billing_profile}) {
            $context->{_bp_c} //= {};
            if (exists $context->{_bp_c}->{$contract{billing_profile}}
                or ($context->{_bp_c}->{$contract{billing_profile}} = $schema->resultset('billing_profiles')->search_rs({
                name => $contract{billing_profile},
                #todo: reseller_id
                status => { '!=' => 'terminated' },
            })->first)) {
                $contract{billing_profile_id} = $context->{_bp_c}->{$contract{billing_profile}}->id;
                $context->{billing_profile} = { $context->{_bp_c}->{$contract{billing_profile}}->get_inflated_columns };
            } else {
                die("unknown billing profile $contract{billing_profile}");
            }
            delete $contract{billing_profile};
        }
        if (exists $contract{product}) {
            $context->{_pr_c} //= {};
            if (exists $context->{_pr_c}->{$contract{product}}
                or ($context->{_pr_c}->{$contract{product}} = $schema->resultset('products')->search_rs({
                name => $contract{product},
            })->first)) {
                $contract{product_id} = $context->{_pr_c}->{$contract{product}}->id;
                $context->{product} = { $context->{_pr_c}->{$contract{product}}->get_inflated_columns };
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
            my $e = $schema->resultset('contracts')->search_rs({
                map { $_ => $contract{$_}; } @identifiers
            })->first;
            if ($e and 'terminated' ne $e->status) {
                $contract{id} = $e->id;
            } else {
                delete $contract{id};
            }
        } else {
            delete $contract{id};
        }
        $contract{create_timestamp} //= $context->{now};
        $contract{modify_timestamp} //= $context->{now};

        $context->{_bm} = [];
        NGCP::Panel::Utils::BillingMappings::prepare_billing_mappings(
            c => $c,
            resource => $context->{contract},
            old_resource => undef,
            mappings_to_create => $context->{_bm},
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
        my @identifiers = _get_identifiers($template->{subscriber});
        my %subscriber = ();
        foreach my $col (keys %{$template->{subscriber}}) {
            next if $col eq $IDENTIFIER_FNAME;
            my ($k,$v) = _calculate($context,$col, $template->{subscriber}->{$col});
            $subscriber{$k} = $v;
        }
        if (exists $subscriber{domain}) {
            $context->{_bd_c} //= {};
            if (exists $context->{_bd_c}->{$subscriber{domain}}
                or ($context->{_bd_c}->{$subscriber{domain}} = $schema->resultset('domains')->search_rs({
                    domain => $subscriber{domain},
                    #todo: reseller_id
                    #status => { '!=' => 'terminated' },
            })->first)) {
                $subscriber{domain_id} = $context->{_bd_c}->{$subscriber{domain}}->id;
                $context->{domain} = { $context->{_bd_c}->{$subscriber{domain}}->get_inflated_columns };
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
        
        my $item;
        if (scalar @identifiers) {
            $item = $schema->resultset('voip_subscribers')->search_rs({
                map { $_ => $subscriber{$_}; } @identifiers
            },{
                join => 'domain',
            })->first;
            if ($item and 'terminated' ne $item->status) {
                $subscriber{id} = $item->id;
            } else {
                delete $subscriber{id};
            }
        } else {
            delete $subscriber{id};
        }

        $context->{subscriber}->{customer_id} //= $context->{contract}->{id};

        $context->{_cs} = NGCP::Panel::Utils::Subscriber::prepare_resource(
            c => $c,
            schema => $schema,
            resource => $context->{subscriber},
            err_code => sub {
                my ($code, $msg) = @_;
                die($msg);
            },
            validate_code => sub {
                my ($res) = @_;
                #todo
                return 1;
            },
            getcustomer_code => sub {
                my ($cid) = @_;
                my $contract = $schema->resultset('contracts')->find($cid);
                NGCP::Panel::Utils::Contract::acquire_contract_rowlocks(
                    schema => $schema, contract_id => $contract->id) if $contract;
                return $contract;
            },
            item => $item,
        );

        $c->log->debug("provisioning template - subscriber: " . Dumper($context->{subscriber}));
    }
}

sub _init_subscriber_preferences_context {

    my ($c, $context, $schema, $template) = @_;

    if (exists $template->{subscriber_preferences}) {
        $context->{_cp} = NGCP::Panel::Utils::Preferences::prepare_resource(
            c => $c,
            schema => $schema,
            item => $schema->resultset('voip_subscribers')->find({
                id => $context->{subscriber}->{id},
            }),
            type => 'subscribers',
        );

        my %subscriber_preferences = %{$context->{_cp}}; #merge
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
        
        $context->{_cp} = NGCP::Panel::Utils::Preferences::prepare_resource(
            c => $c,
            schema => $schema,
            item => $schema->resultset('contracts')->find({
                id => $context->{contract}->{id},
            }),
            type => 'contracts',
        );

        my %contract_preferences = %{$context->{_cp}}; #merge
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

    foreach my $template_registration (@{_force_array($template->{registrations})}) {
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

    foreach my $template_trusted_source (@{_force_array($template->{trusted_sources})}) {
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

sub _init_cf_mappings_context {

    my ($c, $context, $schema, $template) = @_;

    if (exists $template->{cf_mappings}) {   
        my %cf_mappings = ();
        foreach my $col (keys %{$template->{cf_mappings}}) {
            my ($k,$v) = _calculate($context,$col, $template->{cf_mappings}->{$col});
            $cf_mappings{$k} = $v;
        }
    
        $context->{cf_mappings} = \%cf_mappings;
    
        $c->log->debug("provisioning template - cf mappings: " . Dumper($context->{cf_mappings}));
    }

}

sub _create_contract_contact {

    my ($c, $context, $schema) = @_;

    unless ($context->{contract_contact}->{id}) {
        my $contact = $schema->resultset('contacts')->create(
            $context->{contract_contact},
        );
        $context->{contract_contact}->{id} = $contact->id;

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
            mappings_to_create => $context->{_bm},
        );
        NGCP::Panel::Utils::ProfilePackages::create_initial_contract_balances(c => $c,
             contract => $contract,
        );
        $c->log->debug("provisioning template - contract id $context->{contract}->{id} created");
    }

}

sub _create_subscriber {

    my ($c, $context, $schema) = @_;

    unless ($context->{subscriber}->{id}) {
        my $error_info = { extended => {} };
    
        my @events_to_create = ();
        my $event_context = { events_to_create => \@events_to_create };
        my $subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
            c             => $c,
            schema        => $schema,
            contract      => $context->{_cs}->{customer},
            params        => $context->{_cs}->{resource},
            preferences   => $context->{_cs}->{preferences},
            admin_default => 0,
            event_context => $event_context,
            error         => $error_info,
        );
        $context->{subscriber}->{id} = $subscriber->id;
        if($context->{_cs}->{resource}->{status} eq 'locked') {
            NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                c => $c,
                prov_subscriber => $subscriber->provisioning_voip_subscriber,
                level => $context->{_cs}->{resource}->{lock} || 4,
            );
        } else {
            NGCP::Panel::Utils::ProfilePackages::underrun_lock_subscriber(c => $c, subscriber => $subscriber);
        }
        NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
            c              => $c,
            schema         => $schema,
            alias_numbers  => $context->{_cs}->{alias_numbers},
            reseller_id    => $context->{_cs}->{customer}->contact->reseller_id,
            subscriber_id  => $subscriber->id,
        );
        $subscriber->discard_changes; # reload row because of new number
        NGCP::Panel::Utils::Subscriber::manage_pbx_groups(
            c            => $c,
            schema       => $schema,
            groups       => $context->{_cs}->{groups},
            groupmembers => $context->{_cs}->{groupmembers},
            customer     => $context->{_cs}->{customer},
            subscriber   => $subscriber,
        );
        NGCP::Panel::Utils::Events::insert_deferred(
            c => $c, schema => $schema,
            events_to_create => \@events_to_create,
        );
    
        $c->log->debug("provisioning template - subscriber id $context->{subscriber}->{id} created");
    }
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
            old_resource => $context->{_cp},
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
            old_resource => $context->{_cp},
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
        $context->{_dfrd}->{kamailio_flush} //= 0;
        $context->{_dfrd}->{kamailio_flush} += 1;
    }

}

sub _create_trusted_sources {

    my ($c, $context, $schema) = @_;

    foreach my $trusted_source (@{$context->{trusted_sources}}) {
        $schema->resultset('voip_trusted_sources')->create($trusted_source);
        $context->{_dfrd}->{kamailio_trusted_reload} //= 0;
        $context->{_dfrd}->{kamailio_trusted_reload} += 1;
    }

}

sub _create_cf_mappings {

    my ($c, $context, $schema) = @_;
    
    if (exists $context->{cf_mappings}) {
        my $subscriber = $schema->resultset('voip_subscribers')->find({
            id => $context->{subscriber}->{id},
        });
        
        $subscriber = NGCP::Panel::Utils::CallForwards::update_cf_mappings(
            c => $c,
            resource => $context->{cf_mappings},
            item => $subscriber,
            err_code => sub {
                my ($msg) = @_;
                die($msg);
            },
            validate_mapping_code => sub {
                my $res = shift;
                #todo
                return 1;
                #return $self->validate_form(
                #    c => $c,
                #    form => $form,
                #    resource => $res,
                #);
            },
            validate_destination_set_code => sub {
                my $res = shift;
                #todo
                return 1;
                #return $self->validate_form(
                #    c => $c,
                #    form => NGCP::Panel::Role::API::CFDestinationSets->get_form($c),
                #    resource => $res,
                #);
            },
            validate_time_set_code => sub {
                my $res = shift;
                #todo
                return 1;
                #return $self->validate_form(
                #    c => $c,
                #    form => NGCP::Panel::Role::API::CFTimeSets->get_form($c),
                #    resource => $res,
                #);
            },
            validate_source_set_code => sub {
                my $res = shift;
                #todo
                return 1;
                #return $self->validate_form(
                #    c => $c,
                #    form => NGCP::Panel::Role::API::CFSourceSets->get_form($c),
                #    resource => $res,
                #);
            },
            validate_bnumber_set_code => sub {
                my $res = shift;
                #todo
                return 1;
                #return $self->validate_form(
                #    c => $c,
                #    form => NGCP::Panel::Role::API::CFBNumberSets->get_form($c),
                #    resource => $res,
                #);
            },
            params => undef,
        );
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
    if ($f =~ /^([a-z0-9_]+)$CODE_SUFFIX_FNAME$/) {
        return _switch_lang(
            $context,
            $context->{_lang},
            perl => sub {
                my $cl;
                if ($STRICT_CLOSURE) {
                    $cl = eval_closure(
                        source      => ($PERL_ENV . $c),
                        environment => {
                            map { if ('ARRAY' eq ref $context->{$_}) {
                                    ('@' . $_) => $context->{$_};
                                  } elsif ('HASH' eq ref $context->{$_}) {
                                    ('%' . $_) => $context->{$_};
                                  } elsif ($JE_ANON_CLASS eq ref $context->{$_}) {
                                    ('%' . $_) => _unbless($context->{$_});
                                  } elsif ('CODE' eq ref $context->{$_}) {
                                    ('&' . $_) => $context->{$_};
                                  } elsif (ref $context->{$_}) {
                                    ('$' . $_) => \$context->{$_};
                                  } else {
                                    ('$' . $_) => \$context->{$_};
                                  } } grep { substr($_,0,1) ne '_'; } keys %$context
                        },
                        terse_error => 0,
                        description => $f,
                        alias => 0,
                    );
                } else {
                    $context->{_cr_c} //= {};
                    if (exists $context->{_cr_c}->{$c}) {
                        $cl = $context->{_cr_c}->{$c};
                    } else {
                        ## no critic (BuiltinFunctions::ProhibitStringyEval)
                        $cl = eval($PERL_ENV . $c);
                        $context->{_cr_c}->{$c} = $cl;
                    }
                }
                die("$f: " . $@) if $@;
                my $v;
                eval {
                    $v = $cl->($context);
                    $v = _unbless($v) if ($v and $JE_ANON_CLASS eq ref $v);
                };
                if ($@) {
                    die("$f: " . $@);
                }
                return ($1 => $v);
            },
            js => sub {

                $context->{_je}->eval(join (";\n",
                    map { if ('CODE' eq ref $context->{$_}) {
                        die('no coderefs allowed');
                    } elsif (('ARRAY' eq ref $context->{$_})
                        or ('HASH' eq ref $context->{$_})
                        or ($JE_ANON_CLASS eq ref $context->{$_})) {
                    if ($context->{_je_env}->{$_}) {
                        $_ . ' = ' . _to_json($context->{$_});
                    } else { $context->{_je_env}->{$_} = 1;
                        'var ' . $_ . ' = ' . _to_json($context->{$_}); }
                    } elsif (ref $context->{$_}) {
                        die('no refs allowed');
                    } else { if ($context->{_je_env}->{$_}) {
                        $_ . " = '" . escape_js($context->{$_}) . "'";
                    } else { $context->{_je_env}->{$_} = 1;
                        'var ' . $_ . " = '" . escape_js($context->{$_}) . "'"; }
                    } } grep { substr($_,0,1) ne '_'; } keys %$context) .
                    ";\n_func = $c;");
                die("$f: " . $@) if $@;
                my $v;
                eval {
                    $v = _unbox_je_value($context->{_je}->eval('_func();'));
                };
                if ($@) {
                    die("$f: " . $@);
                }
                return ($1 => $v);

            }
        );
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

sub _unbox_je_value {

    my $v = shift;
    return unless defined $v;
    if ((ref $v) =~ /^JE::/) {
        $v = $v->value;
    } elsif ($JE_ANON_CLASS eq ref $v) {
        $v = _unbless($v);
    }
    if ('ARRAY' eq ref $v) {
        return [ map { _unbox_je_value($_); } @$v ];
    } elsif ('HASH' eq ref $v) {
        return { map { $_ => _unbox_je_value($v->{$_}); } keys %$v };
    } else {
        return $v;
    }

}

sub _unbless {
    my $obj = shift;
    return { %$obj }; #unbless
};

sub _to_json {
    return JSON::to_json(shift, {
        allow_nonref => 1, allow_blessed => 1,
        convert_blessed => 1, pretty => 0 });
}

sub _generate_username {

    my ($length, @chars) = @_;
    return unless $length;
    @chars = ("A".."Z", "a".."z", "0".."9") unless scalar @chars;
    my $username = '';
    $username .= $chars[rand @chars] for 1..$length;
    return $username;

}

sub get_fields {

    my ($c, $calculated) = @_;
    my $template = $c->stash->{provisioning_template_name};
    my %fields = ();
    my $fields_tied = tie(%fields, 'Tie::IxHash');
    foreach my $f (@{_force_array($c->stash->{provisioning_templates}->{$template}->{fields})}) {
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
    if ($e =~ /alias '([^']+)' already exists/) {
        $val = $1;
        $msg = $e;
        if ($get) {
            $c->log->debug("provisioning template - $msg");
            my %subs = ();
            foreach my $alias ($c->model('DB')->resultset('voip_dbaliases')->search_rs({
                    username => $val,
                },undef)->all) {
                $subscriber = $alias->subscriber->voip_subscriber;
                $subs{$subscriber->id} = $subscriber unless exists $subs{$subscriber->id};
            }
            $subscriber = [ values %subs ];
        }
    } elsif ($idx and 'number_idx' eq $idx) {
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

sub _switch_lang {

    my ($context, $lang, %code) = @_;

    die('template lang not defined') unless $lang;
    die("unknown template lang '$lang'") unless exists $code{$lang};
    die("template lang '$lang' not supported") unless grep { $_ eq $lang} @SUPPORTED_LANGS;
    return &{$code{$lang}}($context);

}

sub _force_array {
    my $value = shift;
    $value //= [];
    $value = [ $value ] if 'ARRAY' ne ref $value;
    return $value;
}

1;
