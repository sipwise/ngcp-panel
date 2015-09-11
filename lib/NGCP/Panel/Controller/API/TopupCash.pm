package NGCP::Panel::Controller::API::TopupCash;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ProfilePackages;
use NGCP::Panel::Utils::Voucher;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

use NGCP::Panel::Form::Topup::CashAPI;

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

class_has('resource_name', is => 'ro', default => 'topupcash');
class_has('dispatch_path', is => 'ro', default => '/api/topupcash/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-topupcash');

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

    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
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
            # due to the _id suffix, it would be converted to package.id and subscriber.id in
            # the validation, so exclude them here
            exceptions => [qw/package_id subscriber_id/],
        );
        
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $entities = {};
        last unless NGCP::Panel::Utils::Voucher::check_topup(c => $c,
                    now => $now,
                    subscriber_id => $resource->{subscriber_id},
                    package_id => $resource->{package_id},
                    entities => $entities,
                    err_code => sub {
                        my ($err) = @_;
                        #$c->log->error($err);
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
                        },
                    );

        try {
            my $balance = NGCP::Panel::Utils::ProfilePackages::topup_contract_balance(c => $c,
                contract => $entities->{contract},
                package => $entities->{package},
                #old_package => $customer->profile_package,
                amount => $resource->{amount},
                now => $now,
            );
        } catch($e) {
            $c->log->error("failed to perform cash topup: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to perform cash topup.");
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
    return NGCP::Panel::Form::Topup::CashAPI->new(ctx => $c);
}

# vim: set tabstop=4 expandtab:
