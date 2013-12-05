package NGCP::Panel::Role::API::Contracts;
use Moose::Role;
use Sipwise::Base;

use boolean qw(true);
use Try::Tiny;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Form::Contract::PeeringReseller qw();

sub hal_from_contract {
    my ($self, $c, $contract, $form) = @_;

    my $billing_mapping = $contract->billing_mappings->find($contract->get_column('bmid'));
    my $billing_profile_id = $billing_mapping->billing_profile->id;
    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);
    my $contract_balance = $contract->contract_balances
        ->find({
            start => { '>=' => $stime },
            end => { '<' => $etime },
            });
    unless($contract_balance) {
        try {
            NGCP::Panel::Utils::Contract::create_contract_balance(
                c => $c,
                profile => $billing_mapping->billing_profile,
                contract => $contract,
            );
        } catch {
            $self->log->error("Failed to create current contract balance for contract id '".$contract->id."': $_");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
        }
        $contract_balance = $contract->contract_balances->find({
            start => { '>=' => $stime },
            end => { '<' => $etime },
        });
    }

    my %resource = $contract->get_inflated_columns;

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf('/%s', $c->request->path)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("/%s%d", $c->request->path, $contract->id)),
            Data::HAL::Link->new(relation => 'ngcp:systemcontacts', href => sprintf("/api/systemcontacts/%d", $contract->contact->id)),
            Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $billing_profile_id)),
            Data::HAL::Link->new(relation => 'ngcp:contractbalances', href => sprintf("/api/contractbalances/%d", $contract_balance->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= NGCP::Panel::Form::Contract::PeeringReseller->new;
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    $resource{id} = int($contract->id);
    $resource{type} = $billing_mapping->product->class;
    $resource{billing_profile_id} = int($billing_profile_id);
    $hal->resource({%resource});
    return $hal;
}

sub contract_by_id {
    my ($self, $c, $id) = @_;

    # we only return system contracts, that is, those with contacts without
    # reseller
    my $contracts = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'),
    );
    $contracts = $contracts->search({
        'contact.reseller_id' => undef
    },{
        join => 'contact',
        '+select' => 'billing_mappings.id',
        '+as' => 'bmid',
    });

    return $contracts->find({'me.id' => $id});
}

1;
# vim: set tabstop=4 expandtab:
