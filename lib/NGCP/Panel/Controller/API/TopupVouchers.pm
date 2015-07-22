package NGCP::Panel::Controller::API::TopupVouchers;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

use NGCP::Panel::Utils::Voucher;
use NGCP::Panel::Utils::DateTime;

with 'NGCP::Panel::Role::API';

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Defines topup via voucher codes.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
    ]},
);

class_has('resource_name', is => 'ro', default => 'topupvouchers');
class_has('dispatch_path', is => 'ro', default => '/api/topupvouchers/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-topupvouchers');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub POST :Allow {
    my ($self, $c) = @_;

    unless($c->user->billing_data) {
        $c->log->error("user does not have billing data rights");
        $self->error($c, HTTP_FORBIDDEN, "Unsufficient rights to create voucher");
        return;
    }

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }

        my $code = NGCP::Panel::Utils::Voucher::encrypt_code($c, $resource->{code});

        # subscriber_id, voucher_code

        try {
            # TODO: add billing.vouchers.active flag for internal/emergency use

            my $now = NGCP::Panel::Utils::DateTime::current_local;
            my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find($resource->{subscriber_id});
            unless($subscriber) {
                # TODO: error
            }
            my $customer = $subscriber->contract;

            my $voucher = $c->model('DB')->resultset('voip_subscribers')->find({
                code => $code,
                used_by_subscriber_id => undef,
                valid_until => { '<=' => $now },
                reseller_id => $customer->contact->reseller_id, # TODO: make unique key code,reseller_id
            },{
                for => 'update',
            });
            unless($voucher) {
                # TODO: invalid code or already used
            }

            if($voucher->customer_id && $customer->id != $voucher->customer_id) {
                # TODO: error, voucher only to be used by a different customer
            }

            if($voucher->reseller_id != $customer->contact->reseller_id) {
                # TODO: error, voucher only to be used by a different customer
            }

            # TODO: update customer package_id, billing profile mappings etc.

            my $balance = undef; # TODO: get current contract balance
            $balance->update({ cash_balance => $balance->cash_balance + $voucher->amount });


            $voucher->update({
                used_by_subscriber_id => $subscriber->id,
                used_at => $now,
            });
        } catch($e) {
            $c->log->error("failed to create voucher topup: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create voucher topup.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

sub get_form {
    my ($self, $c) = @_;
    # TODO: use correct Form
    if($c->user->roles eq "admin") {
        #return NGCP::Panel::Form::Voucher::AdminAPI->new;
    } elsif($c->user->roles eq "reseller") {
        #return NGCP::Panel::Form::Voucher::ResellerAPI->new;
    }
}

# vim: set tabstop=4 expandtab:
