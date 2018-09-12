package NGCP::Panel::Controller::Subscriber;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;
use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use HTML::Entities;
use JSON qw(decode_json encode_json);
use URI::Escape qw(uri_unescape);
use Data::Dumper;
use MIME::Base64 qw(encode_base64url decode_base64url);
use File::Slurp qw/read_file/;

use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Datatables;
use NGCP::Panel::Utils::Callflow;
use NGCP::Panel::Utils::CallList;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Fax;
use NGCP::Panel::Utils::Kamailio;
use NGCP::Panel::Utils::Events;
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::Phonebook;

use UUID;

=head1 NAME

NGCP::Panel::Controller::Subscriber - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

#sub auto :Does(ACL) :ACLDetachTo('/denied_page') {
sub auto :Private {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub sub_list :Chained('/') :PathPart('subscriber') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash(
        template => 'subscriber/list.tt',
    );

    $c->stash->{subscribers_rs} = $c->model('DB')->resultset('voip_subscribers')->search({
        'me.status' => { '!=' => 'terminated' },
    });
    if($c->user->roles eq 'reseller') {
        $c->stash->{subscribers_rs} = $c->stash->{subscribers_rs}->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => { 'contract' => 'contact'},
        });
    } elsif($c->user->roles eq 'subscriber') {
        $c->stash->{subscribers_rs} = $c->stash->{subscribers_rs}->search({
            'username' => $c->user->username
        },{
            join => { 'contract' => 'contact'},
        });
        if($c->config->{features}->{multidomain}) {
            $c->stash->{subscribers_rs} = $c->stash->{subscribers_rs}->search({
                'domain.domain' => $c->user->domain->domain,
            },{
                join => 'domain'
            });
        }
    } elsif($c->user->roles eq 'subscriberadmin') {
        $c->stash->{subscribers_rs} = $c->stash->{subscribers_rs}->search({
            'contract.id' => $c->user->account_id,
        },{
            join => { 'contract' => 'contact'},
        });
    }

    $c->stash->{dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "contract_id", search => 1, title => $c->loc('Contract #') },
        { name => "contract.contact.email", search => 1, title => $c->loc('Contact Email') },
        { name => "username", search => 1, title => $c->loc('Username') },
        { name => "domain.domain", search => 1, title => $c->loc('Domain') },
        { name => "uuid", search => 1, title => $c->loc('UUID') },
        { name => "status", search => 1, title => $c->loc('Status') },
        { name => "number", search => 1, title => $c->loc('Number'), literal_sql => "concat(primary_number.cc, primary_number.ac, primary_number.sn)",'join' => 'primary_number'},
        { name => "alias", search => 1, literal_sql => { format => " exists ( select subscriber_id, group_concat(concat(cc,ac,sn)) as aliases from billing.voip_numbers voip_subscriber_aliases_csv where voip_subscriber_aliases_csv.`subscriber_id` = `me`.`id` group by subscriber_id having aliases %s )" } ,'no_column' => 1 },
        { name => "provisioning_voip_subscriber.voip_subscriber_profile.name", search => 1, title => $c->loc('Profile') },
    ]);
}

sub root :Chained('sub_list') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
}

sub base :Chained('sub_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $subscriber_id) = @_;

    unless($subscriber_id && is_int($subscriber_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => "subscriber id '$subscriber_id' is not an integer",
            desc  => $c->loc('Invalid subscriber id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriber'));
    }

    my $res = $c->stash->{subscribers_rs}->find({ id => $subscriber_id });
    unless(defined $res) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => "subscriber id '$subscriber_id' does not exist",
            desc  => $c->loc('Subscriber does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriber'));
    }

    $c->stash(subscriber => $res);

    $c->stash->{contract} = $c->stash->{subscriber}->contract;
    my $contract_rs = NGCP::Panel::Utils::Contract::get_customer_rs(c => $c, contract_id => $c->stash->{contract}->id );
    my $contract = $contract_rs->find({
        'me.id' => $c->stash->{contract}->id,
    });
    unless(defined $contract) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => "subscriber id '$subscriber_id' points to non-existing contract id",
            desc  => $c->loc('Contract does not exist for subscriber'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriber'));
    }
    my $billing_mapping = NGCP::Panel::Utils::BillingMappings::get_actual_billing_mapping(c => $c, contract => $contract );
    $c->stash->{billing_mapping} = $billing_mapping;

    $c->stash->{subscribers} = $c->model('DB')->resultset('voip_subscribers')->search({
        contract_id => $c->stash->{contract}->id,
        status => { '!=' => 'terminated' },
        'provisioning_voip_subscriber.is_pbx_group' => 0,
    }, {
        join => 'provisioning_voip_subscriber',
    });

    $c->stash->{pilot} = $c->stash->{subscribers}->search({
        'provisioning_voip_subscriber.is_pbx_pilot' => 1,
    })->first;

    $c->stash->{sd_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "slot", search => 1, title => $c->loc('Slot') },
        { name => "destination", search => 1, title => $c->loc('Destination') },
    ]);
    $c->stash->{aa_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "choice", search => 1, title => $c->loc('Slot') },
        { name => "destination", search => 1, title => $c->loc('Destination') },
    ]);
    $c->stash->{fax_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "time", search_from_epoch => 1, search_to_epoch => 1, title => $c->loc('Timestamp') },
        { name => "status", search => 1, title => $c->loc('Status') },
        { name => "duration", search => 1, title => $c->loc('Duration') },
        { name => "direction", search => 1, title => $c->loc('Direction') },
        { name => "caller", search => 1, title => $c->loc('Caller') },
        { name => "callee", search => 1, title => $c->loc('Callee') },
        { name => "pages", search => 1, title => $c->loc('Pages') },
    ]);

    $c->stash->{ccmap_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "auth_key", search => 1, title => $c->loc('CLI') },
        { name => "source_uuid", search => 1, title => $c->loc('Source UUID') },
    ]);

    $c->stash->{phonebook_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "name", search => 1, title => $c->loc("Name") },
        { name => "number", search => 1, title => $c->loc("Number") },
        { name => "shared", search => 1, title => $c->loc("Shared") },
    ]);

    if($contract->product->class eq "pbxaccount") {
        $c->stash->{pbx_groups} = NGCP::Panel::Utils::Subscriber::get_pbx_subscribers_rs(
            c => $c,
            schema => $c->model('DB'),
            customer_id => $c->stash->{contract}->id ,
            is_group => 1,
        );
        $c->stash->{subscriber_pbx_items} = NGCP::Panel::Utils::Subscriber::get_subscriber_pbx_items(
            c          => $c,
            schema     => $c->model('DB'),
            subscriber => $c->stash->{subscriber} ,
        ) // [] ;
    }
    $c->stash->{pbx} = NGCP::Panel::Utils::Subscriber::get_subscriber_pbx_status($c, $c->stash->{subscriber});
    $c->stash->{custom_announcements_rs} = $c->model('DB')->resultset('voip_sound_handles')->search({
        'group.name' => 'custom_announcements',
    },{
        join => 'group',
    });

    $c->stash->{phonebook} = $c->stash->{subscriber}->phonebook;
}

sub webfax :Chained('base') :PathPart('webfax') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(
        template => 'subscriber/webfax.tt',
    );
}

sub webfax_send :Chained('base') :PathPart('webfax/send') :Args(0) {
    my ($self, $c) = @_;

    my $subscriber = $c->stash->{subscriber};
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::Webfax", $c);
    my $posted = ($c->request->method eq 'POST');

    my $params = {};
    if($posted) {
         $c->req->params->{faxfile} = $c->req->upload('faxfile');
    }
    $form->process(
        posted => $posted,
        params => $c->req->params,
    );

    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->uri_for_action('/subscriber/webfax', $c->req->captures),
    );

    if($posted && $form->validated) {
        try {
            NGCP::Panel::Utils::Fax::send_fax(
                c => $c,
                subscriber => $subscriber,
                destination => $form->values->{destination},
                quality => $form->values->{quality}, # opt (normal, fine,super)
                #coverpage => $form->values->{coverpage},
                pageheader => $form->values->{pageheader},
                #notify => $form->values->{notify}, # TODO: handle in send_fax, read from prefs!
                #coverpage => 1,
                upload => $form->values->{faxfile},
                data => $form->values->{data},
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => "failed to send fax: $e",
                desc  => $c->loc('Error while sending fax (have the fax settings been configured properly?)'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriber/webfax', $c->req->captures));
        return;
    }

    $c->stash(
        template => 'subscriber/webfax.tt',
        form => $form,
        create_flag => 1,
        close_target => $c->uri_for_action('/subscriber/webfax', [$c->req->captures->[0]]),
    );
}

sub webfax_ajax :Chained('base') :PathPart('webfax/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $subscriber = $c->stash->{subscriber};
    my $fax_rs = $c->model('DB')->resultset('voip_fax_journal')->search({
        'voip_subscriber.id' => $subscriber->id,
    },{
        join => { 'provisioning_voip_subscriber' => 'voip_subscriber' },
    });

    NGCP::Panel::Utils::Datatables::process($c, $fax_rs, $c->stash->{fax_dt_columns},
        sub {
            my ($result) = @_;
            my $resource =
                NGCP::Panel::Utils::Fax::process_fax_journal_item(
                    $c, $result, $subscriber
                );
            return %$resource;
        }
    );

    $c->detach( $c->view("JSON") );
}


sub webphone :Chained('base') :PathPart('webphone') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(template => 'subscriber/webphone.tt');
}

sub webphone_ajax :Chained('base') :PathPart('webphone/ajax') :Args(0) {
    my ($self, $c) = @_;

    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $c->detach('/denied_page')
            unless($c->stash->{subscriber}->contract->contact->reseller_id != $c->user->reseller_id);
    } elsif($c->user->roles eq "subscriberadmin") {
        $c->detach('/denied_page')
            unless($c->stash->{subscriber}->contract_id != $c->user->account_id);
    } else {
    }

    my $subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    # TODO: use from config.yml.
    # Important: ws vs wss (issues with self-signed certs on cross-domain)
    my $config = {
        sip => {
            # wss/5061 vs ws/5060
            ws_servers => 'wss://' . $c->request->uri->host . ':' . $c->request->uri->port . '/wss/sip/',
            uri => 'sip:' . $subscriber->username . '@' . $subscriber->domain->domain,
            password => $subscriber->password,
        },
        xmpp => {
            # wss/5281 vs ws/5280
            # - ws causes "insecure" error in firefox
            # - wss fails if self signed cert is not accepted in firefox/chromium
            wsURL => 'wss://' . $c->request->uri->host . ':' . $c->request->uri->port . '/wss/xmpp/',
            jid => $subscriber->username . '@' . $subscriber->domain->domain,
            server => $subscriber->domain->domain,
            credentials => { password => $subscriber->password },
        },
    };

    $c->stash(aaData => $config);
    $c->detach( $c->view("JSON") );
}

sub ajax :Chained('sub_list') :PathPart('ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{subscribers_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{dt_columns});
    $c->detach( $c->view("JSON") );
}

sub terminate :Chained('base') :PathPart('terminate') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c) = @_;
    my $subscriber = $c->stash->{subscriber};

    if($c->user->roles eq 'subscriberadmin' && $c->user->uuid eq $subscriber->uuid) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => 'unauthorized termination of own subscriber for uuid '.$c->user->uuid,
            desc  => $c->loc('Terminating own subscriber is prohibited.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriber'));
    }

    try {
        NGCP::Panel::Utils::Subscriber::terminate(c => $c, subscriber => $subscriber);
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $subscriber->get_inflated_columns },
            desc => $c->loc('Successfully terminated subscriber'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to terminate subscriber'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriber'));
}

sub reset_webpassword :Chained('base') :PathPart('resetwebpassword') :Args(0) {
    my ($self, $c) = @_;
    my $subscriber = $c->stash->{subscriber};

    if($c->user->roles eq 'subscriberadmin' && $c->user->voip_subscriber->contract_id != $subscriber->contract_id) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => 'unauthorized password reset for subscriber uuid '.$c->user->uuid,
            desc  => $c->loc('Invalid password reset attempt.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriber'));
    }

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            my ($uuid_bin, $uuid_string);
            UUID::generate($uuid_bin);
            UUID::unparse($uuid_bin, $uuid_string);
            $subscriber->password_resets->delete; # clear any old entries of this subscriber

            # if reset from a logged in user, clear old pass (to force setting new one)
            # and let reset link be valid for a year
            $subscriber->provisioning_voip_subscriber->update({
                webpassword => undef,
            });
            $subscriber->password_resets->create({
                uuid => $uuid_string,
                timestamp => NGCP::Panel::Utils::DateTime::current_local->epoch + 31536000,
            });
            my $url = $c->uri_for_action('/subscriber/recover_webpassword')->as_string . '?uuid=' . $uuid_string;
            NGCP::Panel::Utils::Email::password_reset($c, $subscriber, $url);


        });
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            desc => $c->loc('Successfully reset web password, please check your email at [_1]', $subscriber->contact ? $subscriber->contact->email : $subscriber->contract->contact->email),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to reset web password'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriber'));
}

sub reset_webpassword_nosubscriber :Chained('/') :PathPart('resetwebpassword') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        unless($c->config->{security}->{password_allow_recovery});

    my $posted = $c->req->method eq "POST";
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::RecoverPassword", $c);
    my $params = {};
    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my ($user, $domain) = split /\@/, $form->params->{username};
                my $subscriber = $schema->resultset('voip_subscribers')->find({
                    username => $user,
                    'domain.domain' => $domain,
                },{
                    join => 'domain',
                });

                # don't inform about unknown users
                if($subscriber) {
                    # don't clear web password, a user might just have guessed it and
                    # could then block the legit user out
                    my ($uuid_bin, $uuid_string);
                    UUID::generate($uuid_bin);
                    UUID::unparse($uuid_bin, $uuid_string);
                    $subscriber->password_resets->delete; # clear any old entries of this subscriber
                    $subscriber->password_resets->create({
                        uuid => $uuid_string,
                        timestamp => NGCP::Panel::Utils::DateTime::current_local->epoch,
                    });
                    my $url = $c->uri_for_action('/subscriber/recover_webpassword')->as_string . '?uuid=' . $uuid_string;
                    NGCP::Panel::Utils::Email::password_reset($c, $subscriber, $url);
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully reset web password, please check your email'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to reset web password'),
            );
        }
        $c->res->redirect($c->uri_for('/login/subscriber'));
    }

    $c->stash(
        form => $form,
        edit_flag => 1,
        template => 'subscriber/recoverpassword.tt',
        close_target => $c->uri_for('/login/subscriber'),
    );

}

sub recover_webpassword :Chained('/') :PathPart('recoverwebpassword') :Args(0) {
    my ($self, $c) = @_;

    $c->log->debug("++++++++++++++++++++ password recovery attempt");

    $c->user->logout if($c->user);

    my $posted = $c->req->method eq "POST";
    my ($uuid_bin, $uuid_string);
    $uuid_string = $c->req->params->{uuid} // '';

    unless($posted) {
        unless($uuid_string && UUID::parse($uuid_string, $uuid_bin) != -1) {
            $c->log->warn("invalid password recovery attempt for uuid '$uuid_string' from '".$c->req->address."'");
            $c->detach('/denied_page')
        }

        my $rs = $c->model('DB')->resultset('password_resets')->search({
            uuid => $uuid_string,
            timestamp => { '>=' => NGCP::Panel::Utils::DateTime::current_local->epoch },
        });

        my $subscriber = $rs->first ? $rs->first->voip_subscriber : undef;
        unless($subscriber) {
            $c->log->warn("invalid password recovery attempt for uuid '$uuid_string' from '".$c->req->address."'");
            $c->detach('/denied_page');
        }
    }

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::ResetPassword", $c);
    my $params = {
        uuid => $uuid_string,
    };
    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        my $subscriber;
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $rs = $c->model('DB')->resultset('password_resets')->search({
                    uuid => $uuid_string,
                    timestamp => { '>=' => NGCP::Panel::Utils::DateTime::current_local->epoch },
                });

                $subscriber = $rs->first ? $rs->first->voip_subscriber : undef;
                unless($subscriber && $subscriber->provisioning_voip_subscriber) {
                    $c->log->warn("invalid password recovery attempt for uuid '$uuid_string' from '".$c->req->address."'");
                    $c->detach('/denied_page');
                }
                $subscriber->provisioning_voip_subscriber->update({
                    webpassword => $form->params->{password},
                });
                $rs->delete;
            });
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                type  => 'internal',
                desc  => $c->loc('Failed to recover web password'),
            );
            $c->detach('/denied_page');
        }

        $c->log->debug("+++++++++++++++++++++++ successfully recovered subscriber " . $subscriber->username . '@' . $subscriber->domain->domain);
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { username => $subscriber->username . '@' . $subscriber->domain->domain },
            desc => $c->loc('Web password successfully recovered, please re-login.'),
        );
        $c->flash(username => $subscriber->username . '@' . $subscriber->domain->domain);
        $c->res->redirect($c->uri_for('/login/subscriber'));
        return;

    }

    $c->stash(
        form => $form,
        edit_flag => 1,
        template => 'subscriber/recoverpassword.tt',
        close_target => $c->uri_for('/login/subscriber'),
    );
}

sub preferences :Chained('base') :PathPart('preferences') :Args(0) {
    my ($self, $c) = @_;

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $cfs = {};

    foreach my $type(qw/cfu cfna cft cfb cfs cfr/) {
        my $maps = $prov_subscriber->voip_cf_mappings
            ->search({ type => $type });
        $cfs->{$type} = [];
        foreach my $map($maps->all) {
            my @dset = ();
            my $dset_name = undef;
            if($map->destination_set) {
                @dset = map { { $_->get_columns } } $map->destination_set->voip_cf_destinations->search({},
                    { order_by => { -asc => 'priority' }})->all;
                foreach my $d(@dset) {
                    $d->{as_string} = NGCP::Panel::Utils::Subscriber::destination_as_string($c, $d, $prov_subscriber);
                }
                $dset_name = $map->destination_set->name;
            }
            my @tset = ();
            my $tset_name = undef;
            if($map->time_set) {
                @tset = map { { $_->get_columns } } $map->time_set->voip_cf_periods->all;
                foreach my $t(@tset) {
                    $t->{as_string} = NGCP::Panel::Utils::Subscriber::period_as_string($t);
                }
                $tset_name = $map->time_set->name;
            }
            my @sources = ();
            my $sset_name = undef;
            my $sset_mode = undef;
            if($map->source_set) {
                @sources = map { { $_->get_columns } } $map->source_set->voip_cf_sources->all;
                foreach my $s(@sources) {
                    $s->{as_string} = $s->{source};
                }
                $sset_name = $map->source_set->name;
                $sset_mode = $map->source_set->mode;
            }
            my @bnumbers = ();
            my $bset_name = undef;
            my $bset_mode = undef;
            if($map->bnumber_set) {
                @bnumbers = map { { $_->get_columns } } $map->bnumber_set->voip_cf_bnumbers->all;
                foreach my $s(@bnumbers) {
                    $s->{as_string} = $s->{bnumber};
                }
                $bset_name = $map->bnumber_set->name;
                $bset_mode = $map->bnumber_set->mode;
            }
            push @{ $cfs->{$type} }, {
                destinations => \@dset,
                dset_name => $dset_name,
                periods => \@tset,
                tset_name => $tset_name,
                sources => \@sources,
                sset_name => $sset_name,
                sset_mode => $sset_mode,
                bset_name => $bset_name,
                bset_mode => $bset_mode,
                bnumbers => \@bnumbers,
            };
        }
    }
    $c->stash(cf_destinations => $cfs);

    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => 'ringtimeout', prov_subscriber => $prov_subscriber)
        ->first;
    $c->stash(cf_ringtimeout => $ringtimeout_preference ? $ringtimeout_preference->value : undef);

    my @upn_rewrite_sets = $c->stash->{subscriber}->provisioning_voip_subscriber
                            ->upn_rewrite_sets_rs->all;
    $c->stash->{upn_rw_sets} = \@upn_rewrite_sets;

    my $vm_recordings_types = [];#type, greeting_exists
    my $subscriber_vm_recordings = get_inflated_columns_all(
        $c->stash->{subscriber}->provisioning_voip_subscriber->voicemail_user->voicemail_spools->search_rs(undef,{
            '+select' => [qw/dir dir/],
            '+as' => [qw/type greeting_exists/],
        }),
        hash => 'type',
    );
    foreach my $voicemail_greeting_type (qw/unavail busy/){
        my $dir = NGCP::Panel::Utils::Subscriber::get_subscriber_voicemail_directory(c => $c, subscriber => $c->stash->{subscriber}, dir => $voicemail_greeting_type);
        push @$vm_recordings_types,
            $subscriber_vm_recordings->{$dir} ? {%{$subscriber_vm_recordings->{$dir}}, type =>  $voicemail_greeting_type }
            : {greeting_exists => 0, type => $voicemail_greeting_type} ;
    }
    $c->stash->{vm_recordings_types} = $vm_recordings_types;

    if($prov_subscriber->profile_id && (
       $c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber")) {
        my @attribute_ids = $prov_subscriber->voip_subscriber_profile->profile_attributes->get_column('attribute_id')->all;
        my @newprefgroups = ();
        foreach my $grp(@{ $c->stash->{pref_groups} }) {
            my @newgrp = ();
            foreach my $pref(@{ $grp->{prefs} }) {
                my $pref_id = $pref->id;
                if(grep { /^$pref_id$/ } @attribute_ids) {
                    push @newgrp, $pref;
                }
            }
            $grp->{prefs} = \@newgrp;
            push @newprefgroups, $grp if @newgrp;
        }
        $c->stash->{pref_groups} = \@newprefgroups;

        my $special_prefs = { check => 1 };
        foreach my $pref(qw/cfu cft cfna cfb cfs cfr
                            speed_dial reminder auto_attendant
                            voice_mail fax_server/) {
            my $preference = $c->model('DB')->resultset('voip_preferences')->find({
                attribute => $pref,
            });
            next unless $preference;
            my $pref_id = $preference->id;
            my $pref_id_exists = grep { $pref_id eq $_ } @attribute_ids;
            if($pref =~ /^cf/ && $pref_id_exists) {
                $special_prefs->{callforward}->{active} = 1;
                $special_prefs->{callforward}->{$pref} = 1;
            } elsif($pref_id_exists) {
                $special_prefs->{$pref}->{active} = 1;
            }
        }
        $c->stash->{special_prefs} = $special_prefs;
    }
}

sub preferences_base :Chained('base') :PathPart('preferences') :CaptureArgs(1) {
    my ($self, $c, $pref_id) = @_;

    $self->load_preference_list($c);

    $c->stash->{preference_meta} = $c->model('DB')
        ->resultset('voip_preferences')
        ->single({id => $pref_id});
     if(($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') &&
        !$c->stash->{preference_meta}->expose_to_customer) {
        NGCP::Panel::Utils::Message::error(
            c    => $c,
            type => 'internal',
            desc => $c->loc("Invalid access to pref_id '[_1]' by provisioning subscriber id '[_2]'", $pref_id, $c->user->id),
        );
        $c->detach('/denied_page');
    }

    $c->stash->{preference} = $c->model('DB')
        ->resultset('voip_usr_preferences')
        ->search({
            attribute_id => $pref_id,
            subscriber_id => $c->stash->{subscriber}->provisioning_voip_subscriber->id
        });
    $c->stash(template => 'subscriber/preferences.tt');
}

sub preferences_edit :Chained('preferences_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    $c->stash(edit_preference => 1);

    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->search({usr_pref => 1})
        ->all;

    my $pref_rs = $c->model('DB')
        ->resultset('voip_usr_preferences')
        ->search({
            subscriber_id => $prov_subscriber->id
        });

    my $old_auth_prefs = {};
    if($c->req->method eq "POST" && $c->stash->{preference_meta}->attribute =~ /^peer_auth_/) {
        NGCP::Panel::Utils::Preferences::get_peer_auth_params(
            $c, $prov_subscriber, $old_auth_prefs);
    }

    try {
        NGCP::Panel::Utils::Preferences::create_preference_form( c => $c,
            pref_rs => $pref_rs,
            enums   => \@enums,
            base_uri => $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]),
            edit_uri => $c->uri_for_action('/subscriber/preferences_edit', $c->req->captures),
        );
        my $attr = $c->stash->{preference_meta}->attribute;
        if ($c->req->method eq "POST" && $attr && ($attr eq "voicemail_echo_number" || $attr eq "cli")) {
            NGCP::Panel::Utils::Subscriber::update_voicemail_number(
                schema => $c->model('DB'), subscriber => $c->stash->{subscriber});
        }
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => "Failed to handle preference: $e",
            desc  => $c->loc('Failed to handle preference'),
        );

        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
        return;
    }

    if(keys %{ $old_auth_prefs }) {
        my $new_auth_prefs = {};
        NGCP::Panel::Utils::Preferences::get_peer_auth_params(
            $c, $prov_subscriber, $new_auth_prefs);
        unless(compare($old_auth_prefs, $new_auth_prefs)) {
            try {
                NGCP::Panel::Utils::Preferences::update_sems_peer_auth(
                    $c, $prov_subscriber, $old_auth_prefs, $new_auth_prefs);
            } catch($e) {
                NGCP::Panel::Utils::Message::error(
                    c     => $c,
                    log   => "Failed to set peer registration: $e",
                    desc  => $c->loc('Peer registration error'),
                );
            }
        }
    }
}

sub preferences_callforward :Chained('base') :PathPart('preferences/callforward') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $cf_desc;
    SWITCH: for ($cf_type) {
        /^cfu$/ && do {
            $cf_desc = $c->loc('Call Forward Unconditional');
            last SWITCH;
        };
        /^cfb$/ && do {
            $cf_desc = $c->loc('Call Forward Busy');
            last SWITCH;
        };
        /^cft$/ && do {
            $cf_desc = $c->loc('Call Forward Timeout');
            last SWITCH;
        };
        /^cfna$/ && do {
            $cf_desc = $c->loc('Call Forward Unavailable');
            last SWITCH;
        };
        /^cfs$/ && do {
            $cf_desc = $c->loc('Call Forward SMS');
            last SWITCH;
        };
        /^cfr$/ && do {
            $cf_desc = $c->loc('Call Forward Rerouting');
            last SWITCH;
        };
        # default
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => "Invalid call-forward type '$cf_type'",
            desc  => $c->loc('Invalid Call Forward type.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    } # SWITCH

    my $posted = ($c->request->method eq 'POST');

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $cf_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, prov_subscriber => $prov_subscriber, attribute => $cf_type);
    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, prov_subscriber => $prov_subscriber, attribute => 'ringtimeout');
    my $cf_mapping = $prov_subscriber->voip_cf_mappings->search_rs({ type => $cf_type });
    my $destination;

    if($cf_mapping->count > 1) {
        # there is more than one mapping,
        # which can only be handled in advanced mode

        $c->response->redirect(
            $c->uri_for_action('/subscriber/preferences_callforward_advanced',
                [$c->req->captures->[0]], $cf_type, 'advanced'
            )
       );
       return;
    } elsif($cf_mapping->first && $cf_mapping->first->destination_set &&
            $cf_mapping->first->destination_set->voip_cf_destinations->first) {

        # there are more than one destinations or a time set or a source set or a bnumber set
        # => these can only be handled in advanced mode
        if($cf_mapping->first->destination_set->voip_cf_destinations->count > 1 ||
           $cf_mapping->first->time_set_id ||
           $cf_mapping->first->source_set_id ||
           $cf_mapping->first->bnumber_set_id) {

            $c->response->redirect(
                $c->uri_for_action('/subscriber/preferences_callforward_advanced',
                    [$c->req->captures->[0]], $cf_type, 'advanced'
                )
           );
           return;
        }
        $destination = $cf_mapping->first->destination_set->voip_cf_destinations->first;
    }

    my $params = {};
    if($posted) {
        # TODO: normalize
        $params = $c->request->params;
        if(length($params->{destination}) &&
           (!$c->request->params->{submitid} ||
            $c->request->params->{submitid} eq "cf_actions.save")
           ) {
            if($params->{destination} !~ /\@/) {
                $params->{destination} .= '@'.$c->stash->{subscriber}->domain->domain;
            }
            if($params->{destination} !~ /^sip:/) {
                $params->{destination} = 'sip:' . $params->{destination};
            }
        }
    } else {
        my $ringtimeout = 15;
        if($cf_type eq 'cft') {
            my $rt = $ringtimeout_preference->first;
            if($rt) {
                $ringtimeout = $rt->value;
            }
        }
        my $d = $destination ? $destination->destination : "";
        my $duri;
        my $t = $destination ? ($destination->timeout || 300) : 300;
        ($d, $duri) = NGCP::Panel::Utils::Subscriber::destination_to_field($d);
        if ($d eq "uri") {
            $c->stash->{cf_tmp_params} = {
                uri => {
                    destination => $duri,
                    timeout => $t,
                },
                id => $destination ? $destination->id : undef,
            };
        }
        $params = { destination => $c->stash->{cf_tmp_params} };
        $params->{destination}{destination} = $d;
        $params->{ringtimeout} = $ringtimeout;
        $params->{destination}->{announcement_id} = $destination ? $destination->announcement_id : '';
    }

    my $cf_form;
    if($cf_type eq "cft") {
        $cf_form = NGCP::Panel::Form::get("NGCP::Panel::Form::SubscriberCFTSimple", $c);
    } else {
        $cf_form = NGCP::Panel::Form::get("NGCP::Panel::Form::SubscriberCFSimple", $c);
    }

    $cf_form->process(
        posted => $posted,
        params => $params,
        item => $params,
    );

    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $cf_form,
        fields => {
            'cf_actions.advanced' =>
                $c->uri_for_action('/subscriber/preferences_callforward_advanced',
                    [$c->req->captures->[0]], $cf_type, 'advanced'
                ),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $cf_form->validated) {
        try {
            $c->model('DB')->schema->txn_do( sub {
                my $map = $cf_mapping->first;
                my $dest_set;
                my $old_autoattendant = 0;
                if($map && $map->destination_set) {
                    $dest_set = $map->destination_set;
                    $old_autoattendant = NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($dest_set);
                    $dest_set->voip_cf_destinations->delete_all;
                }
                unless($dest_set) {
                    $dest_set = $c->model('DB')->resultset('voip_cf_destination_sets')->create({
                        name => 'quickset_'.$cf_type,
                        subscriber_id => $prov_subscriber->id,
                    });
                }
                my $d = $cf_form->field('destination')->field('destination')->value;
                NGCP::Panel::Utils::Subscriber::check_cf_ivr(
                    c => $c, schema => $c->model('DB'),
                    subscriber => $c->stash->{subscriber},
                    old_aa => $old_autoattendant,
                    new_aa => ($d eq 'autoattendant'),
                );

                NGCP::Panel::Utils::Subscriber::create_cf_destination(
                    c => $c,
                    subscriber => $c->stash->{subscriber},
                    cf_type => $cf_type,
                    set => $dest_set,
                    fields => [$cf_form->field('destination')],
                );
                unless(defined $map) {
                    $map = $prov_subscriber->voip_cf_mappings->create({
                        type => $cf_type,
                        destination_set_id => $dest_set->id,
                        time_set_id => undef, #$time_set_id,
                    });
                }
                foreach my $pref($cf_preference->all) {
                    $pref->delete;
                }
                $cf_preference->create({ value => $map->id });
                if($cf_type eq 'cft') {
                    if($ringtimeout_preference->first) {
                        $ringtimeout_preference->first->update({
                            value => $c->request->params->{ringtimeout}
                        });
                    } else {
                        $ringtimeout_preference->create({
                            value => $c->request->params->{ringtimeout},
                        });
                    }
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully saved Call Forward'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to save Call Forward'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cf_flag => 1,
        cf_description => $cf_desc,
        cf_form => $cf_form,
    );
}

sub preferences_callforward_advanced :Chained('base') :PathPart('preferences/callforward') :Args(2) {
    my ($self, $c, $cf_type, $advanced) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    # TODO bail out of $advanced ne "advanced"
    if(defined $advanced && $advanced eq 'advanced') {
        $advanced = 1;
    } else {
        $advanced = 0;
    }

    my $cf_desc;
    SWITCH: for ($cf_type) {
        /^cfu$/ && do {
            $cf_desc = $c->loc('Call Forward Unconditional');
            last SWITCH;
        };
        /^cfb$/ && do {
            $cf_desc = $c->loc('Call Forward Busy');
            last SWITCH;
        };
        /^cft$/ && do {
            $cf_desc = $c->loc('Call Forward Timeout');
            last SWITCH;
        };
        /^cfna$/ && do {
            $cf_desc = $c->loc('Call Forward Unavailable');
            last SWITCH;
        };
        /^cfs$/ && do {
            $cf_desc = $c->loc('Call Forward SMS');
            last SWITCH;
        };
        /^cfr$/ && do {
            $cf_desc = $c->loc('Call Forward Rerouting');
            last SWITCH;
        };
        # default
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => "Invalid call-forward type '$cf_type'",
            desc  => $c->loc('Invalid Call Forward type.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    } # SWITCH

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $cf_mapping = $prov_subscriber->voip_cf_mappings->search_rs({ type => $cf_type });
    my $cf_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, prov_subscriber => $prov_subscriber, attribute => $cf_type);
    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, prov_subscriber => $prov_subscriber, attribute => 'ringtimeout');

    $c->stash->{cf_destination_sets} = $prov_subscriber->voip_cf_destination_sets
        ->search_rs(undef,{order_by => 'name'});
    $c->stash->{cf_time_sets} = $prov_subscriber->voip_cf_time_sets;
    $c->stash->{cf_source_sets} = $prov_subscriber->voip_cf_source_sets;
    $c->stash->{cf_bnumber_sets} = $prov_subscriber->voip_cf_bnumber_sets;

    my $posted = ($c->request->method eq 'POST');

    my $cf_form;
    if($cf_type eq "cft") {
        $cf_form = NGCP::Panel::Form::get("NGCP::Panel::Form::SubscriberCFTAdvanced", $c, 1);
    } else {
        $cf_form = NGCP::Panel::Form::get("NGCP::Panel::Form::SubscriberCFAdvanced", $c, 1);
    }

    my @maps = ();
    foreach my $map($cf_mapping->all) {
        push @maps, {
            destination_set => $map->destination_set ? $map->destination_set->id : undef,
            time_set => $map->time_set ? $map->time_set->id : undef,
            source_set => $map->source_set ? $map->source_set->id : undef,
            bnumber_set => $map->bnumber_set ? $map->bnumber_set->id : undef,
        };
    }
    my $params = {
        active_callforward => \@maps,
        ringtimeout =>  $ringtimeout_preference->first ? $ringtimeout_preference->first->value : 15,
    };

    $cf_form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );


    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $cf_form,
        fields => {
            'cf_actions.simple' =>
                $c->uri_for_action('/subscriber/preferences_callforward',
                    [$c->req->captures->[0], $cf_type],
                ),
            'cf_actions.edit_destination_sets' =>
                $c->uri_for_action('/subscriber/preferences_callforward_destinationset',
                    [$c->req->captures->[0]], $cf_type,
                ),
            'cf_actions.edit_time_sets' =>
                $c->uri_for_action('/subscriber/preferences_callforward_timeset',
                    [$c->req->captures->[0]], $cf_type,
                ),
            'cf_actions.edit_source_sets' =>
                $c->uri_for_action('/subscriber/preferences_callforward_sourceset',
                    [$c->req->captures->[0]], $cf_type,
                ),
            'cf_actions.edit_bnumber_sets' =>
                $c->uri_for_action('/subscriber/preferences_callforward_bnumberset',
                    [$c->req->captures->[0]], $cf_type,
                ),
        },
        back_uri => $c->req->uri,
    );


    if($posted && $cf_form->validated) {
        try {
            $c->model('DB')->schema->txn_do( sub {
                my $autoattendant_count = 0;
                my @active = $cf_form->field('active_callforward')->fields;
                if($cf_mapping->first) { # there are mappings
                    foreach my $map($cf_mapping->all) {
                        $autoattendant_count += NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($map->destination_set);
                        $map->delete;
                    }
                    $cf_preference->delete_all;
                    unless(@active) {
                        $ringtimeout_preference->first->delete
                            if($cf_type eq "cft" &&  $ringtimeout_preference->first);
                        NGCP::Panel::Utils::Message::info(
                            c    => $c,
                            desc => $c->loc('Successfully cleared Call Forward'),
                        );
                        # we don't use back_or, as we might end up in the simple view again
                        $c->res->redirect(
                            $c->uri_for_action('/subscriber/preferences',
                                [$c->req->captures->[0]]), 1
                        );
                        return;
                    }
                }
                foreach my $map(@active) {
                    my $m = $cf_mapping->create({
                        type => $cf_type,
                        destination_set_id => $map->field('destination_set')->value,
                        time_set_id => $map->field('time_set')->value,
                        source_set_id => $map->field('source_set')->value,
                        bnumber_set_id => $map->field('bnumber_set')->value,
                    });
                    $cf_preference->create({ value => $m->id });
                    $autoattendant_count -= NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($m->destination_set);
                }
                if ($autoattendant_count > 0) {
                    while ($autoattendant_count != 0) {
                        $autoattendant_count--;
                        NGCP::Panel::Utils::Events::insert(
                            c => $c, schema => $c->model('DB'),
                            subscriber_id => $c->stash->{subscriber}->id,
                            type => 'end_ivr',
                        );
                    }
                } elsif ($autoattendant_count < 0) {
                    while ($autoattendant_count != 0) {
                        $autoattendant_count++;
                        NGCP::Panel::Utils::Events::insert(
                            c => $c, schema => $c->model('DB'),
                            subscriber_id => $c->stash->{subscriber}->id,
                            type => 'start_ivr',
                        );
                    }
                }
                if($cf_type eq "cft") {
                    if($ringtimeout_preference->first) {
                        $ringtimeout_preference->first->update({ value => $cf_form->field('ringtimeout')->value });
                    } else {
                        $ringtimeout_preference->create({ value => $cf_form->field('ringtimeout')->value });
                    }
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully saved Call Forward'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to save Call Forward'),
            );
        }
        # we don't use back_or, as we might end up in the simple view again
        $c->res->redirect(
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }


    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cf_flag => 1,
        cf_description => $cf_desc,
        cf_form => $cf_form,
    );
}

sub preferences_callforward_destinationset :Chained('base') :PathPart('preferences/destinationset') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    my @sets;
    if($prov_subscriber->voip_cf_destination_sets) {
        foreach my $set($prov_subscriber->voip_cf_destination_sets->all) {
            if($set->voip_cf_destinations) {
                my @dests = map { { $_->get_columns } } $set->voip_cf_destinations->search({},
                    { order_by => { -asc => 'priority' }})->all;
                foreach my $d(@dests) {
                    $d->{as_string} = NGCP::Panel::Utils::Subscriber::destination_as_string($c, $d, $prov_subscriber);
                }
                push @sets, { name => $set->name, id => $set->id, destinations => \@dests };
            }
        }
    }
    $c->stash->{cf_sets} = \@sets;

    my $cf_form = undef;

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cfset_flag => 1,
        cf_description => $c->loc('Destination Sets'),
        cf_form => $cf_form,
        cf_type => $cf_type,
    );
}

