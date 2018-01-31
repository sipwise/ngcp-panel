package NGCP::Panel::Controller::API::TopupCash;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ProfilePackages;
use NGCP::Panel::Utils::Voucher;
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/POST OPTIONS/];
}

use NGCP::Panel::Form;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API/;

sub api_description {
    return 'Defines topup via voucher codes.';
};

sub query_params {
    return [
    ];
}

sub resource_name{
    return 'topupcash';
}

sub dispatch_path{
    return '/api/topupcash/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-topupcash';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});







sub POST :Allow {
    my ($self, $c) = @_;

    my $success = 0;
    my $entities = {};
    my $log_vals = {};
    my $resource = undef;
    my $now = NGCP::Panel::Utils::DateTime::current_local;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        unless($c->user->billing_data) {
            $c->log->error("user does not have billing data rights");
            $self->error($c, HTTP_FORBIDDEN, "Unsufficient rights to create voucher");
            last;
        }
        $resource = $self->get_valid_post_data(
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
        );
        
        last unless NGCP::Panel::Utils::Voucher::check_topup(c => $c,
                    now => $now,
                    subscriber_id => $resource->{subscriber_id},
                    package_id => $resource->{package_id},
                    resource => $resource,
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
                log_vals => $log_vals,
                #old_package => $customer->profile_package,
                amount => $resource->{amount},
                now => $now,
                request_token => $resource->{request_token},
                subscriber => $entities->{subscriber},
            );
        } catch($e) {
            $c->log->error("failed to perform cash topup: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to perform cash topup.");
            last;
        }
        
        $guard->commit;
        $success = 1;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    undef $guard;
    $guard = $c->model('DB')->txn_scope_guard;
    {
        try {
            my $topup_log = NGCP::Panel::Utils::ProfilePackages::create_topup_log_record(
                c => $c,
                is_cash => 1,
                now => $now,
                entities => $entities,
                log_vals => $log_vals,
                resource => $resource,
                is_success => $success
            );
        } catch($e) {
            $c->log->error("failed to create topup log record: $e");
            last;
        }
        $guard->commit;
    }
    return;
}



sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get('NGCP::Panel::Form::Topup::CashAPI', $c);
}

1;

# vim: set tabstop=4 expandtab:
