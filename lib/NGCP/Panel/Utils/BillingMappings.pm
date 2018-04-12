package NGCP::Panel::Utils::BillingMappings;
use strict;
use warnings;

use Sipwise::Base;



sub get_contract_rs {

    my %params = @_;
    my ($c,$schema,$include_terminated) = @params{qw/c schema include_terminated/};
    $schema //= $c->model('DB');
    my $rs = $schema->resultset('contracts')->search({
        $include_terminated ? () : ('me.status' => { '!=' => 'terminated' }),
    }, undef);
    return $rs;

}

sub get_customer_rs {
    my %params = @_;
    my ($c,$schema,$include_terminated) = @params{qw/c schema include_terminated/};

    my $rs = get_contract_rs(
        c => $c,
        schema => $schema,
        include_terminated => $include_terminated,
    )->search_rs({
        'product.class' => { -in => [ 'sipaccount', 'pbxaccount' ] },
    },{
        join => 'product',
    });

    if($c->user->roles eq "admin") {
        $rs = $rs->search_rs({
            'contact.reseller_id' => { '-not' => undef },
        },{
            join => 'contact',
        });
    } elsif($c->user->roles eq "reseller") {
        $rs = $rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => 'contact',
        });
    } elsif($c->user->roles eq "subscriberadmin" or $c->user->roles eq "subscriber") {
        $rs = $rs->search({
            'contact.reseller_id' => $c->user->contract->contact->reseller_id,
        },{
            join => 'contact',
        });
    }

    return $rs;
}


sub x {

    #foreach my $billing_mapping$contract->billing_mappings->all)




}


1;
