package NGCP::Panel::Role::API::Conversations;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::CallList qw();
use NGCP::Panel::Utils::API::Calllist qw();
use NGCP::Panel::Utils::Fax;
use NGCP::Panel::Utils::Subscriber;

use NGCP::Panel::Utils::DateTime qw();
use DateTime::Format::Strptime qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form;
use Data::Dumper;

use Tie::IxHash;
#use Class::Hash;

sub item_name{
    return 'conversation';
}

sub resource_name{
    return 'conversations';
}

sub dispatch_path{
    return '/api/conversations/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-conversations';
}

sub config_allowed_roles {
    return [qw/admin reseller subscriberadmin subscriber/];
}

my %enabled_conversations = (
    call      => 1,
    voicemail => 1,
    sms       => 1,
    fax       => 1,
    xmpp      => 1,
);

my %call_fields = ();
my $call_fields_tied = tie(%call_fields, 'Tie::IxHash');
$call_fields{source_user_id} = 'me.source_user_id';
$call_fields{source_account_id} = 'me.source_account_id';
$call_fields{source_clir} = 'me.source_clir';
$call_fields{source_cli} = 'me.source_cli';
$call_fields{source_user} = 'me.source_user';
$call_fields{source_domain} = 'me.source_domain';

$call_fields{destination_user_id} = 'me.destination_user_id';
$call_fields{destination_account_id} = 'me.destination_account_id';
$call_fields{destination_user_in} = 'me.destination_user_in';
$call_fields{destination_domain} = 'me.destination_domain';

$call_fields{call_type} = 'me.call_type';
$call_fields{call_status} = 'me.call_status';
$call_fields{init_time} = 'me.init_time';
$call_fields{start_time} = 'me.start_time';
$call_fields{duration} = 'me.duration';

$call_fields{call_id} = 'me.call_id';
$call_fields{rating_status} = 'me.rating_status';
$call_fields{source_customer_cost} = 'me.source_customer_cost';
$call_fields{destination_customer_cost} = 'me.destination_customer_cost';
$call_fields{source_customer_free_time} = 'me.source_customer_free_time';
$call_fields{source_customer_billing_fee_id} = 'me.source_customer_billing_fee_id';
$call_fields{destination_customer_billing_fee_id} = 'me.destination_customer_billing_fee_id';

#this is exactly cdr item, although we take call fields.
#Call fields contain everyithing that process_cdr_item  requires
my %voicemail_fields = ();
my $voicemail_fields_tied = tie(%voicemail_fields, 'Tie::IxHash');
$voicemail_fields{duration} = 'me.duration';
$voicemail_fields{origtime} = 'me.origtime';
$voicemail_fields{callerid} = 'me.callerid';
$voicemail_fields{callee}   = 'me.callerid';
$voicemail_fields{mailboxuser} = 'me.mailboxuser';
$voicemail_fields{context} = 'me.context';
$voicemail_fields{macrocontext} = 'me.macrocontext';
$voicemail_fields{mailboxcontext} = 'me.mailboxcontext';
$voicemail_fields{dir} = 'me.dir';
$voicemail_fields{msgnum} = 'me.msgnum';
$voicemail_fields{call_id} = 'me.call_id';

my %sms_fields = ();
my $sms_fields_tied = tie(%sms_fields, 'Tie::IxHash');
$sms_fields{subscriber_id} = 'me.subscriber_id';
$sms_fields{time} = 'me.time';
$sms_fields{direction} = 'me.direction';
$sms_fields{caller} = 'me.caller';
$sms_fields{callee} = 'me.callee';
$sms_fields{text}   = 'me.text';
$sms_fields{reason} = 'me.reason';
$sms_fields{status} = 'me.status';

my %fax_fields = ();
my $fax_fields_tied = tie(%fax_fields, 'Tie::IxHash');
$fax_fields{subscriber_id} = 'me.subscriber_id';
$fax_fields{time} = 'me.time';
$fax_fields{direction} = 'me.direction';
$fax_fields{duration} = 'duration';
$fax_fields{caller} = 'me.caller';
$fax_fields{callee} = 'me.callee';
$fax_fields{pages} = 'me.pages';
$fax_fields{reason} = 'me.reason';
$fax_fields{status} = 'me.status';
$fax_fields{signal_rate} = 'me.signal_rate';
$fax_fields{quality} = 'me.quality';
$fax_fields{filename} = 'me.filename';
$fax_fields{sid} = 'me.sid';
$fax_fields{caller_uuid} = 'me.caller_uuid';
$fax_fields{callee_uuid} = 'me.callee_uuid';
$fax_fields{call_id} = 'me.call_id';

my %xmpp_fields = ();
my $xmpp_fields_tied = tie(%xmpp_fields, 'Tie::IxHash');
$xmpp_fields{subscriber_id} = 'me.id';
$xmpp_fields{user} = 'me.user';
$xmpp_fields{with} = 'me.with';
$xmpp_fields{epoch} = 'me.epoch';

my $max_fields = scalar keys %call_fields;
$max_fields += scalar NGCP::Panel::Utils::CallList::get_suppression_id_colnames();
$max_fields = scalar keys %voicemail_fields if ((scalar keys %voicemail_fields) > $max_fields);
$max_fields = scalar keys %sms_fields if ((scalar keys %sms_fields) > $max_fields);
$max_fields = scalar keys %fax_fields if ((scalar keys %fax_fields) > $max_fields);
$max_fields = scalar keys %xmpp_fields if ((scalar keys %xmpp_fields) > $max_fields);


my $cdr_proto = NGCP::Panel::Utils::Generic::hash2obj(
    classname => 'cdr_item',
    accessors => {
        %{_get_fields_names(\%call_fields,$call_fields_tied)},
        get_column => sub {
            my ($self,$colname) = @_;
            return $self->{$colname};
        },
        source_subscriber => sub {
            my $self = shift;
            return $self->{c}->model('DB')->resultset('voip_subscribers')->find({ uuid => $self->source_user_id() });
        },
        destination_subscriber => sub {
            my $self = shift;
            return $self->{c}->model('DB')->resultset('voip_subscribers')->find({ uuid => $self->destination_user_id() });
        },
    },
);
my $fax_proto = NGCP::Panel::Utils::Generic::hash2obj(
    classname => 'fax_item',
    accessors => {
        %{_get_fields_names(\%fax_fields,$fax_fields_tied)},
        get_column => sub {
            my ($self,$colname) = @_;
            return $self->{$colname};
        },
        caller_subscriber => sub {
            my $self = shift;
            return $self->{c}->model('DB')->resultset('voip_subscribers')->find({ uuid => $self->caller_uuid() });
        },
        callee_subscriber => sub {
            my $self = shift;
            return $self->{c}->model('DB')->resultset('voip_subscribers')->find({ uuid => $self->callee_uuid() });
        },
        provisioning_voip_subscriber => sub {
            my $self = shift;
            return $self->{c}->model('DB')->resultset('provisioning_voip_subscribers')->find({ id => $self->suscriber_id() });
        },
    },
);
my $voicemail_proto = NGCP::Panel::Utils::Generic::hash2obj(
    classname => 'voicemail_item',
    accessors => {
        %{_get_fields_names(\%voicemail_fields,$voicemail_fields_tied)},
        get_column => sub {
            my ($self,$colname) = @_;
            return $self->{$colname};
        },
    },
);
my $sms_proto = NGCP::Panel::Utils::Generic::hash2obj(
    classname => 'sms_item',
    accessors => {
        %{_get_fields_names(\%sms_fields,$sms_fields_tied)},
        get_column => sub {
            my ($self,$colname) = @_;
            return $self->{$colname};
        },
    },
);

my $xmpp_proto = NGCP::Panel::Utils::Generic::hash2obj(
    classname => 'xmpp_item',
    accessors => {
        %{_get_fields_names(\%xmpp_fields,$xmpp_fields_tied)},
        get_column => sub {
            my ($self,$colname) = @_;
            return $self->{$colname};
        },
    },
);

sub get_list{
    my ($self, $c) = @_;
#TODO: move to config and return to the SUPER (Entities) again
#So: if config->{methtod}->{required_params} eq '' owner
#and for other types of possible required parameters or predefined parameters groups
    my $owner = $self->get_owner_cached($c);
    unless (defined $owner) {
        return;
    }
    return $self->item_rs($c, $owner);
}

sub valid_id {
    my ($self, $c, $id) = @_;
    my $source = $c->req->params;
    my $type = $source->{type};
    unless($type){
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Mandatory parameter 'type' missing in request");
        return;
    }
    return $self->SUPER::valid_id($c, $id);
}

sub get_item_id{
    my($self, $c, $item, $resource, $form, $params) = @_;
    my $id;
    if('HASH' eq ref $item){
        $id = int($item->{id});
    }elsif(blessed $item){
        $id = int($item->id);
    }
    return $id;
}

sub get_mandatory_params {
    my ($self, $c, $href_type, $item, $resource, $params) = @_;
    my $owner = $self->get_owner_cached($c);
    return unless $owner;
    my %mandatory_params = (
        $owner->{subscriber}
        ? ( subscriber_id => $owner->{subscriber}->id )
        : ( customer_id => $owner->{customer}->id )
    );
    if ('item' eq $href_type) {
        if('HASH' eq ref $item){
            $mandatory_params{type} = $item->{type};
        }elsif(blessed $item){
            $mandatory_params{type} = $item->type;
        }
    }
    return \%mandatory_params;
}

sub _item_rs {
    my ($self, $c, $owner, $params) = @_;

    $params //= $c->req->params;
    $params = { %$params };
    my $schema = $c->model('DB');
    my ($uuid,$contract_id,$reseller_id,$provider_id,$show);

    $contract_id = $owner->{customer} ? $owner->{customer}->id : undef ;
    $uuid = $owner->{subscriber} ? $owner->{subscriber}->uuid : undef;
    $reseller_id = $owner->{customer} ? $owner->{customer}->contact->reseller_id : undef;
    $provider_id =  $owner->{customer} ? $owner->{customer}->contact->reseller->contract_id : undef;

    my $item_rs;
    my $type_param = ((exists $params->{type}) ? ($params->{type} // '') : undef);
    foreach my $type (qw(call voicemail sms fax xmpp)) {
        if ($enabled_conversations{$type} and ((not defined $type_param) or index(lc($type_param),$type) > -1)) {
            my $sub_name = '_get_' . $type . '_rs';
            my $rs = $self->$sub_name(
                c => $c,
                uuid => $uuid,
                contract_id => $contract_id,
                reseller_id => $reseller_id,
                provider_id => $provider_id,
                params => $params);
            if ($rs) {
                $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
                $item_rs = (defined $item_rs ? $item_rs->union_all($rs) : $rs);
            }
        }
    }

    return $item_rs;

}

sub _apply_timestamp_from_to {
    my $self = shift;
    my %params = @_;
    my ($rs,$params,$col,$cond_code) = @params{qw/rs params col cond/};

    $cond_code //= sub { return shift->epoch; };

    if (exists $params->{from}) {
        my $from = NGCP::Panel::Utils::DateTime::from_string($params->{from});
        if ($from) {
            $rs = $rs->search_rs({
                $col => { '>=' => &$cond_code($from) }
            });
        } else {
            #die invalid from timestamp $params->{from}
        }
    }
    if (exists $params->{to}) {
        my $to = NGCP::Panel::Utils::DateTime::from_string($params->{to});
        if ($to) {
            $rs = $rs->search_rs({
                $col => { '<=' => &$cond_code($to) }
            });
        } else {
            #die invalid to timestamp $params->{to}
        }
    }
    return $rs;
}

sub _apply_direction {
    my $self = shift;
    my %params = @_;
    my ($params,$apply_in_code,$apply_out_code,$apply_inout_code) = @params{qw/params in out inout/};

    $apply_in_code //= sub {};
    $apply_out_code //= sub {};
    $apply_inout_code //= sub {};

    if (exists $params->{direction}) {
        if ('in' eq lc($params->{direction})) {
            &$apply_in_code();
        } elsif ('out' eq lc($params->{direction})) {
            &$apply_out_code();
        } else {
            #die invalid to direction $params->{direction}
        }
    } else {
        &$apply_inout_code();
    }
}

sub _get_call_rs {

    my $self = shift;
    my %params = @_;
    my ($c,$uuid,$contract_id,$provider_id,$params) = @params{qw/c uuid contract_id provider_id params/};

    my $rs = $c->model('DB')->resultset('cdr');

    $rs = $self->_apply_timestamp_from_to(rs => $rs,params => $params,col => 'me.start_time');

    if ($provider_id) {
        $self->_apply_direction(params => $params,
            in => sub {
                $rs = $rs->search({
                    destination_provider_id => $provider_id
                });
            },
            out => sub {
                $rs = $rs->search({
                    source_provider_id => $provider_id
                });
            },
            inout => sub {
                $rs = $rs->search({
                    -or => [
                        { source_provider_id => $provider_id },
                        { destination_provider_id => $provider_id },
                    ],
                });
            },
        );
    }
    if ($contract_id) {
        $self->_apply_direction(params => $params,
            in => sub {
                $rs = $rs->search({
                    destination_account_id => $contract_id
                });
            },
            out => sub {
                $rs = $rs->search({
                    source_account_id => $contract_id
                });
            },
            inout => sub {
                $rs = $rs->search_rs({
                    -or => [
                        { source_account_id => $contract_id },
                        { destination_account_id => $contract_id },
                    ],
                });
            },
        );
    }
    my $max = scalar keys %call_fields;
    $rs = $rs->search(undef,{
        'select' => [
              { '' => \'"call"', -as => 'type' },
              { '' => 'me.id', -as => 'id' },
              { '' => 'me.start_time', -as => 'timestamp' },
              _get_select_list(\%call_fields,undef,$max), #_get_max_fields(1)),
            ],
        'as' => [
                 'type',
                 'id',
                 'timestamp',
                 _get_as_list(\%call_fields,undef,$max), #_get_max_fields(1)),
            ],
    });

    my @suppression_aliases = ();
    foreach (NGCP::Panel::Utils::CallList::get_suppression_id_colnames()) {
        $max += 1;
        push(@suppression_aliases,_get_alias($max));
    }
    if ($uuid) {
        my $out_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs->search_rs({
            source_user_id => $uuid,
        }),NGCP::Panel::Utils::CallList::SUPPRESS_OUT,@suppression_aliases);
        my $in_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs->search_rs({
            destination_user_id => $uuid,
            source_user_id => { '!=' => $uuid },
        }),NGCP::Panel::Utils::CallList::SUPPRESS_IN,@suppression_aliases);

        $self->_apply_direction(params => $params,
            in => sub {
                $rs = $in_rs;
            },
            out => sub {
                $rs = $out_rs;
            },
            inout => sub {
                $rs = $out_rs->union_all($in_rs);
            },
        );
    } else {
        $rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs,
            NGCP::Panel::Utils::CallList::SUPPRESS_INOUT,@suppression_aliases);
    }
    return $rs->search(undef,{
        '+select' => [
              _get_select_list(\%call_fields,$max,undef), #_get_max_fields(1)),
            ],
        '+as' => [
                 _get_as_list(\%call_fields,$max,undef), #_get_max_fields(1)),
            ],
    }) if $max_fields > $max;
    return $rs;

}

sub _get_voicemail_rs {

    my $self = shift;
    my %params = @_;
    my ($c,$uuid,$contract_id,$reseller_id,$params) = @params{qw/c uuid contract_id reseller_id params/};

    my $rs = $c->model('DB')->resultset('voicemail_spool')->search({
        duration => { '!=' => '' },
    });

    $rs = $self->_apply_timestamp_from_to(rs => $rs,params => $params,col => 'me.origtime');

    if ($reseller_id) {
        $rs = $rs->search({
            'contact.reseller_id' => $reseller_id,
        },{
            join => { mailboxuser => { provisioning_voip_subscriber => { voip_subscriber => { contract => 'contact' } } } },
        });
    }
    if ($contract_id) {
        $rs = $rs->search({
            'contract.id' => $contract_id,
        },{
            join => { mailboxuser => { provisioning_voip_subscriber => { voip_subscriber => 'contract' } } },
        });
    }
    if ($uuid) {
        $rs = $rs->search({
            'voip_subscriber.uuid' => $uuid,
        },{
            join => { mailboxuser => { provisioning_voip_subscriber => 'voip_subscriber' } },
        });
    } else {
        $rs = $rs->search({
            'voip_subscriber.id' => { '!=' => undef },
        },{
            join => { mailboxuser => { provisioning_voip_subscriber => 'voip_subscriber' } },
        });
    }
    $rs = $rs->search(undef,{
        select => [
              { '' => \'"voicemail"', -as => 'type' },
              { '' => 'me.id', -as => 'id' },
              { '' => 'me.origtime', -as => 'timestamp' },
              _get_select_list(\%voicemail_fields),
            ],
        as => ['type','id','timestamp',_get_as_list(\%voicemail_fields),],
    });
    $self->_apply_direction(params => $params,
        out => sub {
            undef $rs;
        },
    );
    return $rs;

}

sub _get_sms_rs {

    my $self = shift;
    my %params = @_;
    my ($c,$uuid,$contract_id,$reseller_id,$params) = @params{qw/c uuid contract_id reseller_id params/};

    my $rs = $c->model('DB')->resultset('sms_journal');

    $rs = $self->_apply_timestamp_from_to(rs => $rs,params => $params,col => 'me.time');

    $self->_apply_direction(params => $params,
        in => sub {
            $rs = $rs->search_rs({
                'me.direction' => 'in',
            });
        },
        out => sub {
            $rs = $rs->search_rs({
                'me.direction' => 'out',
            });
        },
    );

    if ($reseller_id) {
        $rs = $rs->search_rs({
            'contact.reseller_id' => $reseller_id,
        },{
            join => { provisioning_voip_subscriber => { voip_subscriber => { contract => 'contact'} } },
        });
    }
    if ($contract_id) {
        $rs = $rs->search({
            'contract.id' => $contract_id,
        },{
            join => { provisioning_voip_subscriber => { voip_subscriber => 'contract' } },
        });
    }
    if ($uuid) {
        $rs = $rs->search_rs({
            'provisioning_voip_subscriber.uuid' => $uuid,
        },{
            join => 'provisioning_voip_subscriber',
        });
    }
    return $rs->search(undef,{
        select => [
              { '' => \'"sms"', -as => 'type' },
              { '' => 'me.id', -as => 'id' },
              { '' => \'unix_timestamp(me.time)', -as => 'timestamp' },
              _get_select_list(\%sms_fields),
            ],
        as => ['type','id','timestamp',_get_as_list(\%sms_fields),],
    });

}

sub _get_fax_rs {

    my $self = shift;
    my %params = @_;
    my ($c,$uuid,$contract_id,$reseller_id,$params) = @params{qw/c uuid contract_id reseller_id params/};

    my $rs = $c->model('DB')->resultset('voip_fax_journal');

    $rs = $self->_apply_timestamp_from_to(rs => $rs,params => $params,col => 'me.time');

    $self->_apply_direction(params => $params,
        in => sub {
            $rs = $rs->search_rs({
                'me.direction' => 'in',
            });
        },
        out => sub {
            $rs = $rs->search_rs({
                'me.direction' => 'out',
            });
        },
    );

    if ($reseller_id) {
        $rs = $rs->search_rs({
            'contact.reseller_id' => $reseller_id,
        },{
            join => { provisioning_voip_subscriber => { voip_subscriber => { contract => 'contact'} } },
        });
    }
    if ($contract_id) {
        $rs = $rs->search({
            'contract.id' => $contract_id,
        },{
            join => { provisioning_voip_subscriber => { voip_subscriber => 'contract' } },
        });
    }
    if ($uuid) {
        $rs = $rs->search({
            'voip_subscriber.uuid' => $uuid,
        },{
            join => { provisioning_voip_subscriber => 'voip_subscriber' },
        });
    } else {
        $rs = $rs->search({
            'voip_subscriber.id' => { '!=' => undef },
        },{
            join => { provisioning_voip_subscriber => 'voip_subscriber' },
        });
    }
    return $rs->search(undef,{
        select => [
              { '' => \'"fax"', -as => 'type' },
              { '' => 'me.id', -as => 'id' },
              { '' => 'me.time', -as => 'timestamp' },
              _get_select_list(\%fax_fields),
            ],
        as => ['type','id','timestamp',_get_as_list(\%fax_fields),],
    });

}

sub _get_xmpp_rs {

    my $self = shift;
    my %params = @_;
    my ($c,$uuid,$contract_id,$reseller_id,$params) = @params{qw/c uuid contract_id reseller_id params/};

    my $rs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search_rs(undef,{
        #join => [ 'domain', 'sipwise_mam_user', 'sipwise_mam_with' ],
        join => 'domain',
    });

    $rs = $self->_apply_timestamp_from_to(rs => $rs,params => $params,col => 'epoch');

    if ($reseller_id) {
        $rs = $rs->search_rs({
            'contact.reseller_id' => $reseller_id,
        },{
            join => { voip_subscriber => { contract => 'contact'} },
        });
    }
    if ($contract_id) {
        $rs = $rs->search({
            'contract.id' => $contract_id,
        },{
            join => { voip_subscriber => 'contract' },
        });
    }
    if ($uuid) {
        $rs = $rs->search({
            'me.uuid' => $uuid,
        });
    }

    my $out_rs = $rs->search_rs(undef,{
        join => 'sipwise_mam_user',
        '+select' => [
            { '' => \'"out"', -as => 'direction' },
            { '' => 'sipwise_mam_user.id', -as => 'mam_id' },
            { '' => 'sipwise_mam_user.username', -as => 'user' },
            { '' => 'sipwise_mam_user.with', -as => 'with' },
            { '' => 'sipwise_mam_user.epoch', -as => 'epoch' },
        ],
        '+as' => ['direction','mam_id','user','with','epoch'],
    });
    my $in_rs = $rs->search_rs(undef,{
        join => 'sipwise_mam_with',
        '+select' => [
            { '' => \'"in"', -as => 'direction' },
            { '' => 'sipwise_mam_with.id', -as => 'mam_id' },
            { '' => 'sipwise_mam_with.username', -as => 'user' },
            { '' => 'sipwise_mam_with.with', -as => 'with' },
            { '' => 'sipwise_mam_with.epoch', -as => 'epoch' },
        ],
        '+as' => ['direction','mam_id','user','with','epoch'],
    });

    $self->_apply_direction(params => $params,
        in => sub {
            $rs = $in_rs;
        },
        out => sub {
            $rs = $out_rs;
        },
        inout => sub {
            $rs = $out_rs->union_all($in_rs);
        },
    );

    return $rs->search(undef,{
        select => [
              { '' => \'"xmpp"', -as => 'type' },
              { '' => 'mam_id', -as => 'id' },
              { '' => 'epoch', -as => 'timestamp' },
              _get_select_list(\%xmpp_fields),
            ],
        as => ['type','id','timestamp',_get_as_list(\%xmpp_fields),],
    });

}

sub _get_select_list {

    my ($fields,$min,$max) = @_;
    $min //= 1;
    $max //= $max_fields;
    my @projections = values %$fields;
    my @select = ();
    foreach my $i ($min..$max) {
        push(@select,{
            '' => ($projections[$i - 1] ? $projections[$i - 1] : \'""'),
            -as => _get_alias($i)
        });
    }
    return @select;

}

sub _get_as_list {

    my ($fields,$min,$max) = @_;
    $min //= 1;
    $max //= $max_fields;
    my @accessors = keys %$fields;
    my @as = ();
    foreach my $i ($min..$max) {
        push(@as,_get_alias($i));
        #push(@as,($accessors[$i - 1] ? $accessors[$i - 1] : 'field'.$i));
    }
    return @as;
}

sub _get_alias {
    return 'field' . shift;
}

sub get_form {
    my ($self, $c) = @_;
    return (NGCP::Panel::Form::get("NGCP::Panel::Form::Conversation::API", $c));
}

sub process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    my $schema = $c->model('DB');
    # todo: mashal specific fields, per conversation event type ...
    #$c->log->debug(Dumper('item'));
    #$c->log->debug(Dumper($item));
    my ($item_mock_obj, $item_accessors_hash) = _get_item_object($c, $item);
    if('call' eq $item->{type}){
        my $owner = $self->get_owner_cached($c);
        return unless $owner;
        $resource = NGCP::Panel::Utils::CallList::process_cdr_item(
            $c,
            $item_mock_obj,
            $owner,
        );
        if ("out" eq $resource->{direction}) {
            @{$resource}{qw/caller callee/} = @{$resource}{qw/own_cli other_cli/};
        } else {
            @{$resource}{qw/caller callee/} = @{$resource}{qw/other_cli own_cli/};
        }
        $resource->{type} = $item->{type};
        my $fee;
        if ($fee = $schema->resultset('billing_fees_history')->search_rs({
                'id' => ($resource->{direction} eq "out" ? $item_mock_obj->source_customer_billing_fee_id : $item_mock_obj->destination_customer_billing_fee_id),
            })->first
            and
            my $profile = $schema->resultset('billing_profiles')->search_rs({ #we dont want a cascade relationship in billing_fees_history
                'id' => $fee->billing_profile_id,
            })->first) {
            $resource->{currency} = $profile->currency // '';
        } else {
            $resource->{currency} = '';
        }
    }elsif('fax' eq $item->{type}){
        my $fax_subscriber_provisioning = $schema->resultset('provisioning_voip_subscribers')->search_rs({
            'id' => $item_mock_obj->subscriber_id,
        })->first;
        my $fax_subscriber_billing = $fax_subscriber_provisioning->voip_subscriber;
        my $number_rewrite_mode = $c->request->query_params->{start} //
                                  $c->config->{faxserver}->{number_rewrite_mode};
        $resource = $number_rewrite_mode eq 'extended'
                    ? NGCP::Panel::Utils::Fax::process_extended_fax_journal_item(
                        $c, $item_mock_obj, $fax_subscriber_billing)
                    : NGCP::Panel::Utils::Fax::process_fax_journal_item(
                        $c, $item_mock_obj, $fax_subscriber_billing);
        foreach my $field (qw/type id status reason pages filename direction/){
            $resource->{$field} = $item_mock_obj->$field;
        }
        $resource->{subscriber_id} = $fax_subscriber_billing->id;
        $resource->{call_id} = $item_mock_obj->call_id;
    }elsif('voicemail' eq $item->{type}){
        $resource = $item_accessors_hash;
        $resource->{caller} = $item_mock_obj->callerid;
        $resource->{voicemail_subscriber_id} = $schema->resultset('voicemail_spool')->search_rs({
            'mailboxuser' => $item_mock_obj->mailboxuser,
        })->first->mailboxuser->provisioning_voip_subscriber->voip_subscriber->id;
        # type is last item of path like /var/spool/asterisk/voicemail/default/uuid/INBOX
        my $filename = NGCP::Panel::Utils::Subscriber::get_voicemail_filename($c,$item_mock_obj);
        my @p = split /\//, $item_mock_obj->dir;
        $resource->{folder} = pop @p;
        $resource->{direction} = 'in';
        $resource->{filename} = $filename;
        $resource->{call_id} = $item_mock_obj->call_id;
    }elsif('sms' eq $item->{type}){
        $resource = $item_accessors_hash;
        #$resource->{start_time} =  NGCP::Panel::Utils::DateTime::from_string($item_mock_obj->timestamp)->epoch;
    }elsif('xmpp' eq $item->{type}){
        $resource = $item_accessors_hash;
    }
    #$c->log->debug(Dumper('resource'));
    #$c->log->debug(Dumper($resource));
    $resource->{start_time} = undef;
    if ($item_mock_obj->timestamp) {
        my $datetime_fmt = DateTime::Format::Strptime->new(
            pattern => '%F %T',
        );
        my $timestamp = NGCP::Panel::Utils::API::Calllist::apply_owner_timezone($self,$c,
            NGCP::Panel::Utils::DateTime::epoch_local($item_mock_obj->timestamp),$self->get_owner_cached($c));
        $resource->{start_time} = $datetime_fmt->format_datetime($timestamp);
        $resource->{start_time} .= '.' . sprintf("%03d",$timestamp->millisecond) if $timestamp->millisecond > 0.0;
    }
    return $resource;
}

sub get_owner_cached{
    my ($self, $c) = @_;
    my $schema = $c->model('DB');
    if ( ! $c->stash->{owner} ) {
        my $source;
        if ($c->req->params->{customer_id} or $c->req->params->{subscriber_id}) {
            $source = $c->req->params;
        }
        $c->stash->{owner} = NGCP::Panel::Utils::API::Calllist::get_owner_data($self, $c, $schema, $source);
    }
    return $c->stash->{owner};
}

sub _get_fields_names{
    my ($fields, $fields_tied) = @_;
    return { map { $_ => $fields_tied->Indices($_) ? _get_alias($fields_tied->Indices($_) + 1) : $_; } (keys %$fields, 'id','type','timestamp') };
}

sub _get_item_object{
    my($c, $item) = @_;
    my ($fields, $fields_tied, $class_proto) = _get_fields_by_type($item->{type});

    my $item_accessors_hash = {%$item};
    foreach(keys %$fields){
        $item_accessors_hash->{$_} = $item->{_get_alias($fields_tied->Indices($_) + 1)};
    }

    my $item_mock_obj = NGCP::Panel::Utils::Generic::hash2obj(
        classname => ref $class_proto,
        hash => $item_accessors_hash,
        private => { c => $c, },
    );
    return ($item_mock_obj, $item_accessors_hash);
}

sub _get_fields_by_type{
    my($type) = @_;
    my ($fields, $fields_tied, $proto);

    if('call' eq $type){
        $fields = \%call_fields;
        $fields_tied = $call_fields_tied;
        $proto = $cdr_proto;
    }elsif('voicemail' eq $type){
        $fields = \%voicemail_fields;
        $fields_tied = $voicemail_fields_tied;
        $proto = $voicemail_proto;
    }elsif('sms' eq $type){
        $fields = \%sms_fields;
        $fields_tied = $sms_fields_tied;
        $proto = $sms_proto;
    }elsif('fax' eq $type){
        $fields = \%fax_fields;
        $fields_tied = $fax_fields_tied;
        $proto = $fax_proto;
    }elsif('xmpp' eq $type){
        $fields = \%xmpp_fields;
        $fields_tied = $xmpp_fields_tied;
        $proto = $xmpp_proto;
    }
    return $fields,$fields_tied,$proto;
}

sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;
    #$c->log->debug("hal_links: type=".($resource->{type} // 'undefined')."; id=".($resource->{id} // 'undefined').";");
    return [
        ('call' eq $resource->{type} ? (
                Data::HAL::Link->new(relation => 'ngcp:calls', href => sprintf("/api/calls/%d", $resource->{id})),
           ) : ()),
        ('voicemail' eq $resource->{type} ? (
                Data::HAL::Link->new(relation => 'ngcp:voicemails', href => sprintf("/api/voicemails/%d", $resource->{id})),
                Data::HAL::Link->new(relation => 'ngcp:voicemailrecordings', href => sprintf("/api/voicemailrecordings/%d", $resource->{id})),
           ) : ()),
        ('sms' eq $resource->{type} ? (
                Data::HAL::Link->new(relation => 'ngcp:sms', href => sprintf("/api/sms/%d", $resource->{id})),
           ) : ()),
        ('fax' eq $resource->{type} ? (
                Data::HAL::Link->new(relation => 'ngcp:faxes', href => sprintf("/api/faxes/%d", $resource->{id})),
                Data::HAL::Link->new(relation => 'ngcp:faxrecordings', href => sprintf("/api/faxrecordings/%d", $resource->{id})),
           ) : ()),
        # todo - add xmpp mam rail:
        #('xmpp' eq $item->{type} ? (
        #    Data::HAL::Link->new(relation => 'ngcp:xmpp', href => sprintf("/api/xmpp/%d", $item->{id})),
        # ) : ()),
    ];
}


1;
