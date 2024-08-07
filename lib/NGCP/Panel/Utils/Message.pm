package NGCP::Panel::Utils::Message;

#use Catalyst;
use Sipwise::Base;
use Data::Dumper;
use DateTime qw();
use DateTime::Format::RFC3339 qw();
use Time::HiRes qw();

sub get_log_params {
    my %params = @_;
    my $c = $params{c};
    my $type = $params{type};
    my $data = $params{data};

    # tx_id
    my $log_tx = DateTime->from_epoch(epoch => Time::HiRes::time);
    my $log_tx_id = sprintf '%X', $log_tx->strftime('%s%N');

    # package and method depending on the request type (normal or api)
    my $called = '';
    if ($type eq 'api_request') {
        $called = sprintf 'API[%s]/%s',
                          $c->request->method,
                          $c->request->path;
        $c->stash->{api_request_tx_id} = $log_tx_id;
    } elsif ($type eq 'api_response') {
        $called = sprintf 'API[%s %d]/%s',
                          $c->request->method,
                          $c->response->code,
                          $c->request->path;
        if ($c->stash->{api_request_tx_id}) {
            $log_tx_id = $c->stash->{api_request_tx_id};
        }
    } elsif ($type eq 'api_retry') {
        $called = sprintf 'API[%s]/%s',
                          $c->request->method,
                          $c->request->path;
        if ($c->stash->{api_request_tx_id}) {
            $log_tx_id = $c->stash->{api_request_tx_id};
        }
    } else {
        my $caller = (caller 2)[3];
        $caller !~ /::/ and $caller = (caller 3)[3];
        if ($caller) {
            my @caller = split(/::/, $caller);
            $#caller >= 3 and $called = join('::', @caller[-3...-1]);
        }
    }

    # remote user
    my $r_user = '';
    my $is_subscriber = 0;
    if ($c->user_exists) {
        if ($c->user->roles eq 'admin' || $c->user->roles eq 'reseller') {
            $r_user = $c->user->login;
        } elsif ($c->user->roles eq 'subscriberadmin' || $c->user->roles eq 'subscriber') {
            $r_user = $c->qs($c->user->webusername . '@' . $c->user->domain->domain);
            $is_subscriber = 1;
        }
    }

    # remote ip
    my $r_ip = $c->request->address;
    $r_ip =~ s/^::ffff://; # ipv4 in ipv6 form -> ipv4
    $r_ip = $c->qs($r_ip) if $is_subscriber;

    # parameters
    my $data_str;
    my $data_ref = ref($data) ? $data :
                    $type eq 'api_request'
                      ? $c->request->query_params
                      : $c->request->parameters;
    if ($data_ref) {
        $data_str = Data::Dumper->new([ obfuscate_password_fields($c,$data_ref) ])
                                ->Terse(1)
                                ->Maxdepth(1)
                                ->Dump;
    } elsif ($data) {
        $data_str = $data;
    }
    if ($data_str) {
        $data_str =~ s/\n//g;
        $data_str =~ s/\s+/ /g;
    } else {
        $data_str = '';
    }
    if (length($data_str) > 100000) {
        # trim long messages
        $data_str = "{ data => 'Msg size is too big' }";
    } else {
        $data_str = $c->qs($data_str);
    }

    return {
                tx_id  => $log_tx_id,
                called => $called,
                r_user => $r_user,
                r_ip   => $r_ip,
                data   => $data_str,
           };
}

sub error {
    my %params = @_;
    my $c = $params{c};
    my $type = $params{type};
    my $data = $params{data};
    my $desc = $params{desc};
    my $cname = $params{cname};
    my $log = $params{log};
    my $error = $params{error};
    $type //= 'panel';
    $desc //= '';

    my $log_params = get_log_params(c => $c,
                                    type => $type,
                                    data => $data, );

    defined $cname and $log_params->{called} =~ s/__ANON__/$cname/;

    my $msg      = ''; # sent to the log file
    my $log_msg  = ''; # optional log info
    my $usr_type = 'error';
    my $usr_text = $desc;

    if (defined $log)
    {
        if (ref($log)) {
            $log_msg = $c->qs(Data::Dumper->new([ obfuscate_password_fields($c,$log) ])
                                   ->Terse(1)
                                   ->Maxdepth(1)
                                   ->Dump);
        } else {
            $log_msg = $log
        }
        $log_msg =~ s/\n//g;
        $log_msg =~ s/\s+/ /g;
    }

    if (not defined $error) {
        $msg = $desc;
    }
    elsif (my ($host) = $error =~ /problem connecting to (\S+, port [0-9]+)/)
    {
        $log_msg  = "$desc ($error)";
        $usr_text = "$desc (A service could not be reached, $host)";
    }
    elsif (ref($error) eq "ARRAY" && @$error >= 2 && $error->[1] eq "showdetails")
    {
        $msg      = "$desc (@$error[0])";
        $usr_text = "$desc (@$error[0])";
    }
    elsif (ref($error) eq "HASH" && $error->{showdetails})
    {
        my $error_msg = $error->{error} ? ' '.$error->{error} : '';
        $msg      = "$desc ($error->{showdetails}$error_msg)";
        $usr_text = "$desc ($error->{showdetails})";
    }
    elsif (not $error->isa('DBIx::Class::Exception'))
    {
        $msg      = "$desc ($error)";
        $usr_text = $desc;
    }
    elsif (my ($dup) = $error =~ /(Duplicate entry \S*)/)
    {
        $msg      = "$desc ($error)";
        $usr_text = "$desc ($dup)";
    }
    elsif (my ($excerpt) = $error =~ /(Column \S+ cannot be null)/)
    {
        $msg      = "$desc ($error)";
        $usr_text = "$desc ($excerpt)";
    }
    else
    {
        $msg = "$desc ($error)";
    }

    my $logstr = 'IP=%s CALLED=%s TX=%s USER=%s DDATA=%s MSG="%s" LOG="%s" DURATION=%f';
    my $rc = $c->log->error(
        sprintf $logstr, @{$log_params}{qw(r_ip called tx_id r_user data)}, $c->qs($msg), $log_msg, (defined $c->stash->{_request_start} ? Time::HiRes::time - $c->stash->{_request_start} : 0));
    if ($type eq 'panel') {
        if (!defined $params{flash} || $params{flash} ) {
            $c->flash(messages => [{ type => $usr_type,
                                 text => sprintf '%s [%s]',
                                            $usr_text,
                                            $log_params->{tx_id},
                                }]);
        }
        if ($params{stash} ) {
            my $messages = $c->stash->{messages} // [];
            push @$messages, { type => $usr_type,
                                 text => sprintf '%s [%s]',
                                            $usr_text,
                                            $log_params->{tx_id},
                                };
            $c->stash(messages => $messages);
        }
        $c->stash(panel_error_message => $msg);
    }
    return $rc;
}

sub info {
    my %params = @_;
    my $c = $params{c};
    my $type = $params{type};
    my $data = $params{data};
    my $desc = $params{desc};
    my $cname = $params{cname};
    my $log = $params{log};
    $type //= 'panel';
    $desc //= '';

    my $log_params = get_log_params(c => $c,
                                    type => $type,
                                    data => $data, );

    defined $cname and $log_params->{called} =~ s/__ANON__/$cname/;

    my $msg      = $desc; # sent to the log file
    my $log_msg  = ''; # optional log info
    my $usr_type = 'info';
    my $usr_text = $desc;

    if (defined $msg) {
        if (ref($msg)) {
            $msg = $c->qs(Data::Dumper->new([ obfuscate_password_fields($c,$log) ])
                                   ->Terse(1)
                                   ->Maxdepth(1)
                                   ->Dump);
        }
        $msg =~ s/\n//g;
        $msg =~ s/\s+/ /g;
    }

    if (defined $log) {
        if (ref($log)) {
            $log_msg = $c->qs(Data::Dumper->new([ obfuscate_password_fields($c,$log) ])
                                   ->Terse(1)
                                   ->Maxdepth(1)
                                   ->Dump);
        } else {
            $log_msg = $log
        }
        $log_msg =~ s/\n//g;
        $log_msg =~ s/\s+/ /g;
    }

    my $logstr = 'IP=%s CALLED=%s TX=%s USER=%s DATA=%s MSG="%s" LOG="%s" DURATION=%f';
    my $rc = $c->log->info(
        sprintf $logstr,
                @{$log_params}{qw(r_ip called tx_id r_user data)}, $msg, $log_msg, (defined $c->stash->{_request_start} ? Time::HiRes::time - $c->stash->{_request_start} : 0));
    if ($type eq 'panel') {
        #flash is on by default
        if (!defined $params{flash} || $params{flash} ) {
            $c->flash(messages => [{ type => $usr_type, text => $usr_text }]);
        }
        if ($params{stash} ) {
            my $messages = $c->stash->{messages} // [];
            push @$messages, { type => $usr_type, text => $usr_text };
            $c->stash(messages => $messages);
        }
    }
    return $rc;
}

sub obfuscate_password_fields {
    my ($c,$data_ref) = @_;
    return $data_ref unless 'HASH' eq ref $data_ref;
    my $log_passwords = $c->config->{security}{log_passwords} || 0;
    my %parsed_data_ref = map {$_ => defined $data_ref->{$_}
        ? length($data_ref->{$_}) > 500
            ? '*too big*'
            : (!$log_passwords && $_ =~ /password/i
                    && $data_ref->{$_})
                ? '*' x 5
                : $data_ref->{$_}
        : 'undef'
      } keys %$data_ref;
    return \%parsed_data_ref;
}

sub obfuscate_body_password_fields {
    my ($c,$body) = @_;
    return $body unless $body;
    return $body unless ref $body;
    return $body if $c->config->{security}{log_passwords};
    if ($body =~ /["']?[a-z0-9_]*password[a-z0-9_]*["']?\s*:\s*["'](.*?)["']\s*,?\s*/gmi) {
        #$c->log->debug($-[1] . ' ' . $+[1]);
        my $result = $body;
        substr($result, $-[1], $+[1] - $-[1], '*' x 5);
        $body = $result;
    }
    return $body;
}

1;

__END__

=encoding UTF-8

=head1 NAME

NGCP::Panel::Utils::Message

=head1 DESCRIPTION

Parse messages for log and Web display.

Usage in the code:

Error:
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to create domain.'),
        );

Info:
        NGCP::Panel::Utils::Message::info(
            c => $c,
            desc => $c->loc('Domain successfully created'),
        );

Check "Params" section for the "error" and the "info" methods for extended usage

Notes:

- If you use the code inside an anonymous function (sub { })
  it will appear in the log as CALLED=....::__ANON__
  you might want to use "$cname" then to specify the caller name
  manually (there is an example in "Params" below).

- If you do not want a message to appear on the GUI
  use "$type => 'internal' (basically anything but 'panel',
  there may be more logic around different types but currently
  there is only a check if ($type eq 'panel') { show on GUI ... })

=head1 INTERFACE

=head2 Functions

=head3 C<get_log_params>

Used by "info" and "error" methods and returns parsed data for logging
- Do not this the method directly -

=head3 C<error>

Shows the error message on the panel. Also logs everything to the logger.

Params:

    $c (required)
    $desc (required) - main log message (will appear on the GUI).
    $log   - additional information that will be added to LOG= only (no GUI).
    $error - error log message, will be parsed and may also appear on the GUI
    $type  - 'panel' by default, means the message will go to both the log and the GUI,
             anything else but 'panel' is written only to the log.
             Expandable with new types if necessary.
             Current types 'panel','internal','api_request','api_response'
    $data  - hash containing what will be written into the DATA= part of the log message
             (by default $c->request->params is used for the data source)
    $cname - Custom function name for CALLED= e.g. Controller::Domain::create
             as the caller and if you need to something else
             $cname => 'custom_create' leads to
             CALLED=Controller:Domain::custom_create in the log

=head3 C<info>

Shows the info message on the panel. Also logs everything to the logger.

Params:

    $c (required)
    $desc (required) - main log message (will appear on the GUI).
    $log   - additional information that will be added to LOG= only (no GUI).
    $type  - 'panel' by default, means the message will go to both the log and the GUI,
             anything else but 'panel' is written only to the log.
             Expandable with new types if necessary.
             Current types 'panel','internal','api_request','api_response'
    $data  - hash containing what will be written into the DATA= part of the log message
             (by default $c->request->params is used for the data source)
    $cname - Custom function name for CALLED= e.g. Controller::Domain::create
             as the caller and if you need to something else
             $cname => 'custom_create' leads to
             CALLED=Controller:Domain::custom_create in the log

=head1 AUTHOR

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.