sub preferences_callforward_destinationset_create :Chained('base') :PathPart('preferences/destinationset/create') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::DestinationSet", $c);

    my $posted = ($c->request->method eq 'POST');

    $form->process(
        posted => $posted,
        params => $c->req->params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my @fields = $form->field('destination')->fields;
                if(@fields) {
                    my $set = $prov_subscriber->voip_cf_destination_sets->create({
                        name => $form->field('name')->value,
                    });
                    NGCP::Panel::Utils::Subscriber::create_cf_destination(
                        c => $c,
                        subscriber => $c->stash->{subscriber},
                        cf_type => $cf_type,
                        set => $set,
                        fields => \@fields,
                    );
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                type => 'internal',
                desc => $c->loc('Successfully created new destination set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                type  => 'internal',
                desc  => $c->loc('Failed to create new destination set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences_callforward_destinationset',
                    [$c->req->captures->[0]], $cf_type)
            );
    }

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cf_flag => 1,
        cf_description => $c->loc('Destination Set'),
        cf_form => $form,
        cf_type => $cf_type,
    );
}

sub preferences_callforward_destinationset_base :Chained('base') :PathPart('preferences/destinationset') :CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    $c->stash(destination_set => $c->stash->{subscriber}
        ->provisioning_voip_subscriber
        ->voip_cf_destination_sets
        ->find($set_id));

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
}

sub preferences_callforward_destinationset_edit :Chained('preferences_callforward_destinationset_base') :PathPart('edit') :Args(1) {
    my ($self, $c, $cf_type) = @_;
    my $fallback = $c->uri_for_action('/subscriber/preferences_callforward_destinationset',
                    [$c->req->captures->[0]], $cf_type);

    my $posted = ($c->request->method eq 'POST');

    my $cf_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => $cf_type,
    );
    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => 'ringtimeout',
    );

    my $set =  $c->stash->{destination_set};
    my $params;
    unless($posted) {
        $params->{name} = $set->name;
        my @destinations;
        for my $dest($set->voip_cf_destinations->all) {
            my $d = $dest->destination;
            my $duri;
            my $t = $dest->timeout;
            ($d, $duri) = NGCP::Panel::Utils::Subscriber::destination_to_field($d);

            push @destinations, {
                destination     => $d,
                uri             => {timeout => $t, destination => $duri},
                priority        => $dest->priority,
                announcement_id => $dest->announcement_id,
                id              => $dest->id,
            };
        }
        $params->{destination} = \@destinations;
    }

    $c->stash->{cf_tmp_params} = $params;
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::DestinationSet", $c);
    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    delete $c->stash->{cf_tmp_params};

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                # delete whole set and mapping if empty
                my @fields = $form->field('destination')->fields;
                unless(@fields) {
                    foreach my $mapping($set->voip_cf_mappings->all) {
                        my $cf = $cf_preference->find({ value => $mapping->id });
                        $cf->delete if $cf;
                        $ringtimeout_preference->first->delete
                            if($cf_type eq "cft" && $ringtimeout_preference->first);
                        $mapping->delete;
                        NGCP::Panel::Utils::Subscriber::check_cf_ivr( # one event per affected mapping
                            c => $c, schema => $schema,
                            subscriber => $c->stash->{subscriber},
                            old_aa => NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($set),
                            new_aa => 0,
                        );
                    }
                    $set->delete;
                    NGCP::Panel::Utils::Navigation::back_or($c, $fallback, 1);
                    return;
                }
                if($form->field('name')->value ne $set->name) {
                    $set->update({name => $form->field('name')->value});
                }
                my $old_autoattendant = NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($set);
                $set->voip_cf_destinations->delete_all;

                NGCP::Panel::Utils::Subscriber::create_cf_destination(
                    c => $c,
                    subscriber => $c->stash->{subscriber},
                    cf_type => $cf_type,
                    set => $set,
                    fields => [$form->field('destination')->fields],
                );

                $set->discard_changes; # reload (destinations may be cached)
                my $new_autoattendant = NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($set);
                my $event_type = '';
                if (!$old_autoattendant && $new_autoattendant) {
                    $event_type = 'start_ivr';
                } elsif ($old_autoattendant && !$new_autoattendant) {
                    $event_type = 'end_ivr';
                }
                if ($event_type) {
                    foreach my $mapping ($set->voip_cf_mappings->all) { # one event per affected mapping
                        NGCP::Panel::Utils::Events::insert(
                            c => $c, schema => $schema,
                            subscriber_id => $c->stash->{subscriber}->id,
                            type => $event_type,
                        );
                    }
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                type => 'internal',
                desc => $c->loc('Successfully updated destination set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                type  => 'internal',
                desc  => $c->loc('Failed to update destination set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $fallback);
    }

    $c->stash(
        edit_cf_flag => 1,
        cf_description => "Destination Set",
        cf_form => $form,
    );

}

sub preferences_callforward_destinationset_delete :Chained('preferences_callforward_destinationset_base') :PathPart('delete') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $cf_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => $cf_type,
    );
    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => 'ringtimeout',
    );
    my $set =  $c->stash->{destination_set};
    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            my $autoattendant = NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($set);
            foreach my $map($set->voip_cf_mappings->all) {
                my $cf = $cf_preference->find({ value => $map->id });
                $cf->delete if $cf;
                $map->delete;
                if ($autoattendant) {
                    NGCP::Panel::Utils::Events::insert(
                        c => $c, schema => $schema,
                        subscriber_id => $c->stash->{subscriber}->id,
                        type => 'end_ivr',
                    );
                }
            }
            if($cf_type eq "cft" &&
               $prov_subscriber->voip_cf_mappings->search_rs({ type => $cf_type})->count == 0) {
                $ringtimeout_preference->first->delete;
            }
            $set->delete;
        });
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $set->get_inflated_columns },
            type => 'internal',
            desc => $c->loc('Successfully deleted destination set'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            data  => { $set->get_inflated_columns },
            type  => 'internal',
            desc  => $c->loc('Failed to delete destination set'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/preferences_callforward_destinationset',
            [$c->req->captures->[0]], $cf_type)
    );
}

sub preferences_callforward_sourceset :Chained('base') :PathPart('preferences/sourceset') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    my @sets;
    if($prov_subscriber->voip_cf_source_sets) {
        foreach my $set($prov_subscriber->voip_cf_source_sets->all) {
            if($set->voip_cf_sources) {
                my @sources = map { { $_->get_columns } } $set->voip_cf_sources->all;
                foreach my $s(@sources) {
                    $s->{as_string} = $s->{source};
                }
                push @sets, { name => $set->name, mode => $set->mode, id => $set->id, sources => \@sources };
            }
        }
    }

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_sourceset_flag => 1,
        cf_form => undef,
        cf_type => $cf_type,
        cf_source_sets => \@sets,
    );
}

sub preferences_callforward_sourceset_create :Chained('base') :PathPart('preferences/sourceset/create') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::CallforwardSourceSet", $c);

    my $posted = ($c->request->method eq 'POST');

    $form->process(
        posted => $posted,
        params => $c->req->params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my @fields = $form->field('source')->fields;
                if(@fields) {
                    my $set = $prov_subscriber->voip_cf_source_sets->create({
                        name => $form->field('name')->value,
                        mode => $form->field('mode')->value,
                        is_regex => $form->field('is_regex')->value,
                    });
                    foreach my $src(@fields) {
                        my $s = $src->field('source')->value;

                        $set->voip_cf_sources->create({
                            source => $s,
                        });
                    }
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                type => 'internal',
                desc => $c->loc('Successfully created new source set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                type  => 'internal',
                desc  => $c->loc('Failed to create new source set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences_callforward_sourceset',
                    [$c->req->captures->[0]], $cf_type)
            );
    }

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cf_flag => 1,
        cf_description => $c->loc('Source Set'),
        cf_form => $form,
        cf_type => $cf_type,
    );
}

sub preferences_callforward_sourceset_base :Chained('base') :PathPart('preferences/sourceset') :CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    $c->stash->{source_set} = $c->stash->{subscriber}
        ->provisioning_voip_subscriber
        ->voip_cf_source_sets
        ->find($set_id);

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
}

sub preferences_callforward_sourceset_edit :Chained('preferences_callforward_sourceset_base') :PathPart('edit') :Args(1) {
    my ($self, $c, $cf_type) = @_;
    my $fallback = $c->uri_for_action('/subscriber/preferences_callforward_sourceset',
                    [$c->req->captures->[0]], $cf_type);

    my $posted = ($c->request->method eq 'POST');

    my $cf_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => $cf_type,
    );
    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => 'ringtimeout',
    );

    my $set =  $c->stash->{source_set};
    my $params;
    unless($posted) {
        $params->{name} = $set->name;
        $params->{mode} = $set->mode;
        $params->{is_regex} = $set->is_regex;
        my @sources;
        for my $src($set->voip_cf_sources->all) {
            push @sources, {
                source => $src->source,
                id => $src->id,
            };
        }
        $params->{source} = \@sources;
    }

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::CallforwardSourceSet", $c);
    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                # delete whole set and mapping if empty
                my @fields = $form->field('source')->fields;
                unless(@fields) {
                    foreach my $mapping($set->voip_cf_mappings->all) {
                        my $cf = $cf_preference->find({ value => $mapping->id });
                        $cf->delete if $cf;
                        $ringtimeout_preference->first->delete
                            if($cf_type eq "cft" && $ringtimeout_preference->first);
                        $mapping->delete;
                    }
                    $set->delete;
                    NGCP::Panel::Utils::Navigation::back_or($c, $fallback, 1);
                    return;
                }
                if($form->field('name')->value ne $set->name) {
                    $set->update({name => $form->field('name')->value});
                }
                if($form->field('mode')->value ne $set->mode) {
                    $set->update({mode => $form->field('mode')->value});
                }
                if($form->field('is_regex')->value ne $set->is_regex) {
                    $set->update({is_regex => $form->field('is_regex')->value});
                }
                $set->voip_cf_sources->delete_all;

                foreach my $src(@fields) {
                    my $s = $src->field('source')->value;

                    $set->voip_cf_sources->create({
                        source => $s,
                    });
                }
                $set->discard_changes; # reload (sources may be cached)
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                type => 'internal',
                desc => $c->loc('Successfully updated source set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                type  => 'internal',
                desc  => $c->loc('Failed to update source set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $fallback);
    }

    $c->stash(
        edit_cf_flag => 1,
        cf_description => "Source Set",
        cf_form => $form,
    );

}

sub preferences_callforward_sourceset_delete :Chained('preferences_callforward_sourceset_base') :PathPart('delete') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $cf_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => $cf_type,
    );
    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => 'ringtimeout',
    );
    my $set =  $c->stash->{source_set};
    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            foreach my $map($set->voip_cf_mappings->all) {
                my $cf = $cf_preference->find({ value => $map->id });
                $cf->delete if $cf;
                $map->delete;
            }
            if($cf_type eq "cft" &&
               $prov_subscriber->voip_cf_mappings->search_rs({ type => $cf_type})->count == 0) {
                $ringtimeout_preference->first->delete;
            }
            $set->delete;
        });
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $set->get_inflated_columns },
            type => 'internal',
            desc => $c->loc('Successfully deleted source set'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            data  => { $set->get_inflated_columns },
            type  => 'internal',
            desc  => $c->loc('Failed to delete source set'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/preferences_callforward_sourceset',
            [$c->req->captures->[0]], $cf_type)
    );
}

sub preferences_callforward_bnumberset :Chained('base') :PathPart('preferences/bnumberset') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    my @sets;
    if($prov_subscriber->voip_cf_bnumber_sets) {
        foreach my $set($prov_subscriber->voip_cf_bnumber_sets->all) {
            if($set->voip_cf_bnumbers) {
                my @bnumbers = map { { $_->get_columns } } $set->voip_cf_bnumbers->all;
                foreach my $s(@bnumbers) {
                    $s->{as_string} = $s->{bnumber};
                }
                push @sets, { name => $set->name, mode => $set->mode, id => $set->id, bnumbers => \@bnumbers };
            }
        }
    }

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_bnumberset_flag => 1,
        cf_form => undef,
        cf_type => $cf_type,
        cf_bnumber_sets => \@sets,
    );
}

sub preferences_callforward_bnumberset_create :Chained('base') :PathPart('preferences/bnumberset/create') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::CallforwardBnumberSet", $c);

    my $posted = ($c->request->method eq 'POST');

    $form->process(
        posted => $posted,
        params => $c->req->params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my @fields = $form->field('bnumbers')->fields;
                if(@fields) {
                    my $set = $prov_subscriber->voip_cf_bnumber_sets->create({
                        name => $form->field('name')->value,
                        mode => $form->field('mode')->value,
                        is_regex => $form->field('is_regex')->value,
                    });
                    foreach my $bnum_row(@fields) {
                        my $s = $bnum_row->field('number')->value;

                        $set->voip_cf_bnumbers->create({
                            bnumber => $s,
                        });
                    }
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                type => 'internal',
                desc => $c->loc('Successfully created new source set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                type  => 'internal',
                desc  => $c->loc('Failed to create new source set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences_callforward_bnumberset',
                    [$c->req->captures->[0]], $cf_type)
            );
    }

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cf_flag => 1,
        cf_description => $c->loc('B-Number Set'),
        cf_form => $form,
        cf_type => $cf_type,
    );
}

sub preferences_callforward_bnumberset_base :Chained('base') :PathPart('preferences/bnumberset') :CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    $c->stash->{bnumber_set} = $c->stash->{subscriber}
        ->provisioning_voip_subscriber
        ->voip_cf_bnumber_sets
        ->find($set_id);

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
}

sub preferences_callforward_bnumberset_edit :Chained('preferences_callforward_bnumberset_base') :PathPart('edit') :Args(1) {
    my ($self, $c, $cf_type) = @_;
    my $fallback = $c->uri_for_action('/subscriber/preferences_callforward_bnumberset',
                    [$c->req->captures->[0]], $cf_type);

    my $posted = ($c->request->method eq 'POST');

    my $cf_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => $cf_type,
    );
    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => 'ringtimeout',
    );

    my $set =  $c->stash->{bnumber_set};
    my $params;
    unless($posted) {
        $params->{name} = $set->name;
        $params->{mode} = $set->mode;
        $params->{is_regex} = $set->is_regex;
        my @numbers;
        for my $bnum_rows($set->voip_cf_bnumbers->all) {
            push @numbers, {
                number => $bnum_rows->bnumber,
                id => $bnum_rows->id,
            };
        }
        $params->{bnumbers} = \@numbers;
    }

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::CallforwardBnumberSet", $c);
    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                # delete whole set and mapping if empty
                my @fields = $form->field('bnumbers')->fields;
                unless(@fields) {
                    foreach my $mapping($set->voip_cf_mappings->all) {
                        # delete it here (this has been a design decicion from the beginning for all parts of cfs)
                        my $cf = $cf_preference->find({ value => $mapping->id });
                        $cf->delete if $cf;
                        $ringtimeout_preference->first->delete
                           if($cf_type eq "cft" && $ringtimeout_preference->first);
                        $mapping->delete;
                    }
                    $set->delete;
                    NGCP::Panel::Utils::Navigation::back_or($c, $fallback, 1);
                    return;
                }
                if($form->field('name')->value ne $set->name) {
                    $set->update({name => $form->field('name')->value});
                }
                if($form->field('mode')->value ne $set->mode) {
                    $set->update({mode => $form->field('mode')->value});
                }
                if($form->field('is_regex')->value ne $set->is_regex) {
                    $set->update({is_regex => $form->field('is_regex')->value});
                }
                $set->voip_cf_bnumbers->delete_all;

                foreach my $src(@fields) {
                    my $s = $src->field('number')->value;

                    $set->voip_cf_bnumbers->create({
                        bnumber => $s,
                    });
                }
                $set->discard_changes; # reload (voip_cf_bnumbers may be cached)
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                type => 'internal',
                desc => $c->loc('Successfully updated bnumber set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                type  => 'internal',
                desc  => $c->loc('Failed to update bnumber set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $fallback);
    }

    $c->stash(
        edit_cf_flag => 1,
        cf_description => "B-Number Set",
        cf_form => $form,
    );

}

sub preferences_callforward_bnumberset_delete :Chained('preferences_callforward_bnumberset_base') :PathPart('delete') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $cf_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => $cf_type,
    );
    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => 'ringtimeout',
    );
    my $set =  $c->stash->{bnumber_set};
    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            foreach my $map($set->voip_cf_mappings->all) {
                my $cf = $cf_preference->find({ value => $map->id });
                $cf->delete if $cf;
                $map->delete;
            }
            if($cf_type eq "cft" &&
               $prov_subscriber->voip_cf_mappings->search_rs({ type => $cf_type})->count == 0) {
                $ringtimeout_preference->first->delete;
            }
            $set->delete;
        });
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $set->get_inflated_columns },
            type => 'internal',
            desc => $c->loc('Successfully deleted bnumber set'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            data  => { $set->get_inflated_columns },
            type  => 'internal',
            desc  => $c->loc('Failed to delete bnumber set'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/preferences_callforward_bnumberset',
            [$c->req->captures->[0]], $cf_type)
    );
}

sub preferences_callforward_timeset :Chained('base') :PathPart('preferences/timeset') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    my @sets;
    if($prov_subscriber->voip_cf_time_sets) {
        foreach my $set($prov_subscriber->voip_cf_time_sets->all) {
            if($set->voip_cf_periods) {
                my @periods = map { { $_->get_columns } } $set->voip_cf_periods->all;
                foreach my $p(@periods) {
                    $p->{as_string} = NGCP::Panel::Utils::Subscriber::period_as_string($p);
                }
                push @sets, { name => $set->name, id => $set->id, periods => \@periods};
            }
        }
    }
    $c->stash->{cf_sets} = \@sets;

    my $cf_form = undef;

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_timeset_flag => 1,
        cf_description => $c->loc('Time Sets'),
        cf_form => $cf_form,
        cf_type => $cf_type,
    );
}

sub preferences_callforward_timeset_create :Chained('base') :PathPart('preferences/timeset/create') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::TimeSet", $c);

    my $posted = ($c->request->method eq 'POST');

    $form->process(
        posted => $posted,
        params => $c->req->params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my @fields = $form->field('period')->fields;
                if(@fields) {
                    my $set = $prov_subscriber->voip_cf_time_sets->create({
                        name => $form->field('name')->value,
                    });

                    foreach my $period($form->field('period')->fields) {
                        my $fields = {};
                        for my $type (qw/year month mday wday hour minute/) {
                            my $row = $period->field("row");
                            my $from = $row->field($type)->field("from")->value;
                            my $to = $row->field($type)->field("to")->value;
                            if($type eq "wday") {
                                $from = int($from)+1 if defined($from);
                                $to = int($to)+1 if defined($to);
                            }
                            if(defined $from) {
                                $fields->{$type} = $from .
                                    (defined $to ?
                                        '-'.$to : '');
                            }
                        }
                        $set->voip_cf_periods->create($fields);
                    }
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                type => 'internal',
                desc => $c->loc('Successfully created new time set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                type  => 'internal',
                desc  => $c->loc('Failed to create new time set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences_callforward_timeset',
                    [$c->req->captures->[0]], $cf_type)
        );
    }

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cf_flag => 1,
        cf_description => "Time Set",
        cf_form => $form,
        cf_type => $cf_type,
    );
}

sub preferences_callforward_timeset_base :Chained('base') :PathPart('preferences/timeset') :CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    $c->stash(time_set => $c->stash->{subscriber}
        ->provisioning_voip_subscriber
        ->voip_cf_time_sets
        ->find($set_id));

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
}

sub preferences_callforward_timeset_edit :Chained('preferences_callforward_timeset_base') :PathPart('edit') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::TimeSet", $c);

    my $posted = ($c->request->method eq 'POST');

    my $set =  $c->stash->{time_set};
    my $params;
    unless($posted) {
        $params->{name} = $set->name;
        my @periods;
        for my $period($set->voip_cf_periods->all) {
            my $p = {};
            foreach my $type(qw/year month mday wday hour minute/) {
                my $val = $period->$type;
                if(defined $val) {
                    my ($from, $to) = split/\-/, $val; #/
                    if($type eq "wday") {
                        $from = int($from)-1 if defined($from);
                        $to = int($to)-1 if defined($to);
                    }
                    $p->{row}->{$type}->{from} = $from;
                    $p->{row}->{$type}->{to} = $to if defined($to);
                }
            }
            push @periods, $p;
        }
        $params->{period} = \@periods;
    }

    $form->process(
        params => $posted ? $c->req->params : $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my @fields = $form->field('period')->fields;
                unless(@fields) {
                    foreach my $mapping($set->voip_cf_mappings) {
                        $mapping->update({ time_set_id => undef });
                    }
                    $set->delete;

                    NGCP::Panel::Utils::Navigation::back_or($c,
                        $c->uri_for_action('/subscriber/preferences_callforward_timeset',
                            [$c->req->captures->[0]], $cf_type), 1
                    );
                    return;
                }
                if($form->field('name')->value ne $set->name) {
                    $set->update({name => $form->field('name')->value});
                }
                foreach my $period($set->voip_cf_periods->all) {
                    $period->delete;
                }
                foreach my $period($form->field('period')->fields) {
                    my $fields = {};
                    for my $type (qw/year month mday wday hour minute/) {
                        my $row = $period->field("row");
                        my $from = $row->field($type)->field("from")->value;
                        my $to = $row->field($type)->field("to")->value;
                        if($type eq "wday") {
                            $from = int($from)+1 if defined($from);
                            $to = int($to)+1 if defined($to);
                        }
                        if(defined $from) {
                            $fields->{$type} = $from .
                                (defined $to ?
                                    '-'.$to : '');
                        }
                    }
                    $set->voip_cf_periods->create($fields);
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                type => 'internal',
                desc => $c->loc('Successfully updated time set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                type  => 'internal',
                desc  => $c->loc('Failed to update time set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
                $c->uri_for_action('/subscriber/preferences_callforward_timeset',
                    [$c->req->captures->[0]], $cf_type)
        );
    }

    $c->stash(
        edit_cf_flag => 1,
        cf_description => $c->loc('Time Set'),
        cf_form => $form,
    );

}

sub preferences_callforward_timeset_delete :Chained('preferences_callforward_timeset_base') :PathPart('delete') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $set =  $c->stash->{time_set};

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            foreach my $map($set->voip_cf_mappings->all) {
                $map->update({ time_set_id => undef });
            }
            $set->delete;
        });
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $set->get_inflated_columns },
            type => 'internal',
            desc => $c->loc('Successfully deleted time set'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            data  => { $set->get_inflated_columns },
            type  => 'internal',
            desc  => $c->loc('Failed to delete time set'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/preferences_callforward_timeset',
            [$c->req->captures->[0]], $cf_type)
    );
}

sub preferences_callforward_delete :Chained('base') :PathPart('preferences/callforward/delete') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
            my $mapping_rs = $prov_subscriber->voip_cf_mappings->search({ type => $cf_type });
            my $autoattendant_count = 0;
            foreach my $map($mapping_rs->all) {
                $autoattendant_count += NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($map->destination_set);
            }
            $mapping_rs->delete_all;
            my $cf_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c,
                attribute => $cf_type,
                prov_subscriber => $prov_subscriber,
            );
            $cf_pref->delete_all;
            while ($autoattendant_count > 0) {
                $autoattendant_count--;
                NGCP::Panel::Utils::Events::insert(
                    c => $c, schema => $schema,
                    subscriber_id => $c->stash->{subscriber}->id,
                    type => 'end_ivr',
                );
            }
        });
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            desc => $c->loc('Successfully deleted Call Forward'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete Call Forward.'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
}

sub underrun_catchup :Private {
    my ($self, $c) = @_;
    try {
        my $schema = $c->model('DB');
        $schema->set_transaction_isolation('READ COMMITTED');
        $schema->txn_do(sub {
            NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c, contract => $c->stash->{subscriber}->contract);
        });
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            type  => 'internal',
            desc  => $c->loc('Failed to check and apply underrun subscriber lock level'),
        );
        $c->response->redirect($c->uri_for());
        #return;
    }
}

sub load_preference_list :Private {
    my ($self, $c) = @_;

    my $reseller_id = $c->stash->{subscriber}->contract->contact->reseller_id;

    $self->underrun_catchup($c);

    my $usr_pref_values = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
                'subscriber.id' => $c->stash->{subscriber}->provisioning_voip_subscriber->id
            },{
                prefetch => {'voip_usr_preferences' => 'subscriber'},
            });
    my %pref_values;
    foreach my $value($usr_pref_values->all) {

        $pref_values{$value->attribute} = [
            map {$_->value} $value->voip_usr_preferences->all
        ];
    }

    my $rewrite_rule_sets_rs = $c->model('DB')
        ->resultset('voip_rewrite_rule_sets')->search({ reseller_id => $reseller_id });
    $c->stash(rwr_sets_rs => $rewrite_rule_sets_rs,
              rwr_sets    => [$rewrite_rule_sets_rs->all]);

    my $ncos_levels_rs = $c->model('DB')
        ->resultset('ncos_levels')->search({ reseller_id => $reseller_id });
    $c->stash(ncos_levels_rs => $ncos_levels_rs,
              ncos_levels    => [$ncos_levels_rs->all]);

    my $emergency_mapping_containers_rs = $c->model('DB')
        ->resultset('emergency_containers')->search({ reseller_id => $reseller_id });
    $c->stash(emergency_mapping_containers_rs => $emergency_mapping_containers_rs,
              emergency_mapping_containers    => [$emergency_mapping_containers_rs->all]);

    my $sound_sets_rs = $c->model('DB')
        ->resultset('voip_sound_sets')->search({
            reseller_id => $reseller_id,
            contract_id => undef });
    $c->stash(sound_sets_rs => $sound_sets_rs,
              sound_sets    => [$sound_sets_rs->all]);

    my $contract_sound_sets_rs = $c->model('DB')
        ->resultset('voip_sound_sets')->search({
            reseller_id => $reseller_id,
            contract_id => $c->stash->{subscriber}->contract_id });
    $c->stash(contract_sound_sets_rs => $contract_sound_sets_rs,
              contract_sound_sets    => [$contract_sound_sets_rs->all]);

    NGCP::Panel::Utils::Preferences::load_preference_list( c => $c,
        pref_values => \%pref_values,
        usr_pref => 1,
        customer_view => (($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') ? 1 : 0)
    );
}

sub master :Chained('base') :PathPart('details') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash->{vm_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "read", search => 1, title => $c->loc('Read'), literal_sql => 'if(dir like "%/INBOX", "new", "read")' },
        { name => "callerid", search => 1, title => $c->loc('Caller') },
        { name => "origtime", search_from_epoch => 1, search_to_epoch => 1, title => $c->loc('Time') },
        { name => "duration", search => 1, title => $c->loc('Duration') },
    ]);
    $c->stash->{streams_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "output_type", title => $c->loc('Type') },
        { name => "file_format", title => $c->loc('Format') },
    ]);
    $c->stash->{reg_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        #left untouchable, although user_agent is always the same by design, see MT 14789 notes
        { name => "user_agent", search => 1, title => $c->loc('User Agent') },
        { name => "contact", search => 1, title => $c->loc('Contact') },
        { name => "expires", search => 1, title => $c->loc('Expires') },
    ]);
    $c->stash->{capture_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "timestamp", search => 1, title => $c->loc('Timestamp') },
        { name => "call_id", search => 1, title => $c->loc('Call-ID') },
        { name => "cseq_method", search => 1, title => $c->loc('Method') },
    ]);
    my $rec_cols = [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "start_timestamp", search_from_epoch => 1, search_to_epoch => 1, title => $c->loc('Time') },
    ];
    if($c->user->roles eq "admin" || $c->user->roles eq "reseller") {
        push @{ $rec_cols },
            { name => "call_id", title => $c->loc('Call-ID') };
    }
    $c->stash->{rec_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, $rec_cols);

    $c->stash(
        template => 'subscriber/master.tt',
    );

    $self->underrun_catchup($c);

    $c->stash->{prov_lock} = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c,
        attribute => 'lock',
        prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
    );
}

sub details :Chained('master') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole('subscriberadmin') {
    my ($self, $c) = @_;

    $self->underrun_catchup($c);

    $c->stash->{prov_lock} = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c,
        attribute => 'lock',
        prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
    );
    my $locklevel = $c->stash->{prov_lock}->first ? $c->stash->{prov_lock}->first->value : 0;
    $c->stash->{prov_lock_string} = NGCP::Panel::Utils::Subscriber::get_lock_string($locklevel);
}

sub voicemails :Chained('master') :PathPart('voicemails') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(
        template => 'subscriber/voicemail.tt'
    );
}

sub recordings :Chained('master') :PathPart('recordings') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(
        template => 'subscriber/recording.tt'
    );
}

sub calllist_master :Chained('base') :PathPart('calls') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash->{callid_enc} = $c->req->params->{callid};
    if($c->stash->{callid_enc}) {
        $c->stash->{callid} = decode_base64url($c->stash->{callid_enc});
    }
    my $call_cols = [
        # NO SEARCH FOR UNINDEXED COLUMNS !!!
        { name => "id", int_search => 1, title => $c->loc('#'), },
        { name => "direction", search => 0, literal_sql => 'if(source_user_id = "'.$c->stash->{subscriber}->uuid.'", "outgoing", "incoming")', },
        #{ name => "source_user", strict_search => 1, 'no_column' => 1, },
        { name => "source_cli", strict_search => 1, title => $c->loc('Caller'), },
        #{ name => "destination_user", strict_search => 1, 'no_column' => 1, },
        { name => "destination_user_in", strict_search => 1, title => $c->loc('Callee'), },
        { name => "clir", search => 0, title => $c->loc('CLIR') },
        { name => "source_customer_billing_zones_history.detail", search => 0, title => $c->loc('Billing zone'), }, #index required...
        { name => "call_status", search => 0, title => $c->loc('Status') },
        { name => "start_time", search_from_epoch => 1, search_to_epoch => 1, title => $c->loc('Start Time') },
        { name => "duration", search => 0, title => $c->loc('Duration'), show_total => 'sum' },
        { name => "cdr_mos_data.mos_average", search => 0, title => $c->loc('MOS avg') },
        { name => "cdr_mos_data.mos_average_packetloss", search => 0, title => $c->loc('MOS packetloss') },
        { name => "cdr_mos_data.mos_average_jitter", search => 0, title => $c->loc('MOS jitter') },
        { name => "cdr_mos_data.mos_average_roundtrip", search => 0, title => $c->loc('MOS roundtrip')  },
    ];
    push @{ $call_cols }, (
        { name => "call_id", strict_search => 1, title => $c->loc('Call-ID'), },
    ) if($c->user->roles eq "admin" || $c->user->roles eq "reseller");

    my $vat_factor = $c->config->{appearance}{cdr_apply_vat} && $c->stash->{subscriber}->contract->add_vat
        ? "* " . (1 + $c->stash->{subscriber}->contract->vat_rate / 100)
        : "";
    $c->log->debug("using vat_factor '$vat_factor'");

    push @{ $call_cols }, (
        { name => "total_customer_cost", search => 0, title => $c->loc('Cost'), show_total => 'sum',
            literal_sql => 'if(source_user_id = "'.$c->stash->{subscriber}->uuid.'", source_customer_cost, destination_customer_cost)'.$vat_factor },
    ) ;
    $c->stash->{calls_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, $call_cols);
}


sub calllist :Chained('calllist_master') :PathPart('') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(
        template => 'subscriber/calllist.tt'
    );
}

sub reglist :Chained('master') :PathPart('regdevices') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(
        template => 'subscriber/reglist.tt'
    );
}

sub edit_master :Chained('master') :PathPart('edit') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $subscriber = $c->stash->{subscriber};
    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;

    my $form; my $pbx_ext; my $is_admin; my $subadmin_pbx;
    my $base_number;

    if($subscriber->contract->product->class eq "pbxaccount") {
        $c->stash(customer_id => $subscriber->contract->id);
        if($subscriber->provisioning_voip_subscriber->is_pbx_pilot) {
            if($c->user->roles eq 'subscriberadmin') {
                $subadmin_pbx = 1;
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadminNoGroup", $c);
            } else {
                $is_admin = 1;
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxSubscriberEdit", $c);
            }
        } else {
            $base_number = $c->stash->{pilot}->primary_number;

            if($c->user->roles eq 'subscriberadmin') {
                $subadmin_pbx = 1;
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadmin", $c);
            } else {
                $is_admin = 1;
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxExtensionSubscriber", $c);
                $form->field('username')->inactive(1);
            }
            $pbx_ext = 1;
        }

    } else {
        if($c->user->roles eq 'subscriberadmin') {
            $subadmin_pbx = 1;
            $c->stash(customer_id => $subscriber->contract->id);
            $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadminNoGroup", $c);
        } else {
            $form = NGCP::Panel::Form::get("NGCP::Panel::Form::SubscriberEdit", $c);
            $is_admin = 1;
        }
    }

    my $posted = ($c->request->method eq 'POST');

    my $params = {};
    my $lock = $c->stash->{prov_lock};
    # we don't change this on edit
    $c->request->params->{username} = $prov_subscriber->username;
    if ($subadmin_pbx) {
        #don't change the status
        $c->request->params->{status} = $subscriber->status;
    }
    unless($posted) {
        $params->{profile_set}{id} = $prov_subscriber->voip_subscriber_profile_set ?
            $prov_subscriber->voip_subscriber_profile_set->id : undef;
        $params->{profile}{id} = $prov_subscriber->voip_subscriber_profile ?
            $prov_subscriber->voip_subscriber_profile->id : undef;
        $params->{webusername} = $prov_subscriber->webusername;
        if (($c->user->roles eq 'admin' || $c->user->roles eq 'reseller') && $c->user->show_passwords) {
            $params->{webpassword} = $prov_subscriber->webpassword;
            $params->{password} = $prov_subscriber->password;
        }
        $params->{administrative} = $prov_subscriber->admin;
        if($subscriber->primary_number) {
            $params->{e164}->{cc} = $subscriber->primary_number->cc;
            $params->{e164}->{ac} = $subscriber->primary_number->ac;
            $params->{e164}->{sn} = $subscriber->primary_number->sn;
        }
        if(defined $prov_subscriber->pbx_extension) {
            $params->{pbx_extension} = $prov_subscriber->pbx_extension;
        }

        if($subscriber->contact) {
            $params->{email} = $subscriber->contact->email;
            $params->{timezone}{name} = $subscriber->contact->timezone;
        }

        my $display_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => 'display_name', prov_subscriber => $prov_subscriber);
        if($display_pref->first) {
            $params->{display_name} = $display_pref->first->value;
        }

        NGCP::Panel::Utils::Subscriber::prepare_alias_select(
            c => $c,
            subscriber => $subscriber,
            params => $params,
        );
        NGCP::Panel::Utils::Subscriber::prepare_group_select(
            c => $c,
            subscriber => $subscriber,
            params => $params,
        );

        $params->{status} = $subscriber->status;
        $params->{external_id} = $subscriber->external_id;

        $params->{lock} = $lock->first ? $lock->first->value : undef;
    }

    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );

    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            $pbx_ext ? ('group.create' => $c->uri_for_action('/customer/pbx_group_create', [$prov_subscriber->account_id])) : (),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        my $old_status = $subscriber->status;
        if($form->values->{status} eq 'terminated' && $old_status ne $form->values->{status}) {
            $self->terminate($c);
            # we never return from here
        }
        my $schema = $c->model('DB');
        try {
            $schema->set_transaction_isolation('READ COMMITTED');
            $schema->txn_do(sub {

                my $email = delete $form->params->{email} || undef;
                my $timezone = delete $form->values->{timezone}{name} || undef;
                if ($subscriber->contact) {
                    $subscriber->contact->update({
                        email => $email,
                        timezone => $timezone,
                    });
                } elsif ($email || $timezone) {
                    my $contact = $c->model('DB')->resultset('contacts')->create({
                        reseller_id => $subscriber->contract->contact->reseller_id,
                        email => $email,
                        timezone => $timezone,
                    });
                    $subscriber->update({ contact_id => $contact->id });
                }
                my $prov_params = {};
                $prov_params->{pbx_extension} = $form->params->{pbx_extension};
                $prov_params->{webusername} = $form->params->{webusername} || undef;
                $prov_params->{webpassword} = $form->params->{webpassword}
                    if($form->params->{webpassword});
                $prov_params->{password} = $form->params->{password}
                    if($form->params->{password});
                if($is_admin) {
                    $prov_params->{admin} = $form->values->{administrative} // $prov_subscriber->admin;
                }
                NGCP::Panel::Utils::Subscriber::update_preferences(
                    c => $c,
                    prov_subscriber => $prov_subscriber,
                    'preferences'   => {
                        display_name  => $form->params->{display_name},
                        cloud_pbx_ext => $form->params->{pbx_extension},
                        #this call will delete the cloud_pbx_ext preference if form param is empty, but form validation shouldn't allow empty value
                    }
                );

                #$old_profile_id is necessary for events
                my $old_profile_id = $prov_subscriber->profile_id;
                my($error,$profile_set,$profile) = NGCP::Panel::Utils::Subscriber::check_profile_set_and_profile($c, $form->values, $subscriber);
                if ($error) {
                    NGCP::Panel::Utils::Message::error(
                        c => $c,
                        error => $error->{error},
                        desc  => $error->{description}
                    );
                    return;
                }
                if($c->user->roles eq "admin" || $c->user->roles eq "reseller") {
                    $prov_params->{profile_set_id} = $profile_set ? $profile_set->id : undef;
                    $prov_params->{profile_id} = $profile ? $profile->id : undef;
                } else {
                    # if the subscriberadmin set the profile, then use it; otherwise
                    # keep it at old value (e.g. if he unset it)
                    if($prov_subscriber->voip_subscriber_profile_set && $profile) {
                        $prov_params->{profile_id} = $profile->id;
                    }
                }

                $prov_subscriber->update($prov_params);

                my $new_group_ids = defined $form->value->{group_select} ?
                    decode_json($form->value->{group_select}) : [];
                NGCP::Panel::Utils::Subscriber::manage_pbx_groups(
                    c            => $c,
                    schema       => $schema,
                    group_ids    => $new_group_ids,
                    subscriber   => $subscriber,
                );

                my $old_ext_id = $subscriber->external_id;
                $subscriber->update({
                    status => $form->params->{status},
                    external_id => $form->field('external_id')->value, # null if empty
                });

                if(defined $subscriber->external_id) {
                    my $ext_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                        c => $c, attribute => 'ext_subscriber_id', prov_subscriber => $prov_subscriber);
                    unless($ext_pref->first) {
                        $ext_pref->create({ value => $subscriber->external_id });
                    } else {
                        $ext_pref->first->update({ value => $subscriber->external_id });
                    }
                } elsif(defined $old_ext_id) {
                    NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                        c => $c, attribute => 'ext_subscriber_id', prov_subscriber => $prov_subscriber)
                    ->delete;
                }
                if($subscriber->status eq 'locked') {
                    $form->values->{lock} ||= 4; # update lock below
                } elsif($old_status eq 'locked' && $subscriber->status eq 'active') {
                    $form->values->{lock} ||= 0; # update lock below
                }

                my $aliases_before = NGCP::Panel::Utils::Events::get_aliases_snapshot(
                    c => $c,
                    schema => $schema,
                    subscriber => $subscriber,
                );

                if(exists $form->params->{alias_select} && $c->stash->{pilot}) {
                    NGCP::Panel::Utils::Subscriber::update_subadmin_sub_aliases(
                        c => $c,
                        schema => $schema,
                        subscriber => $subscriber,
                        contract_id => $subscriber->contract_id,
                        alias_selected => decode_json($form->values->{alias_select}),
                        sadmin => $c->stash->{pilot},
                    );
                }

                if($subscriber->primary_number) {
                    my $old_number = {
                        cc => $subscriber->primary_number->cc,
                        ac => $subscriber->primary_number->ac,
                        sn => $subscriber->primary_number->sn,
                    };
                    if($pbx_ext) {
                        $form->params->{e164}{cc} = $subscriber->primary_number->cc;
                        $form->params->{e164}{ac} = $subscriber->primary_number->ac;
                        $form->params->{e164}{sn} = $base_number->sn . $form->params->{pbx_extension};
                    }

                    NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
                        c => $c,
                        schema => $schema,
                        subscriber_id =>$subscriber->id,
                        reseller_id => $subscriber->contract->contact->reseller_id,
                        exists $form->params->{e164} ? (primary_number => $form->params->{e164}) : (),
                        $subadmin_pbx && $prov_subscriber->admin ? () : (alias_numbers  => $form->values->{alias_number}),
                    );

                    # update the primary number and the cloud_pbx_base_cli pref for all other subscribers
                    # if the primary number of the admin changed
                    $subscriber->discard_changes; # reload row because of potential new number

                    if(defined $subscriber->primary_number) {
                        my $new_number = {
                            cc => $subscriber->primary_number->cc,
                            ac => $subscriber->primary_number->ac,
                            sn => $subscriber->primary_number->sn,
                        };
                        if($subscriber->provisioning_voip_subscriber->admin &&
                           !compare($old_number, $new_number)) {
                            foreach my $sub($c->stash->{subscribers}->all, ( $c->stash->{pbx_groups} ? $c->stash->{pbx_groups}->all : () )) {
                                my $base_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                                        c => $c, attribute => 'cloud_pbx_base_cli',
                                        prov_subscriber => $sub->provisioning_voip_subscriber);
                                my $val = $form->params->{e164}{cc} .
                                          ($form->params->{e164}{ac} // '') .
                                          $form->params->{e164}{sn};
                                if($base_pref->first) {
                                    $base_pref->first->update({ value => $val });
                                } else {
                                    $base_pref->create({ value => $val });
                                }

                                if($sub->id == $subscriber->id) {
                                    next;
                                }
                                unless(defined $sub->provisioning_voip_subscriber->pbx_extension) {
                                    next;
                                }
                                my $num = {
                                    cc => $form->params->{e164}{cc},
                                    ac => $form->params->{e164}{ac},
                                    sn => $form->params->{e164}{sn} . $sub->provisioning_voip_subscriber->pbx_extension,
                                };
                                NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
                                    c => $c,
                                    schema => $schema,
                                    subscriber_id => $sub->id,
                                    reseller_id => $sub->contract->contact->reseller_id,
                                    primary_number => $num,
                                );
                            }
                        }
                    } elsif(defined $subscriber->provisioning_voip_subscriber->pbx_extension) {
                        NGCP::Panel::Utils::Message::error(
                            c     => $c,
                            error => $c->loc('CloudPBX subscriber must have a primary number'),
                            desc  => $c->loc('Failed to update subscriber, CloudPBX must have a primary number'),
                        );
                    } else {
                        NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
                            c => $c,
                            schema => $schema,
                            subscriber_id => $subscriber->id,
                            reseller_id => $subscriber->contract->contact->reseller_id,
                            primary_number => undef,
                        );
                    }
                } else {
                    NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
                        c => $c,
                        schema => $schema,
                        subscriber_id =>$subscriber->id,
                        reseller_id => $subscriber->contract->contact->reseller_id,
                        primary_number => $form->values->{e164},
                        # only update alias list if we're the subadmin but are not editing ourselves,
                        # otherwise we might whipe out our own numbers
                        $subadmin_pbx && $prov_subscriber->admin ? () : (alias_numbers  => $form->values->{alias_number}),
                    );
                }

                NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c, contract => $subscriber->contract);

                $form->values->{lock} ||= 0;
                NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                    c => $c,
                    prov_subscriber => $subscriber->provisioning_voip_subscriber,
                    level => $form->values->{lock},
                ) if ($subscriber->provisioning_voip_subscriber);

                NGCP::Panel::Utils::Events::insert_profile_events(
                    c => $c, schema => $schema, subscriber_id => $subscriber->id,
                    old => $old_profile_id, new => $prov_subscriber->profile_id,
                    %$aliases_before,
                );

            });
            delete $c->session->{created_objects}->{group};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated subscriber'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to update subscriber'),
            );
        }


        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
    }

    $c->stash(
        edit_flag => 1,
        description => $c->loc('Subscriber Master Data'),
        form => $form,
        close_target => $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]),
    );

}

sub order_pbx_items :Chained('master') :PathPart('orderpbxitems') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) : AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c) = @_;

    my $move_id  = $c->req->params->{move};
    my $direction = $c->req->params->{where};

    my $subscriber = $c->stash->{subscriber};
    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;

    my $items = $c->stash->{subscriber_pbx_items} // [] ;
    if(@$items){
        if(defined $move_id){
            for( my $i=0; $i <= $#$items; $i++ ){
                if($move_id == $items->[$i]->id){
                    my $i_subling = $i + ( ( $direction eq 'up' ) ? -1 : 1 );
                    @{$items}[$i,$i_subling] = @{$items}[$i_subling,$i];
                    last;
                }
            }
            NGCP::Panel::Utils::Subscriber::manage_pbx_groups(
                c          => $c,
                schema     => $c->model('DB'),
                subscriber => $subscriber,
                ( $prov_subscriber->is_pbx_group ? 'groupmembers' : 'groups' ) => $items,
            );
        }
        $c->stash->{subscriber_pbx_items} = NGCP::Panel::Utils::Subscriber::get_subscriber_pbx_items(
            c          => $c,
            schema     => $c->model('DB'),
            subscriber => $subscriber ,
        );
    }
    $c->stash->{template} = 'subscriber/pbx_group_items.tt';
    $c->detach( $c->view('TT') );
}

sub aliases_ajax :Chained('master') :PathPart('ordergroups') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c) = @_;

    my $subscriber = $c->stash->{subscriber};
    my @alias_nums = ();
    my $num_rs = $c->model('DB')->resultset('voip_numbers')->search_rs({
        'subscriber.contract_id' => $subscriber->contract_id,
        'voip_subscribers.id' => undef,
    },{
        prefetch => ['subscriber', 'voip_subscribers'],
    });

    my $alias_columns = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "number", search => 1, title => $c->loc('Number'), literal_sql => "concat(cc,' ',ac,' ',sn)"},
        { name => "subscriber.username", search => 1, title => $c->loc('Subscriber') },
    ]);

    NGCP::Panel::Utils::Datatables::process($c, $num_rs, $alias_columns);

    $c->detach( $c->view("JSON") );
}


sub webpass :Chained('base') :PathPart('webpass') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);


    $c->stash(
        template => 'subscriber/edit_webpass.tt',
    );
}

sub webpass_edit :Chained('base') :PathPart('webpass/edit') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);


    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::EditWebpass", $c);
    my $posted = ($c->request->method eq 'POST');


    $form->process(
        posted => $posted,
        params => $c->request->params,
    );

    if($posted && $form->validated) {

        my $schema = $c->model('DB');
        try {
            my $subscriber = $c->stash->{subscriber};
            my $prov_subscriber = $subscriber->provisioning_voip_subscriber;
            $schema->txn_do(sub {
                $prov_subscriber->update({
                    webpassword => $form->values->{webpassword} });
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated password'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to update subscriber (webpassword)'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriber/webpass', [$c->req->captures->[0]]));
    }

    $c->stash(
        edit_flag => 1,
        form => $form,
        close_target => $c->uri_for_action('/subscriber/webpass', [$c->req->captures->[0]]),
        template => 'subscriber/edit_webpass.tt',
    );
}

sub edit_voicebox :Chained('base') :PathPart('preferences/voicebox/edit') :Args() {
    my ($self, $c, $attribute, @additions) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $form;
    my $posted = ($c->request->method eq 'POST');
    my $vm_user = $c->stash->{subscriber}->provisioning_voip_subscriber->voicemail_user;
    unless($vm_user) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => "no voicemail user found for subscriber uuid ".$c->stash->{subscriber}->uuid,
            desc  => $c->loc('Failed to find voicemail user.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }
    my $params;
    my $attribute_name = $attribute;
    try {
        SWITCH: for ($attribute) {
            /^pin$/ && do {
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Voicemail::Pin", $c);
                $params = { 'pin' => $vm_user->password };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $vm_user->update({ password => $form->field('pin')->value });
                }
                last SWITCH;
            };
            /^email$/ && do {
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Voicemail::Email", $c);
                $params = { 'email' => $vm_user->email };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $vm_user->update({ email => $form->values->{email} // '' });
                }
                last SWITCH;
            };
            /^pager$/ && do {
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Voicemail::Pager", $c);
                $params = { 'sms_number' => $vm_user->pager };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $vm_user->update({ pager => $form->values->{sms_number} // ''});
                }
                last SWITCH;
            };
            /^attach$/ && do {
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Voicemail::Attach", $c);
                $params = { 'attach' => $vm_user->attach eq 'yes' ? 1 : 0 };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $vm_user->update({ attach => $form->field('attach')->value ? 'yes' : 'no' });
                }
                last SWITCH;
            };
            /^delete$/ && do {
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Voicemail::Delete", $c);
                $params = { 'delete' => $vm_user->get_column('delete') eq 'yes' ? 1 : 0 };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $vm_user->update({
                        delete => $form->field('delete')->value ? 'yes' : 'no',
                        # force attach if delete flag is set, otherwise message will be lost
                        'attach' => $form->field('delete')->value ? 'yes' : $vm_user->attach,
                    });
                }
                last SWITCH;
            };
            /^voicemailgreeting$/ && do {
                my ($action, $type) = @additions;
                try{
                    if( !grep{ $action eq $_ } (qw/edit delete download/) ){
                        die('Wrong voicemail greeting action.');
                    }
                    if( !grep{ $type eq $_ } (qw/unavail busy/) ){
                        die('Wrong voicemail greeting type.');
                    }
                    my $dir = NGCP::Panel::Utils::Subscriber::get_subscriber_voicemail_directory(c => $c, subscriber => $c->stash->{subscriber}, dir => $type);
                    $attribute_name = $c->loc('voicemail greeting "'.$type.'"');
                    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Voicemail::Greeting", $c);
                    $params = {};
                    $c->req->params->{greetingfile} = $c->req->upload('greetingfile');
                    $form->process(params => $posted ? $c->req->params : $params);
                    NGCP::Panel::Utils::Navigation::check_form_buttons(
                        c => $c,
                        form => $form,
                        fields => {},
                        back_uri => $c->req->uri,
                    );
                    if('delete' eq $action){
                        $vm_user->voicemail_spools->search_rs({
                            'dir'       => $dir,
                            'msgnum'    => '-1',
                        })->delete;
                        NGCP::Panel::Utils::Message::info(
                            c     => $c,
                            log   => 'Voicemail greeting '.$type.' for the subscriber_id '.$c->stash->{subscriber}->id.' deleted.',
                            desc  => $c->loc('Voicemail greeting "'.$type.'" deleted'),
                        );
                        NGCP::Panel::Utils::Navigation::back_or($c,
                            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
                        return;
                    }elsif('download' eq $action){
                        my $recording = $vm_user->voicemail_spools->search_rs({
                            'dir'       => $dir,
                            'msgnum'    => '-1',
                        })->first;
                        if($recording){
                            $recording = $recording->recording;
                            $c->res->headers(HTTP::Headers->new(
                                'Content-Type' => 'audio/x-wav',
                                #'Content-Type' => 'application/octet-stream',
                                'Content-Disposition' => sprintf('attachment; filename=%s', "voicemail_".${type}."_".$c->stash->{subscriber}->id.".wav")
                            ));
                            $c->res->body($recording);
                            return;
                        }
                    }elsif($posted){
                        my $greetingfile = delete $form->values->{'greetingfile'};
                        my $greeting_converted_ref;
                        try {
                            NGCP::Panel::Utils::Subscriber::convert_voicemailgreeting(
                                c => $c,
                                upload => $greetingfile,
                                filepath => $greetingfile->tempname,
                                converted_data_ref => \$greeting_converted_ref );
                        } catch($e) {
                            NGCP::Panel::Utils::Message::error(
                                c    => $c,
                                log  => $e,
                                desc => $c->loc($e),
                            );
                            NGCP::Panel::Utils::Navigation::back_or($c,
                                $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
                            return;
                        }
                        if($form->validated) {
                            if('edit' eq $action){
                                $vm_user->voicemail_spools->update_or_create({
                                    'recording'      => $$greeting_converted_ref,
                                    'dir'            => $dir,
                                    'origtime'       => time(),#just to make inflate possible. Really we don't need this value
                                    'mailboxcontext' => 'default',
                                    'msgnum'         => '-1',
                                });
                            }
                        }
                    }
                } catch($e) {
                    NGCP::Panel::Utils::Message::error(
                        c     => $c,
                        log   => $e,
                        desc  => $c->loc($e),
                    );
                    NGCP::Panel::Utils::Navigation::back_or($c,
                        $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
                    return;
                }
                last SWITCH;
            };
            # default
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                log   => "trying to set invalid voicemail param '$attribute' for subscriber uuid ".$c->stash->{subscriber}->uuid,
                desc  => $c->loc('Invalid voicemail setting'),
            );
            NGCP::Panel::Utils::Navigation::back_or($c,
                $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
            return;
        } # SWITCH
        if($posted && $form->validated) {
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated voicemail setting'),
            );
            NGCP::Panel::Utils::Navigation::back_or($c,
                $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
            return;
        }
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to update voicemail setting.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => $attribute_name || $attribute,
        cf_form => $form,
    );
}

sub edit_fax :Chained('base') :PathPart('preferences/fax/edit') :Args(1) {
    my ($self, $c, $attribute) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $form;
    my $posted = ($c->request->method eq 'POST');
    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $faxpref = $prov_subscriber->voip_fax_preference;
    my $params = {};
    my $faxpref_rs = $c->model('DB')->resultset('voip_fax_preferences')->search({
                            subscriber_id => $prov_subscriber->id
                        });
    if(!$faxpref) {
        $faxpref = $faxpref_rs->create({});
    }

    try {
        SWITCH: for ($attribute) {
            /^name$/ && do {
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Faxserver::Name", $c);
                $params = { 'name' => $faxpref->name };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $faxpref->update({ name => $form->field('name')->value });
                }
                last SWITCH;
            };
            /^active$/ && do {
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Faxserver::Active", $c);
                $params = { 'active' => $faxpref->active };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $faxpref->update({ active => $form->field('active')->value });
                }
                last SWITCH;
            };
            /^t38$/ && do {
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Faxserver::T38", $c);
                $params = { 't38' => $faxpref->t38 };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $faxpref->update({ t38 => $form->field('t38')->value });
                }
                last SWITCH;
            };
            /^ecm$/ && do {
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Faxserver::ECM", $c);
                $params = { 'ecm' => $faxpref->ecm };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $faxpref->update({ ecm => $form->field('ecm')->value });
                }
                last SWITCH;
            };
            /^destinations$/ && do {
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Faxserver::Destination", $c);
                unless($posted) {
                    my @dests = ();
                    for my $dest($prov_subscriber->voip_fax_destinations->all) {
                        push @dests, {
                            destination => $dest->destination,
                            filetype => $dest->filetype,
                            incoming => $dest->incoming,
                            outgoing => $dest->outgoing,
                            status => $dest->status,
                        }
                    }
                    $params->{destination} = \@dests;
                }
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    for my $dest($prov_subscriber->voip_fax_destinations->all) {
                        $dest->delete;
                    }
                    for my $dest($form->field('destination')->fields) {
                        $prov_subscriber->voip_fax_destinations->create({
                            destination => $dest->field('destination')->value,
                            filetype => $dest->field('filetype')->value,
                            incoming => $dest->field('incoming')->value,
                            outgoing => $dest->field('outgoing')->value,
                            status => $dest->field('status')->value,
                        });
                    }
                }
                last SWITCH;
            };
            # default
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                log   => "trying to set invalid fax param '$attribute' for subscriber uuid ".$c->stash->{subscriber}->uuid,
                desc  => $c->loc('Invalid fax setting.'),
            );
            NGCP::Panel::Utils::Navigation::back_or($c,
                $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
            return;
        } # SWITCH
        if($posted && $form->validated) {
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated fax setting'),
            );
            NGCP::Panel::Utils::Navigation::back_or($c,
                $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
            return;
        }
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to update fax setting'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => $attribute,
        cf_form => $form,
    );
}

sub edit_mail_to_fax :Chained('base') :PathPart('preferences/mail_to_fax/edit') :Args(1) {
    my ($self, $c, $attribute) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $form;
    my $posted = ($c->request->method eq 'POST');
    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $mtf_pref = $prov_subscriber->voip_mail_to_fax_preference;
    my $params = {};
    my $mtf_pref_rs = $c->model('DB')->resultset('voip_mail_to_fax_preferences')->search({
                            subscriber_id => $prov_subscriber->id
                        });
    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            $mtf_pref ||= $mtf_pref_rs->create({});
            SWITCH: for ($attribute) {
                /^active$/ && do {
                    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::MailToFax::Active", $c);
                    $params = { 'active' => $mtf_pref->active };
                    $form->process(params => $posted ? $c->req->params : $params);
                    NGCP::Panel::Utils::Navigation::check_form_buttons(
                        c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                    );
                    if($posted && $form->validated) {
                        $mtf_pref->update({ active => $form->field('active')->value });
                    }
                    last SWITCH;
                };
                /^secret_key$/ && do {
                    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::MailToFax::SecretKey", $c);
                    $params = { secret_key => $mtf_pref->secret_key };
                    $form->process(params => $posted ? $c->req->params : $params);
                    NGCP::Panel::Utils::Navigation::check_form_buttons(
                        c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                    );
                    if($posted && $form->validated) {
                        $mtf_pref->update({
                            secret_key => $form->field('secret_key')->value,
                            last_secret_key_modify => NGCP::Panel::Utils::DateTime::current_local,
                        });
                    }
                    last SWITCH;
                };
                /^secret_key_renew$/ && do {
                    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::MailToFax::SecretKeyRenew", $c);
                    $params = { secret_key_renew => $mtf_pref->secret_key_renew, };
                    $form->process(params => $posted ? $c->req->params : $params);
                    NGCP::Panel::Utils::Navigation::check_form_buttons(
                        c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                    );
                    if($posted && $form->validated) {
                        $mtf_pref->update({
                            secret_key_renew => $form->field('secret_key_renew')->value,
                        });
                    }
                    last SWITCH;
                };
                /^secret_renew_notify$/ && do {
                    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::MailToFax::SecretRenewNotify", $c);
                    unless($posted) {
                        my @notify_list = ();
                        for my $notify($prov_subscriber->voip_mail_to_fax_secrets_renew_notify->all) {
                            push @notify_list, {
                                destination => $notify->destination,
                            }
                        }
                        $params->{secret_renew_notify} = \@notify_list;
                    }
                    $form->process(params => $posted ? $c->req->params : $params);
                    NGCP::Panel::Utils::Navigation::check_form_buttons(
                        c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                    );
                    if($posted && $form->validated) {
                        for my $notify($prov_subscriber->voip_mail_to_fax_secrets_renew_notify->all) {
                            $notify->delete;
                        }
                        for my $notify($form->field('secret_renew_notify')->fields) {
                            $prov_subscriber->voip_mail_to_fax_secrets_renew_notify->create({
                                destination => $notify->field('destination')->value,
                            });
                        }
                    }
                    last SWITCH;
                };
                /^acl$/ && do {
                    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::MailToFax::ACL", $c);
                    unless($posted) {
                        my @acl_list = ();
                        for my $acl($prov_subscriber->voip_mail_to_fax_acls->all) {
                            push @acl_list, {
                                from_email => $acl->from_email,
                                received_from => $acl->received_from,
                                destination => $acl->destination,
                                use_regex => $acl->use_regex,
                            }
                        }
                        $params->{acl} = \@acl_list;
                    }
                    $form->process(params => $posted ? $c->req->params : $params);
                    NGCP::Panel::Utils::Navigation::check_form_buttons(
                        c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                    );
                    if($posted && $form->validated) {
                        for my $acl($prov_subscriber->voip_mail_to_fax_acls->all) {
                            $acl->delete;
                        }
                        for my $acl($form->field('acl')->fields) {
                            $prov_subscriber->voip_mail_to_fax_acls->create({
                                from_email => $acl->field('from_email')->value,
                                received_from => $acl->field('received_from')->value,
                                destination => $acl->field('destination')->value,
                                use_regex => $acl->field('use_regex')->value,
                            });
                        }
                    }
                    last SWITCH;
                };
                # default
                NGCP::Panel::Utils::Message::error(
                    c     => $c,
                    log   => "trying to set invalid fax param '$attribute' for subscriber uuid ".$c->stash->{subscriber}->uuid,
                    desc  => $c->loc('Invalid mailtofax setting.'),
                );
                NGCP::Panel::Utils::Navigation::back_or($c,
                    $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
                return;
            } # SWITCH
        });
        if($posted && $form->validated) {
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated mailtofax setting'),
            );
            NGCP::Panel::Utils::Navigation::back_or($c,
                $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
            return;
        }
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to update mailtofax setting'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => $attribute,
        cf_form => $form,
    );
}

sub edit_reminder :Chained('base') :PathPart('preferences/reminder/edit') {
    my ($self, $c, $attribute) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $posted = ($c->request->method eq 'POST');
    my $reminder = $c->stash->{subscriber}->provisioning_voip_subscriber->voip_reminder;
    my $params = {};

    if(!$posted && $reminder) {
        $params = { 'time' => $reminder->column_time, recur => $reminder->recur, active => $reminder->active};
    }

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Reminder", $c);
    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {

        try {
            if($form->field('time')->value) {
                my $t = $form->field('time')->value;
                $t =~ s/^(\d+:\d+)(:\d+)?$/$1/; # strip seconds
                if($reminder) {
                    $reminder->update({
                        time => $t,
                        recur => $form->field('recur')->value,
                        active => $form->values->{active},
                    });
                } else {
                    $c->model('DB')->resultset('voip_reminder')->create({
                        subscriber_id => $c->stash->{subscriber}->provisioning_voip_subscriber->id,
                        time => $t,
                        recur => $form->field('recur')->value,
                        active => $form->values->{active},
                    });
                }
            } elsif($reminder) {
                $reminder->delete;
            }
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated reminder setting'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to update reminder setting.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => 'Reminder',
        cf_form => $form,
    );
}


sub delete_reminder :Chained('base') :PathPart('preferences/reminder/delete') {
    my ($self, $c, $attribute) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $reminder = $c->stash->{subscriber}->provisioning_voip_subscriber->voip_reminder;
    if($reminder){
        try {
            $reminder->delete;
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully cleared reminder setting'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to clear reminder setting.'),
            );
        }
    }
    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
}


sub _process_calls_rows {
    my ($c,$rs) = @_;
    my $owner = {
        subscriber => $c->stash->{subscriber},
        customer => $c->stash->{subscriber}->contract,
    };
    NGCP::Panel::Utils::Datatables::process(
        $c, $rs, $c->stash->{calls_dt_columns},
        sub {
            my ($result) = @_;
            my %data = ();
            my $resource = NGCP::Panel::Utils::CallList::process_cdr_item($c, $result, $owner);
            if (!defined $resource->{other_cli}) {
                $resource->{other_cli} = $c->loc('Anonymous');
            }
            if ($resource->{direction} eq "out") {
                $data{source_user} = uri_unescape($resource->{own_cli});
                $data{destination_user} = uri_unescape($resource->{other_cli});
            } else {
                $data{source_user} = uri_unescape($resource->{other_cli});
                $data{destination_user} = uri_unescape($resource->{own_cli});
            }
            $data{clir} = $resource->{clir};
            $data{duration} = (defined $result->duration ? sprintf("%.2f s", $result->duration) : "");
            $data{duration} = (defined $result->duration ? NGCP::Panel::Utils::DateTime::sec_to_hms($c,$result->duration,3) : "");
            $data{total_customer_cost} = "";
            eval {
                $data{total_customer_cost} = sprintf("%.2f", $result->get_column('total_customer_cost') / 100.0) if defined $result->get_column('total_customer_cost');
            };
            $data{call_id_url} = encode_base64url($resource->{call_id});
            return %data;
        },
        { 'total_row_func' => sub {
                my ($result) = @_;
                my %data = ();
                $data{duration} = (defined $result->{duration} ? NGCP::Panel::Utils::DateTime::sec_to_hms($c,$result->{duration},3) : "");
                $data{total_customer_cost} = (defined $result->{total_customer_cost} ? sprintf("%.2f", $result->{total_customer_cost} / 100.0) : "");
                return %data;
            },
          'count_limit' => 1000,
        }
    );
}

sub ajax_calls :Chained('calllist_master') :PathPart('list/ajax') :Args(0) {
    my ($self, $c) = @_;
    my $callid = $c->stash->{callid};
    my $out_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$c->model('DB')->resultset('cdr')->search({
        source_user_id => $c->stash->{subscriber}->uuid,
        ($callid ? (call_id => $callid) : ()),
    }),NGCP::Panel::Utils::CallList::SUPPRESS_OUT);
    my $in_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$c->model('DB')->resultset('cdr')->search({
        destination_user_id => $c->stash->{subscriber}->uuid,
        source_user_id => { '!=' => $c->stash->{subscriber}->uuid },
        ($callid ? (call_id => $callid) : ()),
    }),NGCP::Panel::Utils::CallList::SUPPRESS_IN);

    $out_rs = NGCP::Panel::Utils::Datatables::apply_dt_joins_filters($c, $out_rs, $c->stash->{calls_dt_columns});
    $in_rs = NGCP::Panel::Utils::Datatables::apply_dt_joins_filters($c, $in_rs, $c->stash->{calls_dt_columns});
    my $rs = $out_rs->union_all($in_rs);

    _process_calls_rows($c,$rs);

    $c->detach( $c->view("JSON") );
}

sub ajax_calls_in :Chained('calllist_master') :PathPart('list/ajax/in') :Args(0) {
    my ($self, $c) = @_;

    my $rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$c->model('DB')->resultset('cdr')->search({
        destination_user_id => $c->stash->{subscriber}->uuid,
    }),NGCP::Panel::Utils::CallList::SUPPRESS_IN);

    _process_calls_rows($c,$rs);

    $c->detach( $c->view("JSON") );
}

sub ajax_calls_out :Chained('calllist_master') :PathPart('list/ajax/out') :Args(0) {
    my ($self, $c) = @_;

    my $rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$c->model('DB')->resultset('cdr')->search({
        source_user_id => $c->stash->{subscriber}->uuid,
    }),NGCP::Panel::Utils::CallList::SUPPRESS_OUT);

    _process_calls_rows($c,$rs);

    $c->detach( $c->view("JSON") );
}

sub ajax_call_details :Chained('master') :PathPart('calls/ajax') :Args(1) {
    my ($self, $c, $call_id) = @_;
    my $call = $c->model('DB')->resultset('cdr')->search_rs({
            id => $call_id,
        },{
            join => 'cdr_mos_data',
            '+select' => [qw/cdr_mos_data.mos_average cdr_mos_data.mos_average_packetloss cdr_mos_data.mos_average_jitter cdr_mos_data.mos_average_roundtrip/],
            '+as' => [qw/mos_average mos_average_packetloss mos_average_jitter mos_average_roundtrip/],
        }
    );
    $c->stash(
        template => 'subscriber/call_details.tt',
        call     => { $call->first->get_inflated_columns } );
    $c->detach( $c->view('TT') );
}

sub ajax_registered :Chained('master') :PathPart('registered/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $reg_rs = NGCP::Panel::Utils::Subscriber::get_subscriber_location_rs(
        $c,
        {
            username => $c->stash->{subscriber}->username,
            $c->config->{features}->{multidomain} ? (domain => $c->stash->{subscriber}->domain->domain) : (),
        }
    );
    NGCP::Panel::Utils::Datatables::process($c, $reg_rs, $c->stash->{reg_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub ajax_voicemails :Chained('master') :PathPart('voicemails/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $vm_rs = $c->model('DB')->resultset('voicemail_spool')->search({
        mailboxuser => $c->stash->{subscriber}->uuid,
        msgnum => { '>=' => 0 },
    });
    NGCP::Panel::Utils::Datatables::process($c, $vm_rs, $c->stash->{vm_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub ajax_recordings :Chained('master') :PathPart('recordings/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $rec_rs = $c->model('DB')->resultset('recording_calls')->search({
        'status' => { -in => ['completed', 'confirmed'] },
        'recording_metakeys.key' => 'uuid',
        'recording_metakeys.value' => $c->stash->{subscriber}->uuid,
    }, {
        join => 'recording_metakeys'
    });

    NGCP::Panel::Utils::Datatables::process($c, $rec_rs, $c->stash->{rec_dt_columns},
        sub {
            my $item = shift;
            my %result;
            $result{call_id} = $item->call_id =~ s/(_b2b-1|_pbx-1)+$//r;
            # similar to Utils::CallList::process_cdr_item
            $result{call_id_url} = encode_base64url($result{call_id});
            return %result;
        }
    );

    $c->detach( $c->view("JSON") );
}

sub ajax_recording_streams :Chained('recording') :PathPart('streams/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $rs = $c->stash->{recording}->recording_streams;
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{streams_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub ajax_captured_calls :Chained('master') :PathPart('callflow/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $rs = $c->model('Storage')->resultset('messages')->search({
        -or => [
            'me.caller_uuid' => $c->stash->{subscriber}->uuid,
            'me.callee_uuid' => $c->stash->{subscriber}->uuid,
        ],
    }, {
        order_by => { -desc => 'me.timestamp' },
        group_by => 'me.call_id',
    });

    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{capture_dt_columns},
        sub {
            my $item = shift;
            my %result;
            $result{call_id} = $item->call_id =~ s/(_b2b-1|_pbx-1)+$//r;
            # similar to Utils::CallList::process_cdr_item
            $result{call_id_url} = encode_base64url($result{call_id});
            return %result;
        }
    );
    $c->detach( $c->view("JSON") );
}

sub voicemail :Chained('master') :PathPart('voicemail') :CaptureArgs(1) {
    my ($self, $c, $vm_id) = @_;

    my $rs = $c->model('DB')->resultset('voicemail_spool')->search({
         mailboxuser => $c->stash->{subscriber}->uuid,
         id => $vm_id,
    });
    unless($rs->first) {
        NGCP::Panel::Utils::Message::error(
            c    => $c,
            log  => "no such voicemail file with id '$vm_id' for uuid ".$c->stash->{subscriber}->uuid,
            desc => $c->loc('No such voicemail file.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
    }
    $c->stash->{voicemail} = $rs->first;
}

sub play_voicemail :Chained('voicemail') :PathPart('play') :Args(0) {
    my ($self, $c) = @_;

    my $file = $c->stash->{voicemail};
    my $recording = $file->recording;
    my $data;

    try {
        $data= NGCP::Panel::Utils::Sounds::transcode_data(
            $recording, 'WAV', 'WAV');
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Transcode of audio file failed'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
    }

    NGCP::Panel::Utils::Subscriber::mark_voicemail_read( 'c' => $c, 'voicemail' => $c->stash->{voicemail} );
    NGCP::Panel::Utils::Subscriber::vmnotify( 'c' => $c, 'voicemail' => $c->stash->{voicemail} );
    my $filename = NGCP::Panel::Utils::Subscriber::get_voicemail_filename($c,$file);
    $c->response->header('Content-Disposition' => 'attachment; filename="'.$filename.'"');
    $c->response->content_type('audio/x-wav');
    $c->response->body($data);
}

sub delete_voicemail :Chained('voicemail') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    try {
        $c->stash->{voicemail}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{voicemail}->get_inflated_columns },
            desc => $c->loc('Successfully deleted voicemail'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete voicemail message'),
        );
    }
    NGCP::Panel::Utils::Subscriber::vmnotify( c => $c, voicemail => $c->stash->{voicemail} );
    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
}

sub recording :Chained('master') :PathPart('recording') :CaptureArgs(1) {
    my ($self, $c, $rec_id) = @_;

    my $rs = $c->model('DB')->resultset('recording_calls')->search({
         'me.id' => $rec_id,
         'recording_metakeys.key' => 'uuid',
         'recording_metakeys.value' => $c->stash->{subscriber}->uuid,
    },{
        join => ['recording_streams', 'recording_metakeys'],
    });
    unless($rs->first) {
        NGCP::Panel::Utils::Message::error(
            c    => $c,
            log  => "no such recording with id '$rec_id' for uuid ".$c->stash->{subscriber}->uuid,
            desc => $c->loc('No such recording'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
    }
    $c->stash->{recording} = $rs->first;
}

sub recording_streams :Chained('recording') :PathPart('streams') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(
        template => 'subscriber/recording_streams.tt'
    );
}

sub recording_stream :Chained('recording') :PathPart('streams') :CaptureArgs(1) {
    my ($self, $c, $stream_id) = @_;

    my $stream = $c->stash->{recording}->recording_streams->find($stream_id);
    unless($stream) {
        NGCP::Panel::Utils::Message::error(
            c    => $c,
            log  => "no such recording with id '$stream_id' for recording id ".$c->stash->{recording}->id,
            desc => $c->loc('No such recording file'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
    }
    $c->stash->{stream} = $stream;
}

sub play_stream :Chained('recording_stream') :PathPart('play') :Args(0) {
    my ($self, $c) = @_;

    # TODO: fix to be able to select certain stream
    my $stream = $c->stash->{stream};
    my $data = read_file($stream->full_filename);
    my $mime_type;
    if($stream->file_format eq "wav") {
        $mime_type = 'audio/x-wav';
    } elsif($stream->file_format eq "mp3") {
        $mime_type = 'audio/mpeg';
    } else {
        $mime_type = 'application/octet-stream';
    }

    $c->response->header('Content-Disposition' => 'attachment; filename="call-recording-'.$stream->id.'.'.$stream->file_format.'"');
    $c->response->content_type($mime_type);
    $c->response->body($data);
}

sub delete_recording :Chained('recording') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    try {
        $c->stash->{recording}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{recording}->get_inflated_columns },
            desc => $c->loc('Successfully deleted recording'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete recording'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
}


sub registered :Chained('master') :PathPart('registered') :CaptureArgs(1) {
    my ($self, $c, $reg_id) = @_;

    my $s = $c->stash->{subscriber}->provisioning_voip_subscriber;

    $c->log->error("+++++ getting subscriber location rs");
    my $reg_rs = NGCP::Panel::Utils::Subscriber::get_subscriber_location_rs(
        $c, { id => $reg_id },
    );

    $c->stash->{registered} = $reg_rs->first;
    unless($c->stash->{registered}) {
        NGCP::Panel::Utils::Message::error(
            c    => $c,
            log  => "failed to find location id '$reg_id' for subscriber uuid " . $s->uuid,
            desc => $c->loc('Failed to find registered device.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
    }
}

sub delete_registered :Chained('registered') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $ret;

    try {
        NGCP::Panel::Utils::Kamailio::delete_location_contact($c,
            $c->stash->{subscriber}->provisioning_voip_subscriber,
            $c->stash->{registered}->contact);
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete registered device'),
        );
    }

    NGCP::Panel::Utils::Message::info(
        c    => $c,
        data => { $c->stash->{registered}->get_inflated_columns },
        desc => $c->loc('Successfully deleted registered device'),
    );
    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
}

sub create_registered :Chained('master') :PathPart('registered/create') :Args(0) {
    my ($self, $c) = @_;

    my $s = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $posted = ($c->request->method eq 'POST');
    my $ret;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::Location", $c);
    $form->process(
        posted => $posted,
        params => $c->request->params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $values = $form->values;
            $values->{flags} = 0;
            $values->{cflags} = 0;
            $values->{cflags} |= 64 if($values->{nat});
            NGCP::Panel::Utils::Kamailio::create_location($c,
                $c->stash->{subscriber}->provisioning_voip_subscriber,
                $values
            );
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully added registered device'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to add registered device'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
    }

    $c->stash(
        reg_create_flag => 1,
        description => $c->loc('Registered Device'),
        form => $form,
    );
}

sub create_trusted :Chained('base') :PathPart('preferences/trusted/create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $trusted_rs = $c->stash->{subscriber}->provisioning_voip_subscriber->voip_trusted_sources;
    my $params = {};

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::TrustedSource", $c);
    $form->process(
        posted => $posted,
        params => $posted ? $c->req->params : {}
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            $trusted_rs->create({
                uuid => $c->stash->{subscriber}->uuid,
                src_ip => $form->field('src_ip')->value,
                protocol => $form->field('protocol')->value,
                from_pattern => $form->field('from_pattern') ? $form->field('from_pattern')->value : undef,
            });
            NGCP::Panel::Utils::Kamailio::trusted_reload($c);
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully created trusted source'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to create trusted source'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => $c->loc('Trusted Source'),
        cf_form => $form,
    );
}

sub trusted_base :Chained('base') :PathPart('preferences/trusted') :CaptureArgs(1) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c, $trusted_id) = @_;

    $c->stash->{trusted} = $c->stash->{subscriber}->provisioning_voip_subscriber
                            ->voip_trusted_sources->find($trusted_id);

    unless($c->stash->{trusted}) {
        NGCP::Panel::Utils::Message::error(
            c    => $c,
            log  => "trusted source id '$trusted_id' not found for subscriber uuid ".$c->stash->{subscriber}->uuid,
            desc => $c->loc('Trusted source entry not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }
}

sub edit_trusted :Chained('trusted_base') :PathPart('edit') {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $posted = ($c->request->method eq 'POST');
    my $trusted = $c->stash->{trusted};
    my $params = {};

    if(!$posted && $trusted) {
        $params = {
            'src_ip' => $trusted->src_ip,
            'protocol' => $trusted->protocol,
            'from_pattern' => $trusted->from_pattern,
        };
    }

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::TrustedSource", $c);
    $form->process(
        params => $posted ? $c->req->params : $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            $trusted->update({
                src_ip => $form->field('src_ip')->value,
                protocol => $form->field('protocol')->value,
                from_pattern => $form->field('from_pattern') ? $form->field('from_pattern')->value : undef,
            });
            NGCP::Panel::Utils::Kamailio::trusted_reload($c);
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated trusted source'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to update trusted source'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => $c->loc('Trusted Source'),
        cf_form => $form,
    );
}

sub delete_trusted :Chained('trusted_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    try {
        $c->stash->{trusted}->delete;
        NGCP::Panel::Utils::Kamailio::trusted_reload($c);
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{trusted}->get_inflated_columns },
            desc => $c->loc('Successfully deleted trusted source'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete trusted source.'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
}

sub create_upn_rewrite :Chained('base') :PathPart('preferences/upnrewrite/create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $upn_rws_rs = $c->stash->{subscriber}->provisioning_voip_subscriber->upn_rewrite_sets_rs;
    my $params = {};

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::UpnRewriteSet", $c);
    $form->process(
        posted => $posted,
        params => $c->req->params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $new_upnr_set = $upn_rws_rs->create({
                new_cli => $form->values->{new_cli},
                upn_rewrite_sources => [
                    map { { pattern => $_->{pattern} }; } @{ $form->values->{upn_rewrite_sources} },
                    ],
            });
            my $upnr_pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => 'upn_rewrite_id',
                prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber);
            $upnr_pref_rs->create({ value => $new_upnr_set->id });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully created UPN rewrite set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to create UPN rewrite set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => $c->loc('UPN rewrite set'),
        cf_form => $form,
    );
}

sub upn_rewrite_base :Chained('base') :PathPart('preferences/upnrewrite') :CaptureArgs(1) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c, $rws_id) = @_;

    $c->stash->{upn_rws} = $c->stash->{subscriber}->provisioning_voip_subscriber
                            ->upn_rewrite_sets_rs->find($rws_id);

    unless($c->stash->{upn_rws}) {
        NGCP::Panel::Utils::Message::error(
            c    => $c,
            log  => "rewrite set id '$rws_id' not found for subscriber uuid ".$c->stash->{subscriber}->uuid,
            desc => $c->loc('Rewrite Set entry not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }
}

sub edit_upn_rewrite :Chained('upn_rewrite_base') :PathPart('edit') {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $posted = ($c->request->method eq 'POST');
    my $upn_rws = $c->stash->{upn_rws};
    my $params = $posted ? {} : {
        $upn_rws->get_inflated_columns,
        upn_rewrite_sources => [ $upn_rws->upn_rewrite_sources->all ],
    };

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::UpnRewriteSet", $c);
    $form->process(
        params => $c->req->params,
        posted => $posted,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            if ($upn_rws->new_cli ne $form->values->{new_cli}) {
                $upn_rws->update({ new_cli => $form->values->{new_cli}});
            }
            $upn_rws->upn_rewrite_sources->delete_all;
            for my $s (@{ $form->values->{upn_rewrite_sources} }) {
                $upn_rws->upn_rewrite_sources->create({
                        pattern => $s->{pattern},
                    });
            }
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated UPN rewrite set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to update UPN rewrite set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => $c->loc('UPN rewrite set'),
        cf_form => $form,
    );
}

sub delete_upn_rewrite :Chained('upn_rewrite_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    try {
        my $upnr_pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => 'upn_rewrite_id',
            prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber);
        my $upnr_pref = $upnr_pref_rs->find({value => $c->stash->{upn_rws}->id});
        if ($upnr_pref) {
            $upnr_pref->delete;
        } else {
            $c->log->warn("UPN rewrite preferences: upn_rewrite_sets and preferences are out of sync!");
        }
        $c->stash->{upn_rws}->delete;

        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{upn_rws} ? $c->stash->{upn_rws}->get_inflated_columns : () },
            desc => $c->loc('Successfully deleted UPN rewrite set'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete UPN rewrite set.'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
}


sub ajax_speeddial :Chained('base') :PathPart('preferences/speeddial/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $sd_rs = $prov_subscriber->voip_speed_dials;
    NGCP::Panel::Utils::Datatables::process($c, $sd_rs, $c->stash->{sd_dt_columns},
        sub {
            my ($result) = @_;
            my %data = ();
            my $sub = $c->stash->{subscriber};
            if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
                my ($user, $domain) = split(/\@/, $result->destination);
                $user =~ s/^sips?://;
                $user = uri_unescape(NGCP::Panel::Utils::Subscriber::apply_rewrite(
                    c => $c, subscriber => $sub, number => $user, direction => 'caller_out'
                ));
                if($domain eq $sub->domain->domain) {
                    $data{destination} = $user;
                } else {
                    $data{destination} = $user . '@' . $domain;
                }
            }
            return %data;
        }
    );

    $c->detach( $c->view("JSON") );
}

sub create_speeddial :Chained('base') :PathPart('preferences/speeddial/create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $slots = $prov_subscriber->voip_speed_dials;
    $c->stash->{used_sd_slots} = $slots;
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::SpeedDial", $c);
    my $params = {};

    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $d = $form->field('destination')->value;
            if($d !~ /\@/) {
                $d .= '@'.$prov_subscriber->domain->domain;
            }
            if($d !~ /^sip:/) {
                $d = 'sip:' . $d;
            }
            $slots->create({
                slot => $form->field('slot')->value,
                destination => $d,
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully created speed dial slot'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to create speed dial slot'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    delete $c->stash->{used_sd_slots};
    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => $c->loc('Speed Dial Slot'),
        cf_form => $form,
    );
}

sub speeddial :Chained('base') :PathPart('preferences/speeddial') :CaptureArgs(1) {
    my ($self, $c, $sd_id) = @_;

    my $sd = $c->stash->{subscriber}->provisioning_voip_subscriber->voip_speed_dials
                ->find($sd_id);
    unless($sd) {
        NGCP::Panel::Utils::Message::error(
            c    => $c,
            log  => "no such speed dial slot with id '$sd_id' for uuid ".$c->stash->{subscriber}->uuid,
            desc => $c->loc('No such speed dial id.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }
    $c->stash->{speeddial} = $sd;
}

sub delete_speeddial :Chained('speeddial') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    try {
        $c->stash->{speeddial}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{speeddial}->get_inflated_columns },
            desc => $c->loc('Successfully deleted speed dial slot'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete speed dial slot'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
}

sub edit_speeddial :Chained('speeddial') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $posted = ($c->request->method eq 'POST');
    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $slots = $prov_subscriber->voip_speed_dials;
    $c->stash->{used_sd_slots} = $slots;
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::SpeedDial", $c);

    my $params;
    $params->{slot} = $c->stash->{speeddial}->slot;
    $params->{destination} = $c->stash->{speeddial}->destination;

    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $d = $form->field('destination')->value;
            if($d !~ /\@/) {
                $d .= '@'.$prov_subscriber->domain->domain;
            }
            if($d !~ /^sip:/) {
                $d = 'sip:' . $d;
            }
            $c->stash->{speeddial}->update({
                slot => $form->field('slot')->value,
                destination => $d,
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated speed dial slot'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to update speed dial slot'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    delete $c->stash->{used_sd_slots};
    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => $c->loc('Speed Dial Slot'),
        cf_form => $form,
    );
}

sub ajax_autoattendant :Chained('base') :PathPart('preferences/autoattendant/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $aa_rs = $prov_subscriber->voip_pbx_autoattendants;
    NGCP::Panel::Utils::Datatables::process($c, $aa_rs, $c->stash->{aa_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub autoattendant :Chained('base') :PathPart('preferences/autoattendant') :CaptureArgs(1) {
    my ($self, $c, $aa_id) = @_;

    my $aa = $c->stash->{subscriber}->provisioning_voip_subscriber->voip_pbx_autoattendants
                ->find($aa_id);
    unless($aa) {
        NGCP::Panel::Utils::Message::error(
            c    => $c,
            log  => "no such auto attendant slot with id '$aa_id' for uuid ".$c->stash->{subscriber}->uuid,
            desc => $c->loc('No such auto attendant id.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }
    $c->stash->{autoattendant} = $aa;
}

sub delete_autoattendant :Chained('autoattendant') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    try {
        $c->stash->{autoattendant}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{autoattendant}->get_inflated_columns },
            desc => $c->loc('Successfully deleted auto attendant slot'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete auto attendant slot'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
}

sub edit_autoattendant :Chained('base') :PathPart('preferences/speeddial/edit') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $posted = ($c->request->method eq 'POST');
    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $slots = $prov_subscriber->voip_pbx_autoattendants;
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::AutoAttendant", $c);

    my $params = {};
    unless($posted) {
        $params->{slot} = [];
        foreach my $slot($slots->all) {
            push @{ $params->{slot} }, { $slot->get_inflated_columns };
        }
    }

    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $slots->delete_all;
                my @fields = $form->field('slot')->fields;
                foreach my $slot(@fields) {
                    my $d = $slot->field('destination')->value;
                    if($d !~ /\@/) {
                        $d .= '@'.$prov_subscriber->domain->domain;
                    }
                    if($d !~ /^sip:/) {
                        $d = 'sip:' . $d;
                    }
                    $slots->create({
                        uuid => $prov_subscriber->uuid,
                        choice => $slot->field('choice')->value,
                        destination => $d,
                    });
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated auto attendant slots'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to update autoattendant slots'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => $c->loc('Auto Attendant Slot'),
        cf_form => $form,
    );
}

sub ajax_ccmappings :Chained('base') :PathPart('preferences/ccmappings/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $aa_rs = $prov_subscriber->voip_cc_mappings;
    NGCP::Panel::Utils::Datatables::process($c, $aa_rs, $c->stash->{ccmap_dt_columns});

    $c->detach( $c->view("JSON") );
    return;
}

sub ccmappings :Chained('base') :PathPart('preferences/ccmappings') :CaptureArgs(1) {
    my ($self, $c, $aa_id) = @_;

    my $ccmapping = $c->stash->{subscriber}->provisioning_voip_subscriber->voip_cc_mappings
                ->find($aa_id);
    unless($ccmapping) {
        NGCP::Panel::Utils::Message::error(
            c    => $c,
            log  => "no such ccmapping with id '$aa_id' for uuid ".$c->stash->{subscriber}->uuid,
            desc => $c->loc('No such auto ccmapping id.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }
    $c->stash->{ccmapping} = $ccmapping;
    return;
}

sub delete_ccmapping :Chained('ccmappings') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    try {
        $c->stash->{ccmapping}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{ccmapping}->get_inflated_columns },
            desc => $c->loc('Successfully deleted ccmapping'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete ccmapping'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c,
        $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    return;
}

sub edit_ccmapping :Chained('base') :PathPart('preferences/ccmappings/edit') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $posted = ($c->request->method eq 'POST');
    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $ccmappings = $prov_subscriber->voip_cc_mappings;
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::CCMapEntries", $c);

    my $params = {};
    unless($posted) {
        $params->{mappings} = [];
        foreach my $mapping ($ccmappings->all) {
            push @{ $params->{mappings} }, { $mapping->get_inflated_columns };
        }
    }

    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $ccmappings->delete_all;
                my @fields = $form->field('mappings')->fields;
                foreach my $map (@fields) {
                    $ccmappings->create({
                        source_uuid => $map->field('source_uuid')->value || $prov_subscriber->uuid,
                        auth_key => $map->field('auth_key')->value,
                    });
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated ccmappings'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to update ccmappings'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_ccmap_flag => 1,
        ccmap_form => $form,
    );
    return;
}

sub callflow_base :Chained('base') :PathPart('callflow') :CaptureArgs(1) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c, $callid) = @_;

    $c->detach('/denied_page')
        unless($c->config->{features}->{callflow});

    $c->stash->{callid} = decode_base64url($callid)
            =~ s/(_b2b-1|_pbx-1)+$//r
            =~ s/[^[:print:]]+//gr;  # remove non-printable chars to be sure for db-operation
}

sub get_pcap :Chained('callflow_base') :PathPart('pcap') :Args(0) {
    my ($self, $c) = @_;
    my $cid = $c->stash->{callid};

    my $packet_rs = $c->model('Storage')->resultset('packets')->search({
        'message.call_id' => { -in => [ $cid, $cid.'_b2b-1', $cid.'_pbx-1' ] },
    }, {
        join => { message_packets => 'message' },
    });

    my $packets = [ $packet_rs->all ];
    my $pcap = NGCP::Panel::Utils::Callflow::generate_pcap($packets);

    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $cid . '.pcap"');
    $c->response->content_type('application/octet-stream');
    $c->response->body($pcap);
}

sub get_uas_json :Chained('callflow_base') :PathPart('uas_json') :Args(0) {
    my ($self, $c) = @_;

    my %int_uas = (
      $c->config->{callflow}->{lb_int}, 'lb',
      $c->config->{callflow}->{lb_ext}, 'lb',
      $c->config->{callflow}->{proxy},  'proxy',
      $c->config->{callflow}->{sbc},    'sbc',
      $c->config->{callflow}->{app},    'app',
      $c->config->{callflow}->{pbx},    'pbx',
    );

    $c->response->content_type('application/json');
    $c->response->body(encode_json(\%int_uas));
}

sub get_json :Chained('callflow_base') :PathPart('json') :Args(0) {
    my ($self, $c) = @_;
    my $cid = $c->stash->{callid};

    my $calls_rs = $c->model('Storage')->resultset('messages')->search({
        'me.call_id' => { -in => [ $cid, $cid.'_b2b-1', $cid.'_pbx-1' ] },
    }, {
        order_by => { -asc => 'timestamp' },
    });

    return unless($calls_rs);
    my @cols = qw(method timestamp src_ip dst_ip call_id payload transport id src_port dst_port request_uri);
    my $ac   = { method => 'column_method' };

    my @msgs;

    foreach my $row ($calls_rs->all ) {
        my $m = { map {
            my $col = $_;
            my $ac  = $ac->{$col} // $col;
            $col => $row->$ac.'';
        } @cols };
        push(@msgs, $m);
    }

    $c->response->content_type('application/json');
    $c->response->body(encode_json(\@msgs));
}

sub get_png :Chained('callflow_base') :PathPart('png') :Args(0) {
    my ($self, $c) = @_;
    my $cid = $c->stash->{callid};

    my $calls_rs = $c->model('Storage')->resultset('messages')->search({
        'me.call_id' => { -in => [ $cid, $cid.'_b2b-1', $cid.'_pbx-1' ] },
    }, {
        order_by => { -asc => 'timestamp' },
    });

    my $calls = [ $calls_rs->all ];
    my $png = NGCP::Panel::Utils::Callflow::generate_callmap_png($c, $calls);

    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $cid . '.png"');
    $c->response->content_type('image/png');
    $c->response->body($png);
}

sub get_callmap :Chained('callflow_base') :PathPart('callmap') :Args(0) {
    my ($self, $c) = @_;
    my $cid = $c->stash->{callid};

    my $calls_rs = $c->model('Storage')->resultset('messages')->search({
        'me.call_id' => { -in => [ $cid, $cid.'_b2b-1', $cid.'_pbx-1' ] },
    }, {
        order_by => { -asc => 'timestamp' },
    });

    my $calls = [ $calls_rs->all ];
    my $map = NGCP::Panel::Utils::Callflow::generate_callmap($c, $calls);

    $c->stash(
        canvas => $map,
        template => 'subscriber/callmap.tt',
    );
}

sub get_packet :Chained('callflow_base') :PathPart('packet') :Args() {
    my ($self, $c, $packet_id) = @_;
    my $cid = $c->stash->{callid};

    my $packet = $c->model('Storage')->resultset('messages')->find({
        'me.call_id' => { -in => [ $cid, $cid.'_b2b-1', $cid.'_pbx-1' ] },
        'me.id' => $packet_id,
    }, {
        order_by => { -asc => 'timestamp' },
    });

    return unless($packet);

    my $pkg = { $packet->get_inflated_columns };

    my $t = $packet->timestamp;
    my $tstamp = $t->ymd('-') . ' ' . $t->hms(':') . '.' . $t->microsecond;

    $pkg->{payload} = encode_entities($pkg->{payload});
    $pkg->{payload} =~ s/\r//g;
    $pkg->{payload} =~ s/([^\n]{120})/$1<br\/>/g;
    $pkg->{payload} =~ s/^([^\n]+)\n/<b>$1<\/b>\n/;
    $pkg->{payload} = $tstamp .' ('.$t->hires_epoch.')<br/>'.
        $pkg->{src_ip}.':'.$pkg->{src_port}.' &rarr; '. $pkg->{dst_ip}.':'.$pkg->{dst_port}.'<br/><br/>'.
        $pkg->{payload};
    $pkg->{payload} =~ s/\n([a-zA-Z0-9\-_]+\:)/\n<b>$1<\/b>/g;
    $pkg->{payload} =~ s/\n/<br\/>/g;

    $c->response->content_type('text/html');
    $c->response->body($pkg->{payload});

}

sub phonebook_ajax :Chained('base') :PathPart('phonebook/ajax') :Args(0) {
    my ($self, $c) = @_;
    NGCP::Panel::Utils::Datatables::process($c,
        @{$c->stash}{qw(phonebook phonebook_dt_columns)});
    $c->detach( $c->view("JSON") );
}

sub phonebook_create :Chained('base') :PathPart('phonebook/create') :Args(0) {
    my ($self, $c) = @_;

    my $subscriber = $c->stash->{subscriber};
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::Subscriber", $c);
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $c->model('DB')->schema->txn_do( sub {
                $c->model('DB')->resultset('subscriber_phonebook')->create({
                    subscriber_id => $subscriber->id,
                    name => $form->values->{name},
                    number => $form->values->{number},
                    shared => $form->values->{shared},
                });
            });

            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $c->loc('Phonebook entry successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create phonebook entry.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action("/subscriber/details", [$subscriber->id]));
    }

    $c->stash(
        close_target => $c->uri_for_action("/subscriber/details", [$subscriber->id]),
        create_flag => 1,
        form => $form
    );
}

sub phonebook_base :Chained('base') :PathPart('phonebook') :CaptureArgs(1) {
    my ($self, $c, $phonebook_id) = @_;

    unless($phonebook_id && is_int($phonebook_id)) {
        $phonebook_id //= '';
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $phonebook_id },
            desc => $c->loc('Invalid phonebook id detected'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->stash->{subscriber}->phonebook->find($phonebook_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc => $c->loc('Phonebook entry does not exist'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    $c->stash(phonebook => {$res->get_inflated_columns},
              phonebook_result => $res);
}

sub phonebook_edit :Chained('phonebook_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $subscriber = $c->stash->{subscriber};
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::Subscriber", $c);
    my $params = $c->stash->{phonebook};
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    if($posted && $form->validated) {
        try {
            $c->model('DB')->schema->txn_do( sub {
                $c->stash->{'phonebook_result'}->update({
                    name => $form->values->{name},
                    number => $form->values->{number},
                    shared => $form->values->{shared},
                });
            });
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Phonebook entry successfully updated'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update phonebook entry'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action("/subscriber/details", [$subscriber->id]));

    }

    $c->stash(
        close_target => $c->uri_for_action("/subscriber/details", [$subscriber->id]),
        edit_flag => 1,
        form => $form
    );
}

sub phonebook_delete :Chained('phonebook_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    my $subscriber = $c->stash->{subscriber};
    my $phonebook = $c->stash->{phonebook_result};

    try {
        $phonebook->delete;
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $c->stash->{phonebook},
            desc => $c->loc('Phonebook entry successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $c->stash->{phonebook},
            desc  => $c->loc('Failed to delete phonebook entry'),
        );
    };

    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action("/subscriber/details", [$subscriber->id]));
}

sub phonebook_upload_csv :Chained('base') :PathPart('phonebook_upload_csv') :Args(0) {
    my ($self, $c) = @_;

    my $subscriber = $c->stash->{subscriber};
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::Upload", $c);
    NGCP::Panel::Utils::Phonebook::ui_upload_csv(
        $c, $c->stash->{phonebook}, $form, 'subscriber', $subscriber->id,
        $c->uri_for_action('/subscriber/phonebook_upload_csv',[$subscriber->id]),
        $c->uri_for_action('/subscriber/details',[$subscriber->id])
    );

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
    return;
}

sub phonebook_download_csv :Chained('base') :PathPart('phonebook_download_csv') :Args(0) {
    my ($self, $c) = @_;

    my $subscriber = $c->stash->{subscriber};
    $c->response->header ('Content-Disposition' => 'attachment; filename="subscriber_phonebook_entries.csv"');
    $c->response->content_type('text/csv');
    $c->response->status(200);
    NGCP::Panel::Utils::Phonebook::download_csv(
        $c, $c->stash->{phonebook}, 'subscriber', $subscriber->id
    );
    return;
}

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


1;

# vim: set tabstop=4 expandtab:
