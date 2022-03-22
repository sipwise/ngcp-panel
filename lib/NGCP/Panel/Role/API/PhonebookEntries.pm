package NGCP::Panel::Role::API::PhonebookEntries;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use HTTP::Status qw(:constants);
use List::Util qw(none any);

sub resource_name{
    return 'phonebookentries';
}

sub _item_rs {
    my ($self, $c) = @_;
    my($owner,$type,$parameter,$value) = $self->check_owner_params($c);
    return unless $owner;
    my ($list_rs,$item_rs);

    if ($type eq 'reseller') {
        ($list_rs,$item_rs) = get_reseller_phonebook_rs($c, $value, $type);
    } elsif ($type eq 'contract') {
        ($list_rs,$item_rs) = get_contract_phonebook_rs($c, $value, $type);
    } elsif ($type eq 'subscriber') {
        ($list_rs,$item_rs) = get_subscriber_phonebook_rs($c, $value, $type);
    } else {
        die 'This shouln\'t happen';
    }
    return $list_rs;
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
    } elsif ($c->user->roles eq "admin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::ResellerAPI", $c);
    } elsif ($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::ResellerAPI", $c);
    } elsif ($c->user->roles eq 'subscriber' ||
             $c->user->roles eq 'subscriberadmin') {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::SubscriberAPI", $c);
    }
    return;
}

sub process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    $resource->{customer_id} = $resource->{contract_id};
    return $resource;
}

sub validate_request {
    my($self, $c) = @_;
    my $method = uc($c->request->method);
    if ($method ne 'OPTIONS' && $method ne 'HEAD') {
        my($owner,$type,$parameter,$value) = $self->check_owner_params($c);
        return unless $owner;
    }
    return 1;
}

sub check_owner_params {
    my($self, $c, $params) = @_;
    if ($c->stash->{check_owner_params}) {
        return (@{$c->stash->{check_owner_params}});
    }

    my @allowed_params;
    if ($c->user->roles eq "admin") {
        @allowed_params = qw/reseller_id customer_id subscriber_id/;
    } elsif ($c->user->roles eq "reseller") {
        @allowed_params = qw/reseller_id customer_id subscriber_id/;
    } elsif ($c->user->roles eq 'subscriberadmin') {
        @allowed_params = qw/customer_id subscriber_id/;
    } elsif ($c->user->roles eq 'subscriber') {
        @allowed_params = qw/subscriber_id/;
    }

    $params //= $self->get_info_data($c);

    # Checking for implicit subscriber - no params provided. subscriber_id can be set up here.
    &_check_implicit_subscriber($c, $params);

    my %owner_params =
        map { $_ => $params->{$_} }
            grep { exists $params->{$_} }
                (qw/reseller_id customer_id subscriber_id/);

    if (!grep { exists $owner_params{$_} } @allowed_params) {
        $c->log->error("'".join("' or '", @allowed_params)."' should be specified");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "'".join("' or '", @allowed_params)."' should be specified.");
        return;
    }

    if (scalar keys %owner_params > 1) {
        $c->log->error('Too many owners: '.join(',',keys %owner_params));
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
            sprintf("Only one of either %s should be specified",
                "'".join("' or '", @allowed_params)."'"));
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
        if ($c->user->roles eq "admin" ||
            ($c->user->roles eq "reseller" &&
                $c->user->reseller_id == $value)) {
            $owner = $schema->resultset('resellers')->find($value);
        }
    } elsif ($parameter eq 'customer_id') {
        $type = 'contract';
        if ($c->user->roles eq "admin") {
            $owner = $schema->resultset('contracts')->find($value);
        } elsif ($c->user->roles eq "reseller") {
            $owner = $schema->resultset('contracts')->search_rs({
                'me.id' => $value,
                'contact.reseller_id' => $c->user->reseller_id,
            },{
                join => 'contact',
            })->first;
        } elsif ($c->user->roles eq 'subscriberadmin' &&
                 $c->user->voip_subscriber->contract_id == $value) {
            $owner = $schema->resultset('contracts')->find({ id => $value });
        }
    } elsif ($parameter eq 'subscriber_id') {
        $type = 'subscriber';
        if ($c->user->roles eq "admin") {
            $owner = $schema->resultset('voip_subscribers')->find($value);
        } elsif ($c->user->roles eq "reseller") {
            $owner = $schema->resultset('voip_subscribers')->search_rs({
                'me.id' => $value,
                'contact.reseller_id' => $c->user->reseller_id,
            },{
                join => { 'contract' => 'contact' },
            })->first;
        } elsif (($c->user->roles eq 'subscriberadmin' ||
                  $c->user->roles eq "subscriber") &&
                 $c->user->voip_subscriber->id == $value) {
            $owner = $schema->resultset('voip_subscribers')->find({ id => $value });
        }
    }

    unless ($owner) {
        $c->log->error("Unknown $parameter value '$value'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Unknown $parameter value '$value'"); #$value is an id, so not sensitive.
        return;
    }
    $c->stash->{check_owner_params} = [$owner,$type,$parameter,$value];
    return @{$c->stash->{check_owner_params}};
}

sub get_reseller_phonebook_rs {
    my ($c, $reseller_id, $context) = @_;

    my $list_rs = $c->model('DB')->resultset('resellers')->find({
        id => $reseller_id,
    })->phonebook;
    my $item_rs = $c->model('DB')->resultset('reseller_phonebook');
    return ($list_rs,$item_rs);
}

sub get_contract_phonebook_rs {
    my ($c, $contract_id, $context) = @_;

    my $list_rs = $c->model('DB')->resultset('contracts')->find({
        id => $contract_id,
    })->phonebook;

    my $item_rs = $c->model('DB')->resultset('contract_phonebook');
    return ($list_rs,$item_rs);
}

sub get_subscriber_phonebook_rs {
    my ($c, $subscriber_id) = @_;

    my $list_rs = $c->model('DB')->resultset('voip_subscribers')->find({
        id => $subscriber_id,
    })->phonebook;
    my $item_rs = $c->model('DB')->resultset('subscriber_phonebook');
    return ($list_rs,$item_rs);
}

sub _check_implicit_subscriber {
    my ($c, $params) = @_;

    if (
        (none {defined $params->{$_}} qw/reseller_id customer_id subscriber_id/) &&
        (any {$c->user->roles eq $_} qw/subscriber subscriberadmin/)
    ) {
       $params->{subscriber_id} = $c->user->voip_subscriber->id;
    }
}

1;
# vim: set tabstop=4 expandtab:
