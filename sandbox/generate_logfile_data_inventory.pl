use strict;

eval 'use lib "/home/rkrenn/sipwise/git/sipwise-base/lib";';
eval 'use lib "/home/rkrenn/sipwise/git/ngcp-panel/lib";';
eval 'use NGCP::Panel::Utils::Message qw();';
my $panel_util_message_loaded = 1;
if ($@) {
    warn('cannot load NGCP::Panel::Utils::Message');
    $panel_util_message_loaded = 0;
}

use File::Find qw();
use File::Basename qw();
use File::Spec qw();
use YAML::XS;

my @perlfileextensions = ('.pl','.pm');
my $rperlextensions = join('|',map { quotemeta($_); } @perlfileextensions);

my $root = "/home/rkrenn/sipwise/git/ngcp-panel/";
my @dirstoskip = ();
push @dirstoskip,$root."sandbox/";

my @filestoskip = ();
push @filestoskip,$root."lib/NGCP/Panel/Utils/Message.pm";

my %dirsdone;
my %mock_objs = ();
my %result = (
    'panel-debug.log' => [],
    'api.log' => [],
    'panel.log' => [],
);
my $messages_count;
my $invocations_count;
my %distinct_variables;
my $extracted_message = undef;
my $is_sensitive = 0;
my $message_role = undef;

scancatalystlog();
scanmessageslog();
write_ymls();
exit();

sub scancatalystlog {

    $messages_count = 0;
    $invocations_count = 0;
    %dirsdone = ();
    %distinct_variables = ();
    File::Find::find({ wanted => \&scancatalystlog_dir_names, follow => 1 }, $root);
    print "scan for \$c->log:\n  method invocations: $invocations_count\n  identified messages: $messages_count\n  distinct variables: " . (scalar keys %distinct_variables) . "\n";

}

sub scancatalystlog_dir_names {

    _scandirs(sub {
        my $dir = shift;
        _scandirfiles($dir,0,sub {
            my ($line,$inputfilename,$inputfiledir,$inputfilesuffix,$next_line) = @_;
            if ($line =~ /->log(\(\))?->(debug|info|warn|error|fatal)/
                and substr(_trim($line),0,1) ne '#') {
                my $method = $2;
                my $source_file_name = _get_source_file_name($inputfilename,$inputfiledir,$inputfilesuffix);
                my $message = _trim($line);
                $message =~ s/^\$.+->log(\(\))?->$method\(//;
                $message =~ s/(\s*#.+)?$//;
                while ($message !~ /;$/) {
                    my $next_line = &$next_line();
                    next if substr(_trim($next_line),0,1) eq '#';
                    $next_line = _trim($next_line);
                    $next_line =~ s/(\s*#.+)?$//;
                    $message .= $next_line;
                }
                $message =~ s/\)(\s+(if|unless)[^;]+)?;(\s*#.+)?$//;
                _dispatch_logfile(_list_variables({
                    gdpr_status => ($message =~ /->qs\(/ ? 2 : 0),
                    level => $method,
                    log_line => $message,
                    source_file => $source_file_name,
                }));
                #print $message . "\n";
                $messages_count++;
                $invocations_count++;
            }
            return 1;
        });
    });

}

sub scanmessageslog {

    $messages_count = 0;
    $invocations_count = 0;
    %dirsdone = ();
    %distinct_variables = ();
    File::Find::find({ wanted => \&scanmessageslog_dir_names, follow => 1 }, $root);
    print "scan for NGCP::Panel::Utils::Message:\n  method invocations: $invocations_count\n  identified messages: $messages_count\n  distinct variables: " . (scalar keys %distinct_variables) . "\n";

}

sub scanmessageslog_dir_names {

    _scandirs(sub {
        my $dir = shift;
        _scandirfiles($dir,1,sub {
            my ($data_ref,$inputfilename,$inputfiledir,$inputfilesuffix) = @_;
            while ($$data_ref =~ /((\s*#\s*)?NGCP::Panel::Utils::Message::(info|error)\([^;]+\)(\s+(if|unless)[^;]+)?;)/gm) {
                my $line = $1;
                my $method = $3;
                next if substr(_trim($line),0,1) eq '#';
                $line =~ s/^NGCP::Panel::Utils::Message::(info|error)\(/{/m;
                $line =~ s/\)(\s+(if|unless)[^;]+)?;/}/m;
                my $source_file_name = _get_source_file_name($inputfilename,$inputfiledir,$inputfilesuffix);
                my %messages = _extract_messages($line,$method);
                foreach my $message (keys %messages) {
                    _dispatch_logfile(_list_variables({
                        gdpr_status => ($messages{$message} ? 2 : 0),
                        level => $method,
                        log_line => $message,
                        source_file => $source_file_name,
                    }));
                    $messages_count++;
                    #print $count . ". " . $message . "\n\n";
                }
                $invocations_count++;
            }
        });
    });

}

sub _scandirs {

    my ($scandirfiles_code) = @_;
    my $path = $File::Find::dir;
    if (-d $path) {
        my $dir = $path . '/';
        if (not $dirsdone{$dir}
            and not scalar grep { substr($dir, 0, length($_)) eq $_; } @dirstoskip) {
            &$scandirfiles_code($dir);
        }
        $dirsdone{$dir} = 1;
    }
}

sub _scandirfiles {

    my ($inputdir,$slurp,$code) = @_;

    local *DIR;
    if (not opendir(DIR, $inputdir)) {
        die('cannot opendir ' . $inputdir . ': ' . $!);
    }
    my @files = grep { /$rperlextensions$/ && -f $inputdir . $_} readdir(DIR);
    closedir DIR;
    return unless (scalar @files) > 0;
    foreach my $file (@files) {
        my $inputfilepath = $inputdir . $file;
        next if grep { $_ eq $inputfilepath; } @filestoskip;
        my ($inputfilename,$inputfiledir,$inputfilesuffix) = File::Basename::fileparse($inputfilepath, $rperlextensions);
        local *FILE;
        if (not open (FILE,'<' . $inputfilepath)) {
            die('cannot open file ' . $inputfilepath . ': ' . $!);
        }
        if ($slurp) {
            my $line_terminator = $/;
            $/ = undef;
            my $data = <FILE>;
            &$code(\$data,$inputfilename,$inputfiledir,$inputfilesuffix);
            $/ = $line_terminator;
        } else {
            while (<FILE>) {
                last unless &$code($_,$inputfilename,$inputfiledir,$inputfilesuffix, sub {
                    <FILE>;
                });
            }
        }
        close(FILE);
    }

}

sub _trim {
    my $str = shift;
    $str =~ s/^\s+//g;
    $str =~ s/\s+$//g;
    return $str;
}

sub _extract_messages {
    my ($message_invocation,$method) = @_;
    my %dupe_results = ();
    foreach my $vector (_generate_combinations(
        [
            { role => 'subscriber' },
        ],[
           { e => '$e' },
        ],[
           { error => undef },
           { error => '$error' },
           { error => _create_mock('error',
                _error => '$error->{error}',
                _description => '$error->{description}',
                _create_sub_mock('type'),
                _create_sub_mock('info'),
            ) },
        ],
    )) {
        my %vector = map { %{$_}; } @$vector;
        my $args = _deserialize_messagesargs($message_invocation,%vector);
        if ($args and _run_message($method,$args,%vector)) {
            if ($extracted_message
                and index($extracted_message,'=HASH(0x') < 0) { # filter out nonsense vector stringifications
                $dupe_results{$extracted_message} = $dupe_results{$extracted_message} || $is_sensitive;
            }
        }
    }
    return %dupe_results;
}

sub _run_message {
    my $method = shift;
    my $args = shift;
    my %_params = @_;
    ($message_role) = @_params{qw/
        role
    /};
    $extracted_message = undef;
    $is_sensitive = 0;
    $args->{flash} = 0;
    $args->{stash} = 0;
    $args->{c} = _create_mock('_c',
        _stash => {

        },
        stash => sub {
            my $self = shift;
            my $key = shift;
            return $self->{stash}->{$key} if $key;
            return $self->{stash};
        },
        user => sub {
            my $self = shift;
            return _create_mock('_user',
                roles => sub {
                    my $self = shift;
                    return $message_role;
                },
                webusername => sub {
                    my $self = shift;
                    return '$c->user->webusername';
                },
                domain => sub {
                    my $self = shift;
                    return _create_mock('_domain',
                        domain => sub {
                            my $self = shift;
                            return '$c->user->domain->domain';
                        },
                    );
                },
            );
        },
        user_exists => sub {
            my $self = shift;
            return 1;
        },
        qs => sub {
            my $self = shift;
            my $str = shift;
            $is_sensitive = 1;
            return "<<" . $str . ">>" if $str;
        },
        request => sub {
            my $self = shift;
            return _create_mock('_request',
        #        _params => {
        #            '$c->request->params' => undef,
        #        },
        #        params => sub {
        #            my $self = shift;
        #            #return $self->{params}->{$key} if $key;
        #            return $self->{params};
        #        },
                method => sub {
                    my $self = shift;
                    return '$c->request->method';
                },
                path => sub {
                    my $self = shift;
                    return '$c->request->path';
                },
                address => sub {
                    my $self = shift;
                    return '$c->request->address';
                },
                query_params => sub {
                    my $self = shift;
                    return { '$c->request->query_params' => undef, };
                },
                parameters => sub {
                    my $self = shift;
                    return { '$c->request->parameters' => undef, };
                },
            );
        },
        response => sub {
            my $self = shift;
            return _create_mock('_response',
                code => sub {
                    my $self = shift;
                    return 999; #'$c->response->code';
                },
            );
        },
        _session => {
            api_request_tx_id => '$c->{session}->{api_request_tx_id}',
        },
        session => sub {
            my $self = shift;
            my $key = shift;
            return $self->{session}->{$key} if $key;
            return $self->{session};
        },
        _config => {
            security => {
                log_passwords => 0,
            },
        },
        config => sub {
            my $self = shift;
            #my $key = shift;
            #return $self->{config}->{$key} if $key;
            return $self->{config};
        },
        log => sub {
            my $self = shift;
            return _create_mock('_log',
                error => sub {
                    my $self = shift;
                    $extracted_message = shift; #global closure needed!
                },
                info => sub {
                    my $self = shift;
                    $extracted_message = shift; #global closure needed!
                },
            );
        },
    );
    eval {
        no strict "refs";  ## no critic (ProhibitNoStrict)
        "NGCP::Panel::Utils::Message::$method"->(%$args);
    };

    if ($@) {
        warn($@);
        return 0;
    } else {
        return 1;
    }

}

sub _deserialize_messagesargs {

    my $_line = shift;
    my %_params = @_;
    (   my $e,
        my $error
    ) = @_params{qw/
        e
        error
    /};

    my $subscriber = _create_mock('subscriber',
        _create_sub_mock('get_inflated_columns'),
        _create_sub_mock('username'),
        _create_sub_mock('uuid'),
        _create_sub_mock('id'),
        contact => sub {
            my $self = shift;
            return _create_mock('contact',_create_sub_mock('email'),);
        },
        domain => sub {
            my $self = shift;
            return _create_mock('domain',_create_sub_mock('domain'),);
        },
    );
    my $contact = _create_mock('contact',
        _create_sub_mock('get_inflated_columns'),
        _create_sub_mock('email'),
    );
    my $contract = _create_mock('contract',
        _create_sub_mock('get_inflated_columns'),
        _create_sub_mock('max_subscribers'),
        _create_sub_mock('id'),
    );
    my $s = $subscriber;
    my $invoice = _create_mock('invoice',
        _create_sub_mock('get_inflated_columns'),
        _create_sub_mock('id'),
    );
    my $pbx_device = _create_mock('pbx_device',
        _create_sub_mock('get_inflated_columns'),
        _create_sub_mock('id'),
    );
    my $c = _create_mock('c',
        _stash => {
            body => '$c->{stash}->{body}',
            hm_rule_result => _create_mock('hm_rule_result',_create_sub_mock('get_inflated_columns'),),
            hm_condition_result => _create_mock('hm_condition_result',_create_sub_mock('get_inflated_columns'),),
            hm_action_result => _create_mock('hm_action_result',_create_sub_mock('get_inflated_columns'),),
            subscriber => $subscriber,
            voicemail => _create_mock('voicemail',_create_sub_mock('get_inflated_columns'),),
            recording => _create_mock('recording',_create_sub_mock('id'),),
            registered => _create_mock('registered',_create_sub_mock('get_inflated_columns'),),
            trusted => _create_mock('trusted',_create_sub_mock('get_inflated_columns'),),
            speeddial => _create_mock('speeddial',_create_sub_mock('get_inflated_columns'),),
            autoattendant => _create_mock('autoattendant',_create_sub_mock('get_inflated_columns'),),
            ccmapping => _create_mock('ccmapping',_create_sub_mock('get_inflated_columns'),),
            body => '$c->{stash}->{number}',
            pattern_result => _create_mock('pattern_result',_create_sub_mock('get_inflated_columns'),), #ncos
            lnp_result => _create_mock('lnp_result',_create_sub_mock('get_inflated_columns'),),
            block => _create_mock('block',_create_sub_mock('get_inflated_columns'),),
            phonebook_result => _create_mock('phonebook_result',
                _create_sub_mock('id'),
                _create_sub_mock('get_inflated_columns'),),
            devmod => _create_mock('devmod',
                _create_sub_mock('id'),
                _create_sub_mock('model'),
                _create_sub_mock('vendor'),
                ),
            devfw => _create_mock('devfw',
                _create_sub_mock('id'),
                _create_sub_mock('get_inflated_columns'),),
            devconf => _create_mock('devconf',
                _create_sub_mock('id'),
                _create_sub_mock('get_inflated_columns'),),
            devprof => _create_mock('devprof',
                _create_sub_mock('id'),
                _create_sub_mock('get_inflated_columns'),),
            preference_meta => _create_mock('preference_meta',
                _create_sub_mock('id'),
                _create_sub_mock('attribute'),),
            inv => $invoice,
            sup => _create_mock('sup',_create_sub_mock('get_inflated_columns'),),
            domain_result => _create_mock('domain_result', _create_sub_mock('get_inflated_columns'),),
            set_result => _create_mock('set_result', _create_sub_mock('get_inflated_columns'),),
            rule_result => _create_mock('rule_result', _create_sub_mock('get_inflated_columns'),),
            voucher_result => _create_mock('voucher_result', _create_sub_mock('id'),),
            administrator => _create_mock('administrator',_create_sub_mock('get_inflated_columns'),),
            profile => _create_mock('profile', #profile set
                _id => '$c->{stash}->{profile}->{id}',
                _create_sub_mock('get_inflated_columns'),),
            contract => $contract,
            pbx_device => $pbx_device,
            tmpl => _create_mock('tmpl',_create_sub_mock('get_inflated_columns'),),
            hm_set_result => _create_mock('hm_set_result',_create_sub_mock('get_inflated_columns'),),
            set => _create_mock('set', _create_sub_mock('get_inflated_columns'),), #profile set
            mcid_res => _create_mock('mcid_res', _create_sub_mock('id'),),
            contact => $contact,
            server_result => _create_mock('server_result', _create_sub_mock('get_inflated_columns'),), #peering
            rule_result => _create_mock('rule_result', _create_sub_mock('get_inflated_columns'),), #peering
            group_result => _create_mock('group_result', _create_sub_mock('get_inflated_columns'),), #peering
            inbound_rule_result => _create_mock('inbound_rule_result', _create_sub_mock('get_inflated_columns'),), #peering
            file_result => _create_mock('file_result', _create_sub_mock('get_inflated_columns'),),
        },
        stash => sub {
            my $self = shift;
            my $key = shift;
            return $self->{stash}->{$key} if $key;
            return $self->{stash};
        },
        loc => sub {
            my $self = shift;
            my $str = shift;
            my @params = @_;
            for (my $i = 1; $i <= scalar @params; $i++) {
                my $subst = quotemeta("[_$i]");
                my $repl = $params[$i - 1];
                $str =~ s/$subst/$repl/g;
            }
            return $str;
        },
        qs => sub {
            my $self = shift;
            my $str = shift;
            $is_sensitive = 1;
            return "<<" . $str . ">>" if $str;
        },
        user => sub {
            my $self = shift;
            return _create_mock('user',
                _create_sub_mock('id'),
                _create_sub_mock('account_id'),
                _create_sub_mock('uuid'),);
        },
        request => sub {
            my $self = shift;
            return _create_mock('request',
                _params => {
                    '$c->request->params' => undef,
                },
                params => sub {
                    my $self = shift;
                    #return $self->{params}->{$key} if $key;
                    return $self->{params};
                },
            );
        },
    );
    #my $e = '$e';
    my $msg = '$msg';
    my $vars = {
       invoice => '$vars->{invoice}',
    };
    #my $error = _create_mock('error',
    #    _error => '$error->{error}',
    #    _description => '$error->{description}',
    #    _create_sub_mock('type'),
    #    _create_sub_mock('info'),
    #);
    my %log_data = ('%log_data' => undef, );
    my $text = \'$text';
    my $text_success = \'$text_success';
    my $response_body = '$response_body';
    my $params_data = '$params_data';
    my $attribute = '$attribute';
    my $subscriber_id = '$subscriber_id';
    my $set = _create_mock('set', _create_sub_mock('get_inflated_columns'),);
    my $pref_id = '$pref_id';
    my $cf_type = '$cf_type';
    my $type = '$type'; #voicemail greeting type
    my $vm_id = '$vm_id';
    my $rec_id = '$rec_id';
    my $stream_id = '$stream_id';
    my $data = '$data';
    my $reg_id = '$reg_id';
    my $trusted_id = '$trusted_id';
    my $rws_id = '$rws_id';
    my $sd_id = '$sd_id';
    my $aa_id = '$aa_id';
    my $phonebook_id = '$phonebook_id';
    my $carrier_id = '$carrier_id';
    my $number_id = '$number_id'; #lnp
    my $form = _create_mock('form',
        _values => {
            lnp_provider_id => '$form->{values}->{lnp_provider_id}',
            name => '$form->{values}->{name}',
            emergency_container_id => '$form->{values}->{emergency_container_id}',
            code => '$form->{values}->{code}',
        },
        values => sub {
            my $self = shift;
            my $key = shift;
            return $self->{values}->{$key} if $key;
            return $self->{values};
        },
    );
    my $ip = '$ip'; #banned
    my $user = '$user'; #banned
    my $contract_id = '$contract_id';
    my $devmod_id = '$devmod_id';
    my $devfw_id = '$devfw_id';
    my $devconf_id = '$devconf_id';
    my $devprof_id = '$devprof_id';
    my $emergency_container_id = '$emergency_container_id';
    my $emergency_mapping_id = '$emergency_mapping_id';
    my $reseller_id = '$reseller_id';
    my $domain_id = '$domain_id';
    my $network_id = '$network_id';
    my $voucher_id = '$voucher_id';
    my $administrator_id = '$administrator_id';
    my $message = '$message';
    my $special_user_login = '$special_user_login';
    my $result = '$result'; #certificate
    my $reseller = _create_mock('reseller', _create_sub_mock('get_inflated_columns'),);
    my %defaults = (
        admins => {
            login => '$defaults{admins}->{login}',
        },
    );
    my $default_pass = '$default_pass';
    my $timeset_id = '$timeset_id';
    my $package_id = '$package_id';
    my $profile_id = '$profile_id';
    my $fee_id = '$fee_id';
    my $zone_id = '$zone_id';
    my $zone_info = '$zone_info';
    my $weekday_id = '$weekday_id';
    my $rs = _create_mock('rs', _create_sub_mock('get_inflated_columns'),); #timerange rs
    my $special_id = '$special_id';
    my $special_result_info = '$special_result_info';
    my $product = '$product';
    my $uri = '$uri';
    my $fraud_prefs = _create_mock('fraud_prefs', _create_sub_mock('get_inflated_columns'),);
    my $group_id = '$group_id'; #pbx group id
    my $dev_id = '$dev_id';
    my $line = _create_mock('line',
        field => sub {
            my $self = shift;
            my $field = shift;
            return _create_mock('field',
                _create_sub_mock('value'),);
        },
    );
    my %hm_rule_columns = ('%hm_rule_columns' => undef);
    my @out = ('@out');
    my $location_id = '$location_id';
    my $contact_id = '$contact_id';
    my $group_name = '$group_name'; #app server
    use Data::Dumper;
    my $args = eval $_line;
    if ($@) {
        warn($_line ."\n" .$@);
        return undef;
    } else {
        return $args;
    }

}

sub _create_sub_mock {
    my $subname = shift;
    return ($subname,sub {
        my $self = shift;
        return '$' . (ref $self) . '->' . $subname; # . '()'; #(caller(0))[3];
    });
}

sub _create_mock {
    my $class = shift;
    return $mock_objs{$class} if exists $mock_objs{$class};
    my %members = @_;
    my $obj = bless({},$class);
    foreach my $member (keys %members) {
        if ('CODE' eq ref $members{$member}) {
            no strict "refs";  ## no critic (ProhibitNoStrict)
            *{$class.'::'.$member} = $members{$member};
        } else {
            $obj->{substr($member,1)} = $members{$member};
        }
    }
    $mock_objs{$class} = $obj;
    return $obj;
}

#foreach my $x (_generate_combinations([qw(1 2 3)], [qw(a b)], [qw(C D)])) {
#    print join("-",@$x)."\n";
#}

sub _generate_combinations {
    my @arrays = grep @$_, @_;
    my $min = @arrays;
    my @current = ([]);
    for my $array (@arrays) {
        $min++;
        @current = map {
            my $n = $_;
            my @res = map { my $r = [@$n]; push(@$r,$_); $r; } @$array;
            unless (scalar @$n < $min) {
                unshift(@res,$n);
            }
            @res;
        } @current;
    }
    return @current;
}

sub _get_source_file_name {
    my ($inputfilename,$inputfiledir,$inputfilesuffix) = @_;
    my @dirparts = File::Spec->splitdir($inputfiledir);
    return $dirparts[$#dirparts - 1] . '/' . $inputfilename.$inputfilesuffix;
}

sub _list_variables {
    my $log_line = shift;

    my @variables = ();
    #while ($log_line->{log_line} =~ /(\$[^\s:.)'"]+)/gm) {
    while ($log_line->{log_line} =~ /(\$[\$a-zA-Z0-9_>{}-]+)/gm) {
        my $var = $1;
        push(@variables,{
            variable => $var,
            description => '#todo',
        });
        #print $var . "\n" unless exists $distinct_variables{$var};
        $distinct_variables{$var} = 0 unless exists $distinct_variables{$var};
        $distinct_variables{$var} += 1;
    }
    $log_line->{variables} = \@variables if scalar @variables > 0;

    return $log_line;
}

sub _dispatch_logfile {

    my $log_line = shift;
    # see rsyslog.conf:
    #if $programname == 'ngcp-panel' and $msg startswith ' DEBUG'  then {
    #  -/var/log/ngcp/panel-debug.log
    #  stop
    #}
    #
    #if $programname == 'ngcp-panel' and $msg contains 'CALLED=API'  then {
    #  -/var/log/ngcp/api.log
    #  stop
    #}
    #
    #:programname, isequal, "ngcp-panel" {
    #  -/var/log/ngcp/panel.log
    #  stop
    #}
    if ($log_line->{level} eq 'debug') {
        push(@{$result{'panel-debug.log'}},$log_line);
    } elsif (index($log_line->{log_line},'CALLED=API') >= 0) {
        push(@{$result{'api.log'}},$log_line);
        #print $log_line->{log_line} . "\n";
    } else {
        push(@{$result{'panel.log'}},$log_line);
        print $log_line->{log_line} . "\n";
    }

}

sub write_ymls {
    print "log inventory .yml output:\n";
    foreach my $logfile (keys %result) {
        my ($filename,$dir,$suffix) = File::Basename::fileparse($logfile, '.log');
        my $output_filename = $filename.'.yml';
        unlink $output_filename;
        YAML::XS::DumpFile($output_filename, {
            blacklist_pattern => '#todo',
            date => _datestamp(),
            gdpr_status => {
                0 => 'not affected',
                1 => 'potentially affected',
                2 => 'affected',
            },
            log_file => {
                description => $filename . $suffix . ' file generated by ngcp admin -panel and rest-api',
                gdpr_status => 2,
                log_lines => $result{$logfile},
            }
        });
        print "  $output_filename: " . scalar @{$result{$logfile}} . " messages\n";
    }
}

sub _datestamp {

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  return sprintf "%4d-%02d-%02d",$year+1900,$mon+1,$mday;

}