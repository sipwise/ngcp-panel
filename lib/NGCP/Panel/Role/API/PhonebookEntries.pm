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
    my ($self, $c, $id, $resource) = @_;
    my $params = $c->request->query_params;
    #if (!$resource) {
    #    my $method = uc($c->request->method);
    #    if ('PATCH' ne $method) {
    #        ($resource) = $self->get_valid_data(
    #            c => $c,
    #            media_type => ['application/json'],
    #            method => uc($c->request->method),
    #            id     => $id,
    #            uploads => [],
    #        );
    #    } else {
    #        $resource = $params;
    #    }
    #}
    my($owner,$type,$parameter,$value) = $self->check_owner_params($c, $params);
    return unless $owner;
    my $method = 'get_'.$type.'_phonebook_rs';
    my ($list_rs,$item_rs) = &$method($c, $value, $type);
    return $list_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c, $id);
    return unless $item_rs;
    return $item_rs->find($id);
}

sub get_form {
    my ($self, $c) = @_;
    my $params = $c->request->query_params;
    if ($params) {
        if ($params->{reseller_id}) {
            return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::ResellerAPI", $c);
        } elsif ($params->{customer_id}) {
            return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::CustomerAPI", $c);
        } elsif ($params->{subscriber_id}) {
            return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::SubscriberAPI", $c);
        }
    }
    if ($c->user->roles eq "admin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::ResellerAPI", $c);
    } elsif ($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::ResellerAPI", $c);
    } elsif ($c->user->roles eq 'subscriber' ||
             $c->user->roles eq 'subscriberadmin') {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::SubscriberAPI", $c);
    }
}

sub check_owner_params {
    my($self, $c, $params) = @_;
    my @allowed_params;
    if ($c->user->roles eq "admin") {
        @allowed_params = qw/reseller_id customer_id subscriber_id/;
    } elsif ($c->user->roles eq "reseller") {
        @allowed_params = qw/customer_id subscriber_id/;
    } elsif ($c->user->roles eq 'subscriberadmin') {
        @allowed_params = qw/customer_id subscriber_id/;
    } elsif ($c->user->roles eq 'subscriber') {
        @allowed_params = qw/subscriber_id/;
    }

    $params //= $c->request->params;
    my %owner_params =
        map { $_ => $params->{$_} }
            grep { exists $params->{$_} }
                (qw/reseller_id customer_id subscriber_id/);

    if (!grep { exists $owner_params{$_} } @allowed_params) {
        $c->log->error('"'.join('" or "', @allowed_params).'" should be specified');
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, '"'.join('" or "', @allowed_params).'" should be specified.');
        return;
    }

    if (scalar keys %owner_params > 1) {
        $c->log->error('Too many owners: '.join(',',keys %owner_params));
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
            sprintf("Only one of either %s should be specified",
                join(' or ', @allowed_params)));
        return;
    }

    my $schema = $c->model('DB');
    my ($parameter,$value) = each %owner_params;
    my ($owner,$type);

    unless (is_int($value)) {
        $c->log->error('Invalid owner id '.join(',',keys %owner_params));
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid owner id");
        return;
    }

    if ($parameter eq 'reseller_id') {
        $type = 'reseller';
        $owner = $schema->resultset('resellers')->find($value);
    } elsif ($parameter eq 'customer_id') {
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
        } elsif ($c->user->roles eq 'subscriberadmin' &&
                 $c->user->voip_subscriber->contract_id == $value) {
            $owner = $schema->resultset('contracts')->find({ id => $value });
        }
    } elsif ($parameter eq 'subscriber_id') {
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
        } elsif (($c->user->roles eq 'subscriberadmin' ||
                  $c->user->roles eq "subscriber") &&
                 $c->user->voip_subscriber->id == $value) {
            $owner = $schema->resultset('voip_subscribers')->find({ id => $value });
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
                { 'owner_id'   => 'me.reseller_id' } ,
                { 'shared'     => \'0'},
            ],
        });

    my $item_rs = $c->model('DB')->resultset('reseller_phonebook');
    return ($list_rs,$item_rs);
}

sub get_contract_phonebook_rs {
    my ($c, $contract_id, $context) = @_;

    my $contract_rs = $c->model('DB')->resultset('contracts')->search({
        id => $contract_id,
    })->first;

    my $contract_pb_rs = $c->model('DB')->resultset('contract_phonebook')->search_rs({
            contract_id => $contract_id,
        },{
            columns => [qw/id name number/,
                { 'owner_id'   => 'me.contract_id' } ,
                { 'shared'     => \'0'},
            ],
        });

    my $list_rs = $contract_pb_rs;
    my $item_rs = $c->model('DB')->resultset('contract_phonebook');
    return ($list_rs,$item_rs);
}

sub get_subscriber_phonebook_rs {
    my ($c, $subscriber_id) = @_;

    my $subscriber_rs = $c->model('DB')->resultset('voip_subscribers')->search({
        id => $subscriber_id,
    })->first;

    my $subscriber_pb_rs = $c->model('DB')->resultset('subscriber_phonebook')->search_rs({
            subscriber_id => $subscriber_id,
        },{
            columns => [qw/id name number/,
                { 'owner_id'   => 'me.subscriber_id' } ,
                { 'shared'     => 'me.shared'},
            ],
            'join' => 'subscriber',
        });

    my $list_rs = $subscriber_pb_rs;
    my $item_rs = $c->model('DB')->resultset('subscriber_phonebook');
    return ($list_rs,$item_rs);
}

1;
# vim: set tabstop=4 expandtab:
