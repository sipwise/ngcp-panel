package NGCP::Panel::Role::API::Conversations;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
#use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::CallList qw();

use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Conversation::API;

use Tie::IxHash;

my %call_fields = ();
tie(%call_fields, 'Tie::IxHash');
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
$call_fields{start_time} = 'me.start_time';
$call_fields{duration} = 'me.duration';

my %voicemail_fields = ();
tie(%voicemail_fields, 'Tie::IxHash');
$voicemail_fields{duration} = 'me.duration';
$voicemail_fields{origtime} = 'me.origtime';
$voicemail_fields{callerid} = 'me.callerid';
$voicemail_fields{mailboxuser} = 'me.mailboxuser';
$voicemail_fields{dir} = 'me.dir';

my %sms_fields = ();
tie(%sms_fields, 'Tie::IxHash');
$sms_fields{subscriber_id} = 'me.subscriber_id';
$sms_fields{time} = 'me.time';
$sms_fields{direction} = 'me.direction';
$sms_fields{caller} = 'me.callee';
$sms_fields{text} = 'me.text';
$sms_fields{reason} = 'me.reason';
$sms_fields{status} = 'me.status';

my %fax_fields = ();
tie(%fax_fields, 'Tie::IxHash');
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

my %xmpp_fields = ();
tie(%xmpp_fields, 'Tie::IxHash');
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

sub _item_rs {
    my ($self, $c) = @_;
    
    my ($uuid,$contract_id,$reseller_id,$provider_id);
    #$uuid = ...;
    #$contract_id = ...;
    if ($c->user->roles eq "subscriber") {
        $uuid = $c->user->voip_subscriber->uuid;
    } elsif ($c->user->roles eq "subscriberadmin") {
        $contract_id = $c->user->account_id;
    } elsif ($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
        $provider_id = $c->user->reseller->contract_id;
    }

    my $item_rs;
    if (1) {
        my $rs = $self->get_calls_rs($c,$uuid,$contract_id,$provider_id);
        $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
        $item_rs = (defined $item_rs ? $item_rs->union_all($rs) : $rs);
    }
    
    if (1) {
        my $rs = $self->get_voicemails_rs($c,$uuid,$contract_id,$reseller_id);
        $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
        $item_rs = (defined $item_rs ? $item_rs->union_all($rs) : $rs);
    }
    
    if (1) {
        my $rs = $self->get_sms_rs($c,$uuid,$contract_id,$reseller_id);
        $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
        $item_rs = (defined $item_rs ? $item_rs->union_all($rs) : $rs);
    }
    
    if (1) {
        my $rs = $self->get_faxes_rs($c,$uuid,$contract_id,$reseller_id);
        $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
        $item_rs = (defined $item_rs ? $item_rs->union_all($rs) : $rs);        
    }
    
    if (1) {
        my $rs = $self->get_xmpp_rs($c,$uuid,$contract_id,$reseller_id);
        $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
        $item_rs = (defined $item_rs ? $item_rs->union_all($rs) : $rs);        
    }
    
    return $item_rs;
    
    
}

sub get_calls_rs {
    
    my ($self,$c,$uuid,$contract_id,$provider_id) = @_;
    my $rs = $c->model('DB')->resultset('cdr');
    if ($provider_id) {
        $rs = $rs->search({
            -or => [
                { source_provider_id => $provider_id },
                { destination_provider_id => $provider_id },
            ],
        });        
    }
    if ($contract_id) {
        $rs = $rs->search_rs({
            -or => [
                { source_account_id => $contract_id },
                { destination_account_id => $contract_id },
            ],
        });    
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
        }),NGCP::Panel::Utils::CallList::SUPPRESS_IN,@suppression_aliases);
        $rs = $out_rs->union_all($in_rs);
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

sub get_voicemails_rs {
    
    my ($self,$c,$uuid,$contract_id,$reseller_id) = @_;

    my $rs = $c->model('DB')->resultset('voicemail_spool')->search({
        duration => { '!=' => '' },
    });
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
            'voip_subscriber.uuid' => $c->user->uuid,
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
    return $rs->search(undef,{
        select => [
              { '' => \'"voicemail"', -as => 'type' },
              { '' => 'me.id', -as => 'id' },
              { '' => 'me.origtime', -as => 'timestamp' },
              _get_select_list(\%voicemail_fields),
            ],
        as => [
               'type',
               'id',
               'timestamp',
               _get_as_list(\%voicemail_fields),
        ],
    });
    
}

sub get_sms_rs {
    
    my ($self,$c,$uuid,$contract_id,$reseller_id) = @_;


    my $rs = $c->model('DB')->resultset('sms_journal');
    if ($reseller_id) {
        $rs = $rs->search_rs({
            'contact.reseller_id' => $reseller_id,
        },{
            join => { provisioning_voip_subscriber => { subscriber => { contract => 'contact'} } },
        });
    }
    if ($contract_id) {
        $rs = $rs->search({
            'contract.id' => $contract_id,
        },{
            join => { provisioning_voip_subscriber => { subscriber => 'contract' } },
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
              { '' => 'me.time', -as => 'timestamp' },
              _get_select_list(\%sms_fields),
            ],
        as => ['type','id','timestamp',,_get_as_list(\%sms_fields),],
    });
    
}

sub get_faxes_rs {
    
    my ($self,$c,$uuid,$contract_id,$reseller_id) = @_;

    my $rs = $c->model('DB')->resultset('voip_fax_journal');
    if ($reseller_id) {
        $rs = $rs->search_rs({
            'contact.reseller_id' => $reseller_id,
        },{
            join => { provisioning_voip_subscriber => { subscriber => { contract => 'contact'} } },
        });
    }
    if ($contract_id) {
        $rs = $rs->search({
            'contract.id' => $contract_id,
        },{
            join => { provisioning_voip_subscriber => { subscriber => 'contract' } },
        }); 
    }
    if ($uuid) {
        $rs = $rs->search({
            'voip_subscriber.uuid' => $c->user->uuid,
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

sub get_xmpp_rs {
    
    my ($self,$c,$uuid,$contract_id,$reseller_id) = @_;

    my $rs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search_rs(undef,{
        #join => [ 'domain', 'sipwise_mam_user', 'sipwise_mam_with' ],
        join => 'domain',
    });
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
            'me.uuid' => $c->user->uuid,
        },undef);
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
    $rs = $out_rs->union_all($in_rs);
    
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
        push(@select,{ '' => ($projections[$i - 1] ? $projections[$i - 1] : \'""'), -as => _get_alias($i) });
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
    return (NGCP::Panel::Form::Conversation::API->new(ctx => $c),['customer_id','template_id']);
}

sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;
    return [
        #NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->contract_id)),
    ];
}

1;
# vim: set tabstop=4 expandtab:
