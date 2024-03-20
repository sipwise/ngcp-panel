package NGCP::Panel::Controller::API::TopupVouchers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Voucher;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ProfilePackages;

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
    return 'topupvouchers';
}

sub dispatch_path{
    return '/api/topupvouchers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-topupvouchers';
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
            $self->error($c, HTTP_FORBIDDEN, "Insufficient rights to create voucher",
                         "user does not have billing data rights");
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
        );

        last unless NGCP::Panel::Utils::Voucher::check_topup(c => $c,
                    now => $now,
                    subscriber_id => $resource->{subscriber_id},
                    plain_code => $resource->{code},
                    resource => $resource,
                    entities => $entities,
                    err_code => sub {
                            my ($err) = @_;
                            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
                        },
                    );
       
        try {
            my $balance = NGCP::Panel::Utils::ProfilePackages::topup_contract_balance(c => $c,
                contract => $entities->{contract},
                voucher => $entities->{voucher},
                log_vals => $log_vals,
                now => $now,
                request_token => $resource->{request_token},
                subscriber => $entities->{subscriber},
            );

            $entities->{voucher}->update({
                used_by_subscriber_id => $resource->{subscriber_id},
                used_at => $now,
            });
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create voucher topup.", $e);
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
                is_cash => 0,
                now => $now,
                entities => $entities,
                log_vals => $log_vals,
                resource => $resource,
                is_success => $success
            );
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create voucher topup.", $e);
            last;
        }
        $guard->commit;
    }
    return;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get('NGCP::Panel::Form::Topup::VoucherAPI', $c);
}

1;

# vim: set tabstop=4 expandtab:
