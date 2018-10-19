package NGCP::Panel::Controller::SOAP::Intercept;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use File::Slurp;
use SOAP::Transport::LOCAL;

sub thewsdl : GET Path('/SOAP/Intercept.wsdl') :Local :Args() {
    my ($self, $c, $args) = @_;

    my $thewsdl = read_file('/etc/ngcp-panel/Intercept.wsdl');
    $c->response->body($thewsdl);
    $c->response->content_type('text/xml');
}

sub index : POST Path('/SOAP/Intercept') {
    my ($self, $c) = @_;
    my $h = Sipwise::SOAP::Intercept->new(c => $c);
    my $server = SOAP::Transport::LOCAL::Client->new;
    $server->serializer->register_ns('http://dev.sipwise.com/SOAP/Provisioning/Types', 'typens');
    my $out = $server
        ->dispatch_with({ 'urn:/SOAP/Intercept' => $h })
        ->handle($c->req->body);
    $c->response->content_type('text/xml');
    $c->response->body($out);
}

package Sipwise::SOAP::Intercept;
use Sipwise::Base;
use NGCP::Panel::Form;
use Data::Structure::Util qw/unbless/;
use NGCP::Panel::Utils::SOAP qw/typed/;
use NGCP::Panel::Utils::Interception qw();
use UUID;
use Moose;
use NGCP::Panel::Utils::Admin;
use Crypt::Eksblowfish::Bcrypt qw/bcrypt_hash en_base64 de_base64/;

has 'c' => (is => 'rw', isa => 'Object');

sub _validate {
    my ($self, $form, $data) = @_;

    unbless($data);
    $form->process(params => $data);
    unless($form->validated) {
        if($form->has_form_errors) {
            my @errs = $form->form_errors;
            die SOAP::Fault
                ->faultcode('Client.Syntax.MissingParameter')
                ->faultstring(shift @errs);
        } else {
            my @fields = $form->error_fields;
            my $field = shift @fields;
            my @errs = $field->errors;
            my $err = shift @errs;
            die SOAP::Fault
                ->faultcode('Client.Syntax.MalformedParameter')
                ->faultstring($field->label . ": " . join('; ', @{ $err }));
        }
    }
}


sub _auth {
    my ($self, $auth) = @_;
    my $c = $self->c;

    $self->_validate(NGCP::Panel::Form::get("NGCP::Panel::Form::Intercept::Authentication", $c), $auth);

    try {

        # check for general availability of user first, we need it in
        # both md5 and bcrypt cases
        my $admin = $c->model('DB')->resultset('admins')->search({
            login => $auth->{username},
            is_active => 1,
        })->first;
        die unless($admin && ($admin->is_superuser || $admin->lawful_intercept));

        if(defined $admin->saltedpass) {
            my ($db_b64salt, $db_b64hash) = split /\$/, $admin->saltedpass;
            my $salt = de_base64($db_b64salt);
            my $usr_b64hash = en_base64(bcrypt_hash({
                key_nul => 1,
                cost => NGCP::Panel::Utils::Admin::get_bcrypt_cost(),
                salt => $salt,
            }, $auth->{password}));

            die unless($usr_b64hash eq $db_b64hash);
            die unless($admin->is_superuser || $admin->lawful_intercept);
        } else {
            my $md5admin = $c->model('DB')->resultset('admins')->search({
                login => $auth->{username},
                is_active => 1,
                md5pass => { '=' => \['MD5("'.$auth->{password}.'")'] },
            })->first;
            die unless($md5admin && ($md5admin->is_superuser || $md5admin->lawful_intercept));

            # migrate password to bcrypt
            $admin->update({
                md5pass => undef,
                saltedpass => NGCP::Panel::Utils::Admin::get_salted_hash($auth->{password}),
            });
        }

    } catch($e) {
        die SOAP::Fault
            ->faultcode('Client.Auth.Refused')
            ->faultstring("admin may not access LI data (wrong credentials or lawful_intercept flag not set)");
    }
}

sub create_interception {
    my ($self, $auth, $params) = @_;
    my $c = $self->c;

    $self->_auth($auth);
    $self->_validate(NGCP::Panel::Form::get("NGCP::Panel::Form::Intercept::Create", $c), $params);

    my ($sub, $reseller, $voip_number, $sip_username, $sip_domain);
    try {
        ($sub, $reseller, $voip_number) = NGCP::Panel::Utils::Interception::subresnum_from_number($c, $params->{number}, sub {
            my ($msg,$field,$response) = @_;
            die SOAP::Fault
                ->faultcode($response)
                ->faultstring($msg);
            return 0;
        });
        $sip_username = NGCP::Panel::Utils::Interception::username_to_regexp_pattern($c,$voip_number,$sub->username);
        $sip_domain = $sub->domain->domain;
    } catch($e) {
        die $e if 'SOAP::Fault' eq ref $e;
        die SOAP::Fault
            ->faultcode('Server.Internal')
            ->faultstring($e);
    }

    my ($uuid_bin, $uuid_string);
    UUID::generate($uuid_bin);
    UUID::unparse($uuid_bin, $uuid_string);
    my $guard = $c->model('DB')->txn_scope_guard;
    my $i;
    {
        try {
            $i = $self->c->model('InterceptDB')->resultset('voip_intercept')->create({
                reseller_id => $reseller->id,
                LIID => $params->{LIID},
                number => $params->{number},
                cc_required => $params->{cc_required},
                delivery_host => $params->{iri_delivery}->{host},
                delivery_port => $params->{iri_delivery}->{port},
                delivery_user => $params->{iri_delivery}->{user},
                delivery_pass => $params->{iri_delivery}->{pass},
                deleted => 0,
                uuid => $uuid_string,
                sip_username => $sip_username,
                sip_domain => $sip_domain,
                create_timestamp => \['NOW()'],
                $params->{cc_required} ? (cc_delivery_host => $params->{cc_delivery}->{host}) : (),
                $params->{cc_required} ? (cc_delivery_port => $params->{cc_delivery}->{port}) : (),
            });
            $guard->commit;

            NGCP::Panel::Utils::Interception::request($c, 'POST', undef, {
                liid => $i->LIID,
                uuid => $i->uuid,
                number => $i->number,
                sip_username => $sip_username,
                sip_domain => $sip_domain,
                delivery_host => $i->delivery_host,
                delivery_port => $i->delivery_port,
                delivery_user => $i->delivery_user,
                delivery_password => $i->delivery_pass,
                cc_required => $i->cc_required,
                cc_delivery_host => $i->cc_delivery_host,
                cc_delivery_port => $i->cc_delivery_port,
            });
        } catch($e) {
            die SOAP::Fault
                ->faultcode('Server.Internal')
                ->faultstring($e);
        }
    }
    return typed($c, $i->id);
}

sub update_interception {
    my ($self, $auth, $params) = @_;
    my $c = $self->c;

    $self->_auth($auth);
    $self->_validate(NGCP::Panel::Form::get("NGCP::Panel::Form::Intercept::Update", $c), $params);

    my $i;
    try {
        $i = $c->model('DB')->resultset('voip_intercept')->search({
            id => $params->{id},
            deleted => 0,
        })->first;
    } catch($e) {
        die SOAP::Fault
            ->faultcode('Server.Internal')
            ->faultstring($e);
    }

    unless($i) {
        die SOAP::Fault
            ->faultcode('Client.Intercept.NoSuchInterception')
            ->faultstring("interception ID '$$params{id}' does not exist");
    }

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        if($params->{data}->{iri_delivery}) {
            $i->delivery_host($params->{data}->{iri_delivery}->{host});
            $i->delivery_port($params->{data}->{iri_delivery}->{port});
            $i->delivery_user($params->{data}->{iri_delivery}->{username});
            $i->delivery_pass($params->{data}->{iri_delivery}->{password});
        }
        if($params->{data}->{cc_delivery}) {
            $i->cc_delivery_host($params->{data}->{cc_delivery}->{host});
            $i->cc_delivery_port($params->{data}->{cc_delivery}->{port});
        }
        $i->cc_required($params->{data}->{cc_required});
        # not applying changed number/domain?

        try {
            $i->update();
            $guard->commit;

            NGCP::Panel::Utils::Interception::request($c, 'PUT', $i->uuid, {
                liid => $i->LIID,
                uuid => $i->uuid,
                number => $i->number,
                sip_username => $i->sip_username,
                sip_domain => $i->sip_domain,
                delivery_host => $i->delivery_host,
                delivery_port => $i->delivery_port,
                delivery_user => $i->delivery_user,
                delivery_password => $i->delivery_pass,
                cc_required => $i->cc_required,
                cc_delivery_host => $i->cc_delivery_host,
                cc_delivery_port => $i->cc_delivery_port,
            });
        } catch($e) {
            die SOAP::Fault
                ->faultcode('Server.Internal')
                ->faultstring($e);
        }
    }
    return;
}

sub delete_interception {
    my ($self, $auth, $params) = @_;
    my $c = $self->c;

    $self->_auth($auth);
    $self->_validate(NGCP::Panel::Form::get("NGCP::Panel::Form::Intercept::Delete", $c), $params);

    my $i;
    try {
        $i = $c->model('DB')->resultset('voip_intercept')->search({
            id => $params->{id},
            deleted => 0,
        })->first;
    } catch($e) {
        die SOAP::Fault
            ->faultcode('Server.Internal')
            ->faultstring($e);
    }

    unless($i) {
        die SOAP::Fault
            ->faultcode('Client.Intercept.NoSuchInterception')
            ->faultstring("interception ID '$$params{id}' does not exist");
    }

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        try {
            my $uuid = $i->uuid;
            $i->update({
                deleted => 1,
                reseller_id => undef,
                LIID => undef,
                number => undef,
                cc_required => 0,
                delivery_host => undef,
                delivery_port => undef,
                delivery_user => undef,
                delivery_pass => undef,
                cc_delivery_host => undef,
                cc_delivery_port => undef,
                sip_username => undef,
                sip_domain => undef,
                uuid => undef,
            });
            $guard->commit;

            NGCP::Panel::Utils::Interception::request($c, 'DELETE', $uuid);
        } catch($e) {
            die SOAP::Fault
                ->faultcode('Server.Internal')
                ->faultstring($e);
        }
    }
    return;
}

sub get_interception_by_id {
    my ($self, $auth, $params) = @_;
    my $c = $self->c;

    $self->_auth($auth);

    my $i;
    try {
        $i = $c->model('DB')->resultset('voip_intercept')->search({
            id => $params->{id},
            deleted => 0,
        })->first;
    } catch($e) {
        die SOAP::Fault
            ->faultcode('Server.Internal')
            ->faultstring($e);
    }

    unless($i) {
        die SOAP::Fault
            ->faultcode('Client.Intercept.NoSuchInterception')
            ->faultstring("interception ID '$$params{id}' does not exist");
    }

    return typed($c, {
        id => $i->id,
        LIID => $i->LIID,
        number => $i->number,
        cc_required => $i->cc_required,
        iri_delivery => {
            host => $i->delivery_host,
            port => $i->delivery_port,
            username => $i->delivery_user,
            password => $i->delivery_pass,
        },
        cc_delivery => {
            host => $i->cc_delivery_host,
            port => $i->cc_delivery_port,
        }
    });
}

sub get_interceptions_by_liid {
    my ($self, $auth, $params) = @_;
    my $c = $self->c;

    $self->_auth($auth);
    my @interceptions = ();

    try {
        my $rs = $c->model('DB')->resultset('voip_intercept')->search({
            LIID => $params->{LIID},
            deleted => 0,
        });
        while(my $i = $rs->next) {
            push @interceptions, {
                id => $i->id,
                LIID => $i->LIID,
                number => $i->number,
                cc_required => $i->cc_required,
                iri_delivery => {
                    host => $i->delivery_host,
                    port => $i->delivery_port,
                    username => $i->delivery_user,
                    password => $i->delivery_pass,
                },
                cc_delivery => {
                    host => $i->cc_delivery_host,
                    port => $i->cc_delivery_port,
                }
            };
        }
    } catch($e) {
        die SOAP::Fault
            ->faultcode('Server.Internal')
            ->faultstring($e);
    }
    return typed($c, \@interceptions);
}

sub get_interceptions_by_number {
    my ($self, $auth, $params) = @_;
    my $c = $self->c;

    $self->_auth($auth);
    my @interceptions = ();

    try {
        my $rs = $c->model('DB')->resultset('voip_intercept')->search({
            number => $params->{number},
            deleted => 0,
        });
        while(my $i = $rs->next) {
            push @interceptions, {
                id => $i->id,
                LIID => $i->LIID,
                number => $i->number,
                cc_required => $i->cc_required,
                iri_delivery => {
                    host => $i->delivery_host,
                    port => $i->delivery_port,
                    username => $i->delivery_user,
                    password => $i->delivery_pass,
                },
                cc_delivery => {
                    host => $i->cc_delivery_host,
                    port => $i->cc_delivery_port,
                }
            };
        }
    } catch($e) {
        die SOAP::Fault
            ->faultcode('Server.Internal')
            ->faultstring($e);
    }
    return typed($c, \@interceptions);
}

sub get_interceptions {
    my ($self, $auth, $params) = @_;
    my $c = $self->c;

    $self->_auth($auth);
    my @interceptions = ();

    try {
        my $rs = $c->model('DB')->resultset('voip_intercept')->search({
            deleted => 0,
        });
        while(my $i = $rs->next) {
            push @interceptions, {
                id => $i->id,
                LIID => $i->LIID,
                number => $i->number,
                cc_required => $i->cc_required,
                iri_delivery => {
                    host => $i->delivery_host,
                    port => $i->delivery_port,
                    username => $i->delivery_user,
                    password => $i->delivery_pass,
                },
                cc_delivery => {
                    host => $i->cc_delivery_host,
                    port => $i->cc_delivery_port,
                }
            };
        }
    } catch($e) {
        die SOAP::Fault
            ->faultcode('Server.Internal')
            ->faultstring($e);
    }
    return typed($c, \@interceptions);
}



1;

# vim: set tabstop=4 expandtab:
