package NGCP::Panel::Controller::API::Invoices;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Invoices/;

__PACKAGE__->set_config();

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines invoices generated by the system.';
};

sub query_params {
    return [
        {
            param => 'period_start_ge',
            description => 'Filter for invoices newer or equal to the given date (YYYY-MM-DDThh:mm:ss)',
            query => {
                first => sub {
                    my $q = shift;
                    { 'period_start' => { '>=' => $q }};
                },
                second => sub { },
            },
        },
        {
            param => 'period_end_le',
            description => 'Filter for invoices older or equal to the given date (YYYY-MM-DDThh:mm:ss)',
            query => {
                first => sub {
                    my $q = shift;
                    { 'period_end' => { '<=' => $q }};
                },
                second => sub { },
            },
        },
        {
            param => 'reseller_id',
            description => 'Filter for invoices of customers belonging to a certain reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { 'contact.reseller_id' => $q };
                },
                second => sub {
                    return { join => { contract => 'contact' } };
                },
            },
        },
        {
            param => 'customer_id',
            description => 'Filter for invoices belonging to a specific customer',
            query => {
                first => sub {
                    my $q = shift;
                    { contract_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'serial',
            description => 'Filter for invoices matching a serial',
            query_type  => 'wildcard',
        },
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $contract_id = $form->values->{customer_id};
    my $tmpl_id = $form->values->{template_id};
    my $period_start = $form->values->{period_start};
    my $period_end = $form->values->{period_end};
    my $period = $form->values->{period};
    my $item;
    try {
        my ($contract,$tmpl,$stime,$etime,$invoice_data) = NGCP::Panel::Utils::Invoice::check_invoice_data($c, {
            contract_id  => $contract_id,
            tmpl_id      => $tmpl_id,
            period_start => $period_start,
            period_end   => $period_end,
            period       => $period,
        });
        $item = NGCP::Panel::Utils::Invoice::create_invoice($c,{
            contract     => $contract,
            stime        => $stime,
            etime        => $etime,
            tmpl         => $tmpl,
            invoice_data => $invoice_data,
        });
    } catch($e) {
        my $http_code = 'HASH' eq ref $e && $e->{httpcode} ? $e->{httpcode} : HTTP_INTERNAL_SERVER_ERROR;
        $self->error($c, $http_code, $e);
        return;
    }
    return $item;
}

1;

# vim: set tabstop=4 expandtab:
