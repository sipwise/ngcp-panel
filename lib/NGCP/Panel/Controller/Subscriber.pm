package NGCP::Panel::Controller::Subscriber;
use Sipwise::Base;
BEGIN { extends 'Catalyst::Controller'; }
use HTML::Entities;
use JSON qw(decode_json encode_json);
use URI::Escape qw(uri_unescape);
use IPC::System::Simple qw/capturex/;
use Test::More;
use Data::Dumper;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Datatables;
use NGCP::Panel::Utils::Callflow;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Sems;
use NGCP::Panel::Utils::Hylafax;
use NGCP::Panel::Utils::Kamailio;
use NGCP::Panel::Utils::Events;
use NGCP::Panel::Form::Subscriber;
use NGCP::Panel::Form::SubscriberEdit;
use NGCP::Panel::Form::CCMapEntries;
use NGCP::Panel::Form::Customer::PbxSubscriberEdit;
use NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadmin;
use NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadminNoGroup;
use NGCP::Panel::Form::SubscriberCFSimple;
use NGCP::Panel::Form::SubscriberCFTSimple;
use NGCP::Panel::Form::SubscriberCFAdvanced;
use NGCP::Panel::Form::SubscriberCFTAdvanced;
use NGCP::Panel::Form::DestinationSet;
use NGCP::Panel::Form::TimeSet;
use NGCP::Panel::Form::Voicemail::Pin;
use NGCP::Panel::Form::Voicemail::Email;
use NGCP::Panel::Form::Voicemail::Attach;
use NGCP::Panel::Form::Voicemail::Delete;
use NGCP::Panel::Form::Reminder;
use NGCP::Panel::Form::Subscriber::EditWebpass;
use NGCP::Panel::Form::Subscriber::TrustedSource;
use NGCP::Panel::Form::Subscriber::Location;
use NGCP::Panel::Form::Subscriber::SpeedDial;
use NGCP::Panel::Form::Subscriber::AutoAttendant;
use NGCP::Panel::Form::Faxserver::Name;
use NGCP::Panel::Form::Faxserver::Password;
use NGCP::Panel::Form::Faxserver::Active;
use NGCP::Panel::Form::Faxserver::SendStatus;
use NGCP::Panel::Form::Faxserver::SendCopy;
use NGCP::Panel::Form::Faxserver::Destination;
use NGCP::Panel::Form::Subscriber::Webfax;
use NGCP::Panel::Form::Subscriber::ResetPassword;
use NGCP::Panel::Form::Subscriber::RecoverPassword;

use NGCP::Panel::Utils::XMLDispatcher;
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
        { name => "number", search => 1, title => $c->loc('Number'), literal_sql => "concat(primary_number.cc, primary_number.ac, primary_number.sn)"},
        { name => "primary_number.cc", search => 1, title => "" }, #need this to get the relationship
        { name => "provisioning_voip_subscriber.voip_subscriber_profile.name", search => 1, title => $c->loc('Profile') },
    ]);
}

sub root :Chained('sub_list') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
}


sub create_list :Chained('sub_list') :PathPart('create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    my $form = NGCP::Panel::Form::Subscriber->new(ctx => $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'domain.create' => $c->uri_for('/domain/create'),
            'reseller.create' => $c->uri_for('/reseller/create'),
            'contract.create' => $c->uri_for('/customer/create'),
        },
        back_uri => $c->req->uri,
    );
    if($form->validated) {
        my $schema = $c->model('DB');
        try {
            $schema->txn_do(sub {
                my $preferences = {};
                my $contract_rs = NGCP::Panel::Utils::Contract::get_customer_rs(c => $c);
                my $contract = $contract_rs->find({
                    'me.id' => $form->params->{contract}{id},
                });


                my $billing_mapping = $contract->billing_mappings->find($contract->get_column('bmid'));

                if($contract->external_id) {
                    $preferences->{ext_contract_id} = $contract->external_id;
                }
                if(defined $form->params->{external_id}) {
                    $preferences->{ext_subscriber_id} = $form->params->{external_id};
                }
                if($billing_mapping->billing_profile->prepaid) {
                    $preferences->{prepaid} = 1;
                }
                my $billing_subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                    c => $c,
                    schema => $schema,
                    contract => $contract,
                    params => $form->params,
                    admin_default => 0,
                    preferences => $preferences,
                );

                delete $c->session->{created_objects}->{reseller};
                delete $c->session->{created_objects}->{contract};
                delete $c->session->{created_objects}->{domain};
            });
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Subscriber successfully created!'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create subscriber'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriber'));
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form)
}

sub base :Chained('sub_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $subscriber_id) = @_;

    unless($subscriber_id && $subscriber_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            error => "subscriber id '$subscriber_id' is not an integer",
            desc  => $c->loc('Invalid subscriber id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriber'));
    }

    my $res = $c->stash->{subscribers_rs}->find({ id => $subscriber_id });
    unless(defined $res) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            error => "subscriber id '$subscriber_id' does not exist",
            desc  => $c->loc('Subscriber does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriber'));
    }

    $c->stash(subscriber => $res);

    $c->stash->{contract} = $c->stash->{subscriber}->contract;
    my $contract_rs = NGCP::Panel::Utils::Contract::get_customer_rs(c => $c);
    my $contract = $contract_rs->find({
        'me.id' => $c->stash->{contract}->id,
    });
    unless(defined $contract) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            error => "subscriber id '$subscriber_id' points to non-existing contract id",
            desc  => $c->loc('Contract does not exist for subscriber'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriber'));
    }
    my $billing_mapping = $contract->billing_mappings->find($contract->get_column('bmid'));
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
        { name => "the_timestamp", search_from_epoch => 1, search_to_epoch => 1, title => $c->loc('Timestamp') },
        { name => "status", search => 1, title => $c->loc('Status') },
        { name => "duration", search => 1, title => $c->loc('Duration') },
        { name => "direction", search => 1, title => $c->loc('Direction') },
        { name => "peer_number", search => 1, title => $c->loc('Peer Number') },
        { name => "pages", search => 1, title => $c->loc('Pages') },
    ]);

    $c->stash->{ccmap_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "auth_key", search => 1, title => $c->loc('CLI') },
        { name => "source_uuid", search => 1, title => $c->loc('Source UUID') },
    ]);

    if($c->stash->{billing_mapping}->product->class eq "pbxaccount") {
        $c->stash->{pbx_groups} = $c->model('DB')->resultset('voip_subscribers')->search({
            contract_id => $c->stash->{subscriber}->contract->id,
            status => { '!=' => 'terminated' },
            'provisioning_voip_subscriber.is_pbx_group' => 1,
        }, {
            join => 'provisioning_voip_subscriber',
        });
    }
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
    my $form = NGCP::Panel::Form::Subscriber::Webfax->new;
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
            if(defined $form->params->{faxfile}) {
                NGCP::Panel::Utils::Hylafax::send_fax(
                    c => $c,
                    subscriber => $subscriber,
                    destination => $form->params->{destination},
                    #resolution => 'low', # opt (low, medium, extended)
                    #notify => 'someone@example.org', # TODO: handle in send_fax, read from prefs!
                    #coverpage => 1,
                    upload => $form->params->{faxfile},
                );
            } else {
                NGCP::Panel::Utils::Hylafax::send_fax(
                    c => $c,
                    subscriber => $subscriber,
                    destination => $form->params->{destination},
                    #resolution => 'low', # opt (low, medium, extended)
                    #notify => 'someone@example.org', # TODO: handle in send_fax, read from prefs!
                    #coverpage => 1,
                    data => $form->params->{data},
                );
            }
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c     => $c,
                error => "failed to send fax: $e",
                desc  => $c->loc('Internal error while sending fax'),
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

    my $s = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $kam_subscriber = $c->model('DB')->resultset('subscriber')->find({
        uuid => $s->uuid
    });
    my $fax_rs = $c->model('DB')->resultset('fax_journal')->search({
        subscriber_id => $kam_subscriber->id,
    });

    NGCP::Panel::Utils::Datatables::process($c, $fax_rs, $c->stash->{fax_dt_columns});

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
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            error => 'unauthorized termination of own subscriber for uuid '.$c->user->uuid,
            desc  => $c->loc('Terminating own subscriber is prohibited.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriber'));
    }

    try {
        NGCP::Panel::Utils::Subscriber::terminate(c => $c, subscriber => $subscriber);
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $subscriber->get_inflated_columns },
            desc => $c->loc('Successfully terminated subscriber'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            desc => $c->loc('Successfully reset web password, please check your email at [_1]', $subscriber->contact ? $subscriber->contact->email : $subscriber->contract->contact->email),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
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
    my $form = NGCP::Panel::Form::Subscriber::RecoverPassword->new;
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
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully reset web password, please check your email'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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

    my $form = NGCP::Panel::Form::Subscriber::ResetPassword->new(ctx => $c);
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
            NGCP::Panel::Utils::Message->error(
                c     => $c,
                error => $e,
                type  => 'internal',
                desc  => $c->loc('Failed to recover web password'),
            );
            $c->detach('/denied_page');
        }

        $c->log->debug("+++++++++++++++++++++++ successfully recovered subscriber " . $subscriber->username . '@' . $subscriber->domain->domain);
        NGCP::Panel::Utils::Message->info(
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

    foreach my $type(qw/cfu cfna cft cfb/) {
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
                    $d->{as_string} = NGCP::Panel::Utils::Subscriber::destination_as_string($c, $d);
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
            push @{ $cfs->{$type} }, { destinations => \@dset, periods => \@tset, tset_name => $tset_name , dset_name => $dset_name };
        }
    }
    $c->stash(cf_destinations => $cfs);

    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => 'ringtimeout', prov_subscriber => $prov_subscriber)
        ->first;
    $c->stash(cf_ringtimeout => $ringtimeout_preference ? $ringtimeout_preference->value : undef);

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
        foreach my $pref(qw/cfu cft cfna cfb 
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
        NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->error(
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
        unless(is_deeply($old_auth_prefs, $new_auth_prefs)) {
            try {

                if(!NGCP::Panel::Utils::Preferences::is_peer_auth_active($c, $old_auth_prefs) && 
                    NGCP::Panel::Utils::Preferences::is_peer_auth_active($c, $new_auth_prefs)) {

                    NGCP::Panel::Utils::Sems::create_peer_registration(
                        $c, $prov_subscriber, $new_auth_prefs);
                } elsif(NGCP::Panel::Utils::Preferences::is_peer_auth_active($c, $old_auth_prefs) && 
                        !NGCP::Panel::Utils::Preferences::is_peer_auth_active($c, $new_auth_prefs)) {

                    NGCP::Panel::Utils::Sems::delete_peer_registration(
                        $c, $prov_subscriber, $old_auth_prefs);
                } elsif(NGCP::Panel::Utils::Preferences::is_peer_auth_active($c, $old_auth_prefs) &&
                        NGCP::Panel::Utils::Preferences::is_peer_auth_active($c, $new_auth_prefs)){

                    NGCP::Panel::Utils::Sems::update_peer_registration(
                        $c, $prov_subscriber, $new_auth_prefs, $old_auth_prefs);
                }

            } catch($e) {
                NGCP::Panel::Utils::Message->error(
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
        # default
        NGCP::Panel::Utils::Message->error(
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

        # there are more than one destinations or a time set, so
        # which can only be handled in advanced mode
        if($cf_mapping->first->destination_set->voip_cf_destinations->count > 1 ||
           $cf_mapping->first->time_set) {

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
    }

    if($c->config->{features}->{cloudpbx}) {
        my $pbx_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c,
            attribute => 'cloud_pbx',
            prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber
        );
        if($pbx_pref->first) {
            $c->stash->{pbx} = 1;
        }
    }

    my $cf_form;
    if($cf_type eq "cft") {
        $cf_form = NGCP::Panel::Form::SubscriberCFTSimple->new(ctx => $c);
    } else {
        $cf_form = NGCP::Panel::Form::SubscriberCFSimple->new(ctx => $c);
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

                my $numberstr = "";
                my $number = $c->stash->{subscriber}->primary_number;
                if(defined $number) {
                    $numberstr .= $number->cc;
                    $numberstr .= $number->ac if defined($number->ac);
                    $numberstr .= $number->sn;
                } else {
                    $numberstr = $c->stash->{subscriber}->uuid;
                }
                my $dest = $cf_form->field('destination');
                my $d = $dest->field('destination')->value;
                my $t = 300;
                NGCP::Panel::Utils::Subscriber::check_cf_ivr(
                    subscriber => $c->stash->{subscriber},
                    schema => $c->model('DB'),
                    old_aa => $old_autoattendant,
                    new_aa => ($d eq 'autoattendant'),
                );
                if ($d eq "uri") {
                    $t = $dest->field('uri')->field('timeout')->value;
                    # TODO: check for valid timeout here
                }
                $d = NGCP::Panel::Utils::Subscriber::field_to_destination(
                        number => $numberstr,
                        domain => $c->stash->{subscriber}->domain->domain,
                        destination => $d,
                        uri => $dest->field('uri')->field('destination')->value,
                    );

                $dest_set->voip_cf_destinations->create({
                    destination => $d,
                    timeout => $t,
                    priority => 1,
                });

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
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully saved Call Forward'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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
        # default
        NGCP::Panel::Utils::Message->error(
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

    $c->stash->{cf_destination_sets} = $prov_subscriber->voip_cf_destination_sets;
    $c->stash->{cf_time_sets} = $prov_subscriber->voip_cf_time_sets;

    my $posted = ($c->request->method eq 'POST');

    my $cf_form;
    if($cf_type eq "cft") {
        $cf_form = NGCP::Panel::Form::SubscriberCFTAdvanced->new(ctx => $c);
    } else {
        $cf_form = NGCP::Panel::Form::SubscriberCFAdvanced->new(ctx => $c);
    }

    my @maps = ();
    foreach my $map($cf_mapping->all) {
        push @maps, {
            destination_set => $map->destination_set ? $map->destination_set->id : undef,
            time_set => $map->time_set ? $map->time_set->id : undef,
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
                        NGCP::Panel::Utils::Message->info(
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
                    });
                    $cf_preference->create({ value => $m->id });
                    $autoattendant_count -= NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($m->destination_set);
                }
                if ($autoattendant_count > 0) {
                    while ($autoattendant_count != 0) {
                        $autoattendant_count--;
                        NGCP::Panel::Utils::Events::insert(
                            schema => $c->model('DB'),
                            subscriber => $c->stash->{subscriber},
                            type => 'end_ivr',
                        );
                    }
                } elsif ($autoattendant_count < 0) {
                    while ($autoattendant_count != 0) {
                        $autoattendant_count++;
                        NGCP::Panel::Utils::Events::insert(
                            schema => $c->model('DB'),
                            subscriber => $c->stash->{subscriber},
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
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully saved Call Forward'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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
                    $d->{as_string} = NGCP::Panel::Utils::Subscriber::destination_as_string($c, $d);
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

    if($c->config->{features}->{cloudpbx}) {
        my $pbx_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c,
            attribute => 'cloud_pbx',
            prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber
        );
        if($pbx_pref->first) {
            $c->stash->{pbx} = 1;
        }
    }

    my $form = NGCP::Panel::Form::DestinationSet->new(ctx => $c);

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
                    my $number = $c->stash->{subscriber}->primary_number;
                    my $numberstr = "";
                    if(defined $number) {
                        $numberstr .= $number->cc;
                        $numberstr .= $number->ac if defined($number->ac);
                        $numberstr .= $number->sn;
                    } else {
                        $numberstr = $c->stash->{subscriber}->uuid;
                    }
                    foreach my $dest(@fields) {
                        my $d = $dest->field('destination')->value;
                        my $t = 300;
                        if ($d eq "uri") {
                            $t = $dest->field('uri')->field('timeout')->value;
                            # TODO: check for valid timeout here
                        }
                        $d = NGCP::Panel::Utils::Subscriber::field_to_destination(
                                number => $numberstr,
                                domain => $c->stash->{subscriber}->domain->domain,
                                destination => $d,
                                uri => $dest->field('uri')->field('destination')->value,
                            );

                        $set->voip_cf_destinations->create({
                            destination => $d,
                            timeout => $t,
                            priority => $dest->field('priority')->value,
                        });
                    }
                }
            });
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                type => 'internal',
                desc => $c->loc('Successfully created new destination set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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

    if($c->config->{features}->{cloudpbx}) {
        my $pbx_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c,
            attribute => 'cloud_pbx',
            prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber
        );
        if($pbx_pref->first) {
            $c->stash->{pbx} = 1;
        }
    }

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
                destination => $d,
                uri => {timeout => $t, destination => $duri},
                priority => $dest->priority,
                id => $dest->id,
            };
        }
        $params->{destination} = \@destinations;
    }

    $c->stash->{cf_tmp_params} = $params;
    my $form = NGCP::Panel::Form::DestinationSet->new(ctx => $c);
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
                            subscriber => $c->stash->{subscriber},
                            schema => $schema,
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

                my $number = $c->stash->{subscriber}->primary_number;
                my $numberstr = "";
                if(defined $number) {
                    $numberstr .= $number->cc;
                    $numberstr .= $number->ac if defined($number->ac);
                    $numberstr .= $number->sn;
                } else {
                    $numberstr = $c->stash->{subscriber}->uuid;
                }
                foreach my $dest($form->field('destination')->fields) {
                    my $d = $dest->field('destination')->value;
                    my $t = 300;
                    if ($d eq "uri") {
                        $t = $dest->field('uri')->field('timeout')->value;
                        # TODO: check for valid timeout here
                    }
                    $d = NGCP::Panel::Utils::Subscriber::field_to_destination(
                            number => $numberstr,
                            domain => $c->stash->{subscriber}->domain->domain,
                            destination => $d,
                            uri => $dest->field('uri')->field('destination')->value,
                        );

                    $set->voip_cf_destinations->create({
                        destination => $d,
                        timeout => $t,
                        priority => $dest->field('priority')->value,
                    });
                }
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
                            schema => $schema,
                            subscriber => $c->stash->{subscriber},
                            type => $event_type,
                        );
                    }
                }
            });
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                type => 'internal',
                desc => $c->loc('Successfully updated destination set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $set->get_inflated_columns },
            type => 'internal',
            desc => $c->loc('Successfully deleted destination set'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
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

    my $form = NGCP::Panel::Form::TimeSet->new;

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
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                type => 'internal',
                desc => $c->loc('Successfully created new time set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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

    my $form = NGCP::Panel::Form::TimeSet->new;

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
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                type => 'internal',
                desc => $c->loc('Successfully updated time set'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $set->get_inflated_columns },
            type => 'internal',
            desc => $c->loc('Successfully deleted time set'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
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
        my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
        $prov_subscriber->voip_cf_mappings->search({ type => $cf_type })
            ->delete_all;
        my $cf_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c,
            attribute => $cf_type,
            prov_subscriber => $prov_subscriber,
        );
        $cf_pref->delete_all;
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            desc => $c->loc('Successfully deleted Call Forward'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete Call Forward.'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c, 
        $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
}

sub load_preference_list :Private {
    my ($self, $c) = @_;

    my $reseller_id = $c->stash->{subscriber}->contract->contact->reseller_id;

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

    my $call_cols = [
        { name => "id", title => $c->loc('#')  },
        { name => "source_user", search => 1, title => $c->loc('Caller') },
        { name => "destination_user", search => 1, title => $c->loc('Callee') },
        { name => "call_status", search => 1, title => $c->loc('Status') },
        { name => "start_time", search_from_epoch => 1, search_to_epoch => 1, title => $c->loc('Start Time') },
        { name => "duration", search => 1, title => $c->loc('Duration'), show_total => 'sum' },
    ];
    push @{ $call_cols }, (
        { name => "call_id", search => 1, title => $c->loc('Call-ID') },
    ) if($c->user->roles eq "admin" || $c->user->roles eq "reseller");

    push @{ $call_cols }, (
        { name => "source_customer_cost", search => 1, title => $c->loc('Source Cust Cost (cents)'), show_total => 'sum' },
    ) ;
    $c->stash->{calls_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, $call_cols);

    $c->stash->{vm_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "read", search => 1, title => $c->loc('Read'), literal_sql => 'if(dir like "%/INBOX", "new", "read")' },
        { name => "callerid", search => 1, title => $c->loc('Caller') },
        { name => "origtime", search_from_epoch => 1, search_to_epoch => 1, title => $c->loc('Time') },
        { name => "duration", search => 1, title => $c->loc('Duration') },
    ]);
    $c->stash->{reg_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "user_agent", search => 1, title => $c->loc('User Agent') },
        { name => "contact", search => 1, title => $c->loc('Contact') },
        { name => "expires", search => 1, title => $c->loc('Expires') },
    ]);
    $c->stash->{capture_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "timestamp", search => 1, title => $c->loc('Timestamp') },
        { name => "call_id", search => 1, title => $c->loc('Call-ID') },
        { name => "cseq_method", search => 1, title => $c->loc('Method') },
    ]);

    $c->stash(
        template => 'subscriber/master.tt',
    );

    $c->stash->{prov_lock} = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c,
        attribute => 'lock',
        prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
    );
}

sub details :Chained('master') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole('subscriberadmin') {
    my ($self, $c) = @_;

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

sub calllist :Chained('master') :PathPart('calls') :Args(0) {
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
    
    if($c->stash->{billing_mapping}->product->class eq "pbxaccount") {
        $c->stash(customer_id => $subscriber->contract->id);
        if($subscriber->provisioning_voip_subscriber->is_pbx_pilot) {
            if($c->user->roles eq 'subscriberadmin') {
                $subadmin_pbx = 1;
                $form = NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadminNoGroup->new(ctx => $c);
            } else {
                $is_admin = 1;
                $form = NGCP::Panel::Form::Customer::PbxSubscriberEdit->new(ctx => $c);
            }
        } else {
            $base_number = $c->stash->{pilot}->primary_number;

            if($c->user->roles eq 'subscriberadmin') {
                $subadmin_pbx = 1;
                $form = NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadmin->new(ctx => $c);
            } else {
                $is_admin = 1;
                $form = NGCP::Panel::Form::Customer::PbxExtensionSubscriber->new(ctx => $c);
            }
            $pbx_ext = 1;
        }

    } else {
        if($c->user->roles eq 'subscriberadmin') {
            $subadmin_pbx = 1;
            $c->stash(customer_id => $subscriber->contract->id);
            $form = NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadminNoGroup->new(ctx => $c);
        } else {
            $form = NGCP::Panel::Form::SubscriberEdit->new(ctx => $c);
            $is_admin = 1;
        }
    }

    my $posted = ($c->request->method eq 'POST');

    my $params = {};
    my $lock = $c->stash->{prov_lock};
    # we don't change this on edit
    $c->request->params->{username} = $prov_subscriber->username;
    if ($subadmin_pbx) {
        #dont change the status
        $c->request->params->{status} = $subscriber->status;
    }
    unless($posted) {
        $params->{profile_set}{id} = $prov_subscriber->voip_subscriber_profile_set ?
            $prov_subscriber->voip_subscriber_profile_set->id : undef;
        $params->{profile}{id} = $prov_subscriber->voip_subscriber_profile ?
            $prov_subscriber->voip_subscriber_profile->id : undef;
        $params->{webusername} = $prov_subscriber->webusername;
        $params->{webpassword} = $prov_subscriber->webpassword;
        $params->{password} = $prov_subscriber->password;
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
            $schema->txn_do(sub {

                my $email = delete $form->params->{email};
                if($email) {
                    if($subscriber->contact) {
                        $subscriber->contact->update({
                            email => $email,
                        });
                    } else {
                        my $contact = $c->model('DB')->resultset('contacts')->create({
                            reseller_id => $subscriber->contract->contact->reseller_id,
                            email => $email,
                        });
                        $subscriber->update({ contact_id => $contact->id });
                    }
                }
                my $prov_params = {};
                $prov_params->{pbx_extension} = $form->params->{pbx_extension};
                $prov_params->{webusername} = $form->params->{webusername} || undef;
                $prov_params->{webpassword} = $form->params->{webpassword}
                    if($form->params->{webpassword});
                $prov_params->{password} = $form->params->{password}
                    if($form->params->{password});
                if($is_admin) {
                    $prov_params->{admin} = $form->params->{administrative} // $prov_subscriber->admin;
                }


                if($form->params->{display_name}) {
                    my $display_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                            c => $c, attribute => 'display_name', 
                            prov_subscriber => $prov_subscriber);
                    if($display_pref->first) {
                        $display_pref->first->update({ value => $form->params->{display_name} });
                    } else {
                        $display_pref->create({ value => $form->params->{display_name} });
                    }
                }
                if(defined $form->params->{pbx_extension}) {
                    my $pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                            c => $c, attribute => 'cloud_pbx_ext', 
                            prov_subscriber => $prov_subscriber);
                    if($pref->first) {
                        $pref->first->update({ value => $form->params->{pbx_extension} });
                    } else {
                        $pref->create({ value => $form->params->{pbx_extension} });
                    }
                }

                my $old_profile = $prov_subscriber->profile_id;
                my ($profile_set, $profile);
                if($form->values->{profile_set}{id}) {
                    my $profile_set_rs = $c->model('DB')->resultset('voip_subscriber_profile_sets');
                    if($c->user->roles eq "admin") {
                    } elsif($c->user->roles eq "reseller") {
                        $profile_set_rs = $profile_set_rs->search({
                            reseller_id => $c->user->reseller_id,
                        });
                    }
                         
                    $profile_set = $profile_set_rs->find($form->values->{profile_set}{id});
                    unless($profile_set) {
                        NGCP::Panel::Utils::Message->error(
                            c => $c,
                            error => 'invalid subscriber profile set id ' . $form->values->{profile_set}{id},
                            desc  => $c->loc('Invalid subscriber profile set id'),
                        );
                        return;
                    }
                    delete $form->values->{profile_set};
                } elsif(exists $form->params->{profile_set}{id}) {
                    # if the param has been passed and is empty, clear it (by doing nothing)
                } else {
                    $profile_set = $prov_subscriber->voip_subscriber_profile_set;
                }

                if($profile_set && $form->values->{profile}{id}) {
                    $profile = $profile_set->voip_subscriber_profiles->find({
                        id => $form->values->{profile}{id},
                    });
                }
                if($profile_set && !$profile) {
                    $profile = $profile_set->voip_subscriber_profiles->find({
                        set_default => 1,
                    });
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

                # if the profile changed, clear any preferences which are not in the new profile
                if($prov_subscriber->voip_subscriber_profile) {
                    my %old_profile_attributes = map { $_ => 1 }
                        $prov_subscriber->voip_subscriber_profile
                        ->profile_attributes->get_column('attribute_id')->all;
                    if($profile) {
                        foreach my $attr_id($profile->profile_attributes->get_column('attribute_id')->all) {
                            delete $old_profile_attributes{$attr_id};
                        }
                    }
                    if(keys %old_profile_attributes) {
                        my $cfs = $c->model('DB')->resultset('voip_preferences')->search({
                            id => { -in => [ keys %old_profile_attributes ] },
                            attribute => { -in => [qw/cfu cfb cft cfna/] },
                        });
                        $prov_subscriber->voip_usr_preferences->search({
                            attribute_id => { -in => [ keys %old_profile_attributes ] },
                        })->delete;
                        $prov_subscriber->voip_cf_mappings->search({
                            type => { -in => [ map { $_->attribute } $cfs->all ] },
                        })->delete;
                    }
                }

                $prov_subscriber->update($prov_params);

                if(($prov_subscriber->profile_id // 0) != ($old_profile // 0)) {
                    my $type;
                    if(defined $prov_subscriber->profile_id && defined $old_profile) {
                        $type = "update_profile";
                    } elsif(defined $prov_subscriber->profile_id) {
                        $type = "start_profile";
                    } else {
                        $type = "end_profile";
                    }
                    NGCP::Panel::Utils::Events::insert(
                        c => $c, schema => $schema, subscriber => $subscriber,
                        type => $type, old => $old_profile, new => $prov_subscriber->profile_id
                    );
                }

                my @old_groups = $prov_subscriber->voip_pbx_groups->get_column('group_id')->all;
                my $new_group_ids = defined $form->value->{group_select} ? 
                    decode_json($form->value->{group_select}) : [];
                my @new_groups = ();
                foreach my $group_id(@{ $new_group_ids }) {
                    # add subscriber to group if not there yet
                    my $group = $schema->resultset('voip_subscribers')->find($group_id);
                    next unless($group && $group->provisioning_voip_subscriber && $group->provisioning_voip_subscriber->is_pbx_group);
                    push @new_groups, $group->provisioning_voip_subscriber->id;
                    unless(grep { $group->provisioning_voip_subscriber->id eq $_ } @old_groups) {
                        $prov_subscriber->voip_pbx_groups->create({
                            group_id => $group->provisioning_voip_subscriber->id,
                        });
                        NGCP::Panel::Utils::Subscriber::update_pbx_group_prefs(
                            c => $c,
                            schema => $schema,
                            old_group_id => undef,
                            new_group_id => $group_id,
                            username => $subscriber->username,
                            domain => $subscriber->domain->domain,
                        );
                    }
                }
                foreach my $group_id(@old_groups) {
                    # remove subscriber from group if not there anymore
                    unless(grep { $group_id eq $_ } @new_groups) {
                        my $group = $schema->resultset('provisioning_voip_subscribers')->find($group_id);
                        NGCP::Panel::Utils::Subscriber::update_pbx_group_prefs(
                            c => $c,
                            schema => $schema,
                            old_group_id => $group->voip_subscriber->id,
                            new_group_id => undef,
                            username => $subscriber->username,
                            domain => $subscriber->domain->domain,
                        );
                        $prov_subscriber->voip_pbx_groups->search({
                            group_id => $group_id,
                            subscriber_id => $prov_subscriber->id,
                        })->delete;
                    }
                }

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
                    $form->values->{lock} = 4; # update lock below
                } elsif($old_status eq 'locked' && $subscriber->status eq 'active') {
                    $form->values->{lock} ||= 0; # update lock below
                }

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
                           !is_deeply($old_number, $new_number)) {
                            foreach my $sub($c->stash->{subscribers}->all, $c->stash->{pbx_groups}->all) {
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
                        NGCP::Panel::Utils::Message->error(
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

                $form->values->{lock} ||= 0;
                if($lock->first) {
                    if ($form->values->{lock} == 0) {
                        $lock->delete;
                    } else {
                        $lock->first->update({ value => $form->values->{lock} });
                    }
                } elsif($form->values->{lock} > 0) {
                    $lock->create({ value => $form->values->{lock} });
                }
            });
            delete $c->session->{created_objects}->{group};
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully updated subscriber'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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

sub aliases_ajax :Chained('master') :PathPart('aliases/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
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


    my $form = NGCP::Panel::Form::Subscriber::EditWebpass->new(ctx => $c);
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
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully updated password'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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

sub edit_voicebox :Chained('base') :PathPart('preferences/voicebox/edit') :Args(1) {
    my ($self, $c, $attribute) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $form;
    my $posted = ($c->request->method eq 'POST');
    my $vm_user = $c->stash->{subscriber}->provisioning_voip_subscriber->voicemail_user;
    unless($vm_user) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => "no voicemail user found for subscriber uuid ".$c->stash->{subscriber}->uuid,
            desc  => $c->loc('Failed to find voicemail user.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
    }
    my $params;

    try {
        SWITCH: for ($attribute) {
            /^pin$/ && do {
                $form = NGCP::Panel::Form::Voicemail::Pin->new;
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
                $form = NGCP::Panel::Form::Voicemail::Email->new; 
                $params = { 'email' => $vm_user->email };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $vm_user->update({ email => $form->field('email')->value });
                }
                last SWITCH;
            };
            /^attach$/ && do {
                $form = NGCP::Panel::Form::Voicemail::Attach->new; 
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
                $form = NGCP::Panel::Form::Voicemail::Delete->new; 
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
            # default
            NGCP::Panel::Utils::Message->error(
                c     => $c,
                log   => "trying to set invalid voicemail param '$attribute' for subscriber uuid ".$c->stash->{subscriber}->uuid,
                desc  => $c->loc('Invalid voicemail setting'),
            );
            NGCP::Panel::Utils::Navigation::back_or($c, 
                $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
            return;
        } # SWITCH
        if($posted && $form->validated) {
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully updated voicemail setting'),
            );
            NGCP::Panel::Utils::Navigation::back_or($c, 
                $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
            return;
        }
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to update voicemail setting'),
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
                $form = NGCP::Panel::Form::Faxserver::Name->new;
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
            /^password$/ && do {
                $form = NGCP::Panel::Form::Faxserver::Password->new(ctx => $c);
                $params = { 'password' => $faxpref->password };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $faxpref->update({ password => $form->field('password')->value });
                }
                last SWITCH;
            };
            /^active$/ && do {
                $form = NGCP::Panel::Form::Faxserver::Active->new;
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
            /^send_status$/ && do {
                $form = NGCP::Panel::Form::Faxserver::SendStatus->new;
                $params = { 'send_status' => $faxpref->send_status };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $faxpref->update({ send_status => $form->field('send_status')->value });
                }
                last SWITCH;
            };
            /^send_copy$/ && do {
                $form = NGCP::Panel::Form::Faxserver::SendCopy->new;
                $params = { 'send_copy' => $faxpref->send_copy };
                $form->process(params => $posted ? $c->req->params : $params);
                NGCP::Panel::Utils::Navigation::check_form_buttons(
                    c => $c, form => $form, fields => {}, back_uri => $c->req->uri,
                );
                if($posted && $form->validated) {
                    $faxpref->update({ send_copy => $form->field('send_copy')->value });
                }
                last SWITCH;
            };
            /^destinations$/ && do {
                $form = NGCP::Panel::Form::Faxserver::Destination->new;
                unless($posted) {
                    my @dests = ();
                    for my $dest($prov_subscriber->voip_fax_destinations->all) {
                        push @dests, {
                            destination => $dest->destination,
                            filetype => $dest->filetype,
                            cc => $dest->cc,
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
                            cc => $dest->field('cc')->value,
                            incoming => $dest->field('incoming')->value,
                            outgoing => $dest->field('outgoing')->value,
                            status => $dest->field('status')->value,
                        });
                    }
                }
                last SWITCH;
            };
            # default
            NGCP::Panel::Utils::Message->error(
                c     => $c,
                log   => "trying to set invalid fax param '$attribute' for subscriber uuid ".$c->stash->{subscriber}->uuid,
                desc  => $c->loc('Invalid fax setting.'),
            );
            NGCP::Panel::Utils::Navigation::back_or($c,
                $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
            return;
        } # SWITCH
        if($posted && $form->validated) {
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully updated fax setting'),
            );
            NGCP::Panel::Utils::Navigation::back_or($c, 
                $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]), 1);
            return;
        }
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
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

sub edit_reminder :Chained('base') :PathPart('preferences/reminder/edit') {
    my ($self, $c, $attribute) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    my $posted = ($c->request->method eq 'POST');
    my $reminder = $c->stash->{subscriber}->provisioning_voip_subscriber->voip_reminder;
    my $params = {};
    
    if(!$posted && $reminder) {
        $params = { 'time' => $reminder->column_time, recur => $reminder->recur};
    }

    my $form = NGCP::Panel::Form::Reminder->new;
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
            if($form->field('time')->value) {
                my $t = $form->field('time')->value;
                $t =~ s/^(\d+:\d+)(:\d+)?$/$1/; # strip seconds
                if($reminder) {
                    $reminder->update({
                        time => $t,
                        recur => $form->field('recur')->value,
                    });
                } else {
                    $c->model('DB')->resultset('voip_reminder')->create({
                        subscriber_id => $c->stash->{subscriber}->provisioning_voip_subscriber->id,
                        time => $t,
                        recur => $form->field('recur')->value,
                    });
                }
            } elsif($reminder) {
                $reminder->delete;
            }
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully updated reminder setting'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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

sub ajax_calls :Chained('master') :PathPart('calls/ajax') :Args(0) {
    my ($self, $c) = @_;

    # CDRs
    my $rs = $c->model('DB')->resultset('cdr')->search({
        -or => [
            source_user_id => $c->stash->{subscriber}->uuid,
            destination_user_id => $c->stash->{subscriber}->uuid,
        ],
    });
    NGCP::Panel::Utils::Datatables::process(
        $c, $rs, $c->stash->{calls_dt_columns},
        sub {
            my ($result) = @_;
            my %data = ();
            if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
                $data{duration} = POSIX::ceil($result->duration);
                $data{source_user} = uri_unescape(NGCP::Panel::Utils::Subscriber::apply_rewrite(
                    c => $c, subscriber => $c->stash->{subscriber}, number => $result->source_user, direction => 'caller_out'
                ));
                $data{destination_user} = uri_unescape(NGCP::Panel::Utils::Subscriber::apply_rewrite(
                    c => $c, subscriber => $c->stash->{subscriber}, number => $result->destination_user, direction => 'caller_out'
                ));
            } else {
                $data{source_user} = uri_unescape($result->source_user);
                $data{destination_user} = uri_unescape($result->destination_user);
            }
            return %data;
        },
    );

    $c->detach( $c->view("JSON") );
}
sub ajax_call_details :Chained('master') :PathPart('calls/ajax') :Args(1) {
    my ($self, $c, $call_id) = @_;
    my $call = $c->model('DB')->resultset('cdr')->search_rs({
        id => $call_id,
    });
    $c->stash( 
        template => 'subscriber/call_details.tt',
        call     => { $call->first->get_inflated_columns } );
    $c->detach( $c->view('TT') );
}

sub ajax_registered :Chained('master') :PathPart('registered/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $s = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $reg_rs = $c->model('DB')->resultset('location')->search({
        username => $s->username,
    });
    if($c->config->{features}->{multidomain}) {
        $reg_rs = $reg_rs->search({
            domain => $s->domain->domain,
        });
    }

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

sub ajax_captured_calls :Chained('master') :PathPart('callflow/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $rs = $c->model('DB')->resultset('messages')->search({
        -or => [
            'me.caller_uuid' => $c->stash->{subscriber}->uuid,
            'me.callee_uuid' => $c->stash->{subscriber}->uuid,
        ],
    }, {
        order_by => { -desc => 'me.timestamp' },
        group_by => 'me.call_id',
    });

    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{capture_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub voicemail :Chained('master') :PathPart('voicemail') :CaptureArgs(1) {
    my ($self, $c, $vm_id) = @_;

    my $rs = $c->model('DB')->resultset('voicemail_spool')->search({
         mailboxuser => $c->stash->{subscriber}->uuid,
         id => $vm_id,
    });
    unless($rs->first) {
        NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Transcode of audio file failed'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
    }
    
    my $dir = $file->dir;
    $dir =~s/INBOX$/Old/;
    $file->update({ dir => $dir });
    
    $self->vmnotify($c, $c->stash->{voicemail});
    
    $c->response->header('Content-Disposition' => 'attachment; filename="'.$file->msgnum.'.wav"');
    $c->response->content_type('audio/x-wav');
    $c->response->body($data);
}

sub delete_voicemail :Chained('voicemail') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    try {
        $c->stash->{voicemail}->delete;
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $c->stash->{voicemail}->get_inflated_columns },
            desc => $c->loc('Successfully deleted voicemail'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete voicemail message'),
        );
    }
    $self->vmnotify($c, $c->stash->{voicemail});
    NGCP::Panel::Utils::Navigation::back_or($c, 
        $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
}

sub vmnotify :Private(){
    my ($self, $c, $voicemail) = @_;
    #1.although method is called after delete - DBIC still can access data in deleted row
    #2.amount of the new messages should be selected after played update or delete, of course
    
    my $data = { $voicemail->get_inflated_columns };
    $data->{cli} = $voicemail->mailboxuser->provisioning_voip_subscriber->username;
    $data->{context} = 'default';
    
    $data->{messages_amount} = $c->model('DB')->resultset('voicemail_spool')->find({
        'mailboxuser' => $data->{mailboxuser},
        'msgnum'      => { '>=' => 0 },
        'dir'         => { 'like' => '%/INBOX' },
    },{
        'select'      => [{'count' => '*', -as => 'messages_number'}]
    })->get_column('messages_number');
    
    my @cmd = ('vmnotify',@$data{qw/context cli messages_amount/});
    my $output = capturex([0..3],@cmd);
    $c->log->debug("cmd=".join(" ", @cmd)."; output=$output;");
}
sub registered :Chained('master') :PathPart('registered') :CaptureArgs(1) {
    my ($self, $c, $reg_id) = @_;

    my $s = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $reg_rs = $c->model('DB')->resultset('location')->search({
        id => $reg_id,
        username => $s->username,
    });
    if($c->config->{features}->{multidomain}) {
        $reg_rs = $reg_rs->search({
            domain => $s->domain->domain,
        });
    }
    $c->stash->{registered} = $reg_rs->first;
    unless($c->stash->{registered}) {
        NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete registered device'),
        );
    }

    NGCP::Panel::Utils::Message->info(
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

    my $form = NGCP::Panel::Form::Subscriber::Location->new;
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
            NGCP::Panel::Utils::Kamailio::create_location($c, 
                $c->stash->{subscriber}->provisioning_voip_subscriber, 
                $form->field('contact')->value,
                $form->field('q')->value
            );
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully added registered device'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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
    
    my $form = NGCP::Panel::Form::Subscriber::TrustedSource->new;
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
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully created trusted source'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->error(
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

    my $form = NGCP::Panel::Form::Subscriber::TrustedSource->new;
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
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully updated trusted source'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $c->stash->{trusted}->get_inflated_columns },
            desc => $c->loc('Successfully deleted trusted source'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete trusted source.'),
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
    my $form = NGCP::Panel::Form::Subscriber::SpeedDial->new(ctx => $c);
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
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully created speed dial slot'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $c->stash->{speeddial}->get_inflated_columns },
            desc => $c->loc('Successfully deleted speed dial slot'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
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
    my $form = NGCP::Panel::Form::Subscriber::SpeedDial->new(ctx => $c);

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
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully updated speed dial slot'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $c->stash->{autoattendant}->get_inflated_columns },
            desc => $c->loc('Successfully deleted auto attendant slot'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
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
    my $form = NGCP::Panel::Form::Subscriber::AutoAttendant->new;

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
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully updated auto attendant slots'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $c->stash->{ccmapping}->get_inflated_columns },
            desc => $c->loc('Successfully deleted ccmapping'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
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
    my $form = NGCP::Panel::Form::CCMapEntries->new;

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
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully updated ccmappings'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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

    my $decoder = URI::Encode->new;
    $c->stash->{callid} = $decoder->decode($callid);
}

sub get_pcap :Chained('callflow_base') :PathPart('pcap') :Args(0) {
    my ($self, $c) = @_;
    my $cid = $c->stash->{callid};

    my $packet_rs = $c->model('DB')->resultset('packets')->search({
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

sub get_png :Chained('callflow_base') :PathPart('png') :Args(0) {
    my ($self, $c) = @_;
    my $cid = $c->stash->{callid};

    my $calls_rs = $c->model('DB')->resultset('messages')->search({
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

    my $calls_rs = $c->model('DB')->resultset('messages')->search({
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

    my $packet = $c->model('DB')->resultset('messages')->find({
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

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
