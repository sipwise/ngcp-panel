package NGCP::Panel::Role::API::PhonebookEntries;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

no strict 'refs';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

sub resource_name{
    return 'phonebookentries';
}

sub dispatch_path{
    return '/api/phonebookentries/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-phonebookentries';
}

sub _item_rs {
    my ($self, $c) = @_;
    my($owner,$type,$parameter,$value) = $self->check_owner_params($c);
    return unless $owner;
    my $method = 'get_'.$type.'_phonebook_rs';
    my ($list_rs,$item_rs) = &$method($c, $value, $type);
    return $list_rs;
}

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::AdminAPI", $c);
    } elsif ($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::ResellerAPI", $c);
    } elsif ($c->user->roles eq 'subscriber' 
        || $c->user->roles eq 'subscriberadmin') {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Phone::SubscriberAPI", $c);
    }
}

sub check_owner_params {
    my($self, $c, $params) = @_;
    my %allowed_params;
    if ($c->user->roles eq "admin") {
        @allowed_params{qw/reseller_id contract_id subscriber_id/} = (1) x 3;
    } elsif ($c->user->roles eq "reseller") {
        @allowed_params{qw/contract_id subscriber_id/} = (1) x 3;
    } elsif ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') {
        @allowed_params{qw/subscriber_id/} = (1) x 3;
    }

    $params //= $self->get_info_data($c);
    my %owner_params = 
        map { $_ => $params->{$_} } 
        grep { exists $params->{$_} } 
            (qw/reseller_id contract_id subscriber_id/);
    if (!grep { exists $allowed_params{$_}} keys %owner_params) {
        $c->log->error('"'.join('" or "', keys %allowed_params).'" should be specified');
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, '"'.join('" or "', keys %allowed_params).'" should be specified.');
        return;
    }

    if (1 < scalar keys %owner_params) {
        $c->log->error('Too many owners: '.join(',',keys %owner_params));
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Only one of the reseller_id, contract_id,subscriber_id can be specified.");
        return;
    }
    my $schema = $c->model('DB');
    my ($parameter,$value) = each %owner_params;
    my ($owner,$type);
    if ('reseller_id' eq $parameter) {
        $type = 'reseller';
        $owner = $schema->resultset('resellers')->find($value);
    } elsif ('contract_id' eq $parameter) {
        $type = 'contract';
        if ($c->user->roles eq "admin") {
            $owner = $schema->resultset('contracts')->find($value);
        } elsif ($c->user->roles eq "reseller") {
            $owner = $schema->resultset('contracts')->find({
                    id => $value,
                    'contact.reseller_id' => $c->user->reseller_id,
                },{ 
                    join => 'contact',
                });
        }
    } elsif ('subscriber_id' eq $parameter) {
        $type = 'subscriber';
        if ($c->user->roles eq "admin") {
            $owner = $schema->resultset('voip_subscribers')->find($value);
        } elsif ($c->user->roles eq "reseller") {
            $owner = $schema->resultset('voip_subscribers')->find({
                    id => $value,
                    'contact.reseller_id' => $c->user->reseller_id,
                },{ 
                    join => { 'contract' => 'contact' },
                });
        } elsif ($c->user->roles eq "subscriberadmin") {
            $owner = $schema->resultset('voip_subscribers')->find({
                    id => $value,
                    'contract.id' => $c->user->contract->id,
                },{ 
                    join => 'contract',
                });
        } elsif ($c->user->roles eq "subscriber") {
            $value = $c->user->voip_subscriber->id;
            $owner = $schema->resultset('voip_subscribers')->find({
                    id => $c->user->voip_subscriber->id,
                });
        }
    }
    unless($owner) {
        $c->log->error("Unknown $parameter value '$value'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Unknown $parameter value '$value'");
        return;
    }
    return ($owner,$type,$parameter,$value);
}

sub get_reseller_phonebook_rs {
    my ($c, $reseller_id, $context) = @_;

    my $list_rs = $c->model('DB')->resultset('reseller_phonebook')->search_rs({
            reseller_id => $reseller_id,
        },{
            columns => [qw/id name number/,
                #{ 'owner_type' => \['?', [{} => $context ? $context : 'reseller' ]] } ,
                { 'owner_id'   => 'me.reseller_id' } ,
                { 'shared'     => \'0'},
            ],
        });
    #$list_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    my $item_rs = $c->model('DB')->resultset('reseller_phonebook');
    return ($list_rs,$item_rs);
}

sub get_contract_phonebook_rs {
    my ($c, $contract_id, $context) = @_;

    my $contract_rs = $c->model('DB')->resultset('contracts')->search({
        id => $contract_id,
    })->first;
    #my ($reseller_pb_rs) = get_reseller_phonebook_rs($c, $contract_rs->contact->reseller->id, 'contract');
    my $contract_pb_rs = $c->model('DB')->resultset('contract_phonebook')->search_rs({
            contract_id => $contract_id,
        },{
            columns => [qw/id name number/,
                #{ 'owner_type' => \['?', [{} => $context ? $context : 'reseller' ]] },
                { 'owner_id'   => 'me.contract_id' } ,
                { 'shared'     => \'0'},
            ],
        });
    #$contract_pb_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    my $list_rs = $contract_pb_rs;
    #my $list_rs = $contract_pb_rs->union_all($reseller_pb_rs);
    my $item_rs = $c->model('DB')->resultset('contract_phonebook');
    return ($list_rs,$item_rs);
}

sub get_subscriber_phonebook_rs {
    my ($c, $subscriber_id) = @_;

    my $subscriber_rs = $c->model('DB')->resultset('voip_subscribers')->search({
        id => $subscriber_id,
    })->first;

    #my ($reseller_pb_rs) = get_reseller_phonebook_rs($c, $subscriber_rs->contract->contact->reseller->id, 'subscriber');
    #my ($contract_pb_rs) = get_reseller_phonebook_rs($c, $subscriber_rs->contract->id, 'subscriber');
    my $subscriber_pb_rs = $c->model('DB')->resultset('subscriber_phonebook')->search_rs({
            -or => [
                subscriber_id => $subscriber_id,
                { shared => 1,
                  'subscriber.contract_id' => $subscriber_rs->contract->id,
                },
            ],
        },{
            columns => [qw/id name number/,
                #{ 'owner_type' => \'subscriber'},
                { 'owner_id'   => 'me.subscriber_id' } ,
                { 'shared'     => 'me.shared'},
            ],
            'join' => 'contract',
        });
    #$subscriber_pb_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    #my $list_rs = $subscriber_pb_rs->union_all($contract_pb_rs,$reseller_pb_rs);
    my $list_rs = $subscriber_pb_rs;
    my $item_rs = $c->model('DB')->resultset('subscriber_phonebook');
    return ($list_rs,$item_rs);
}

1;
# vim: set tabstop=4 expandtab:
