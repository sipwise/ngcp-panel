package NGCP::Panel::Controller::Network;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form::BillingNetwork::Admin;
use NGCP::Panel::Form::BillingNetwork::Reseller;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::BillingNetworks qw();

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub network_list :Chained('/') :PathPart('network') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $dispatch_to = '_network_resultset_' . $c->user->roles;
    my $network_rs = $self->$dispatch_to($c);

    $c->stash->{network_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        NGCP::Panel::Utils::BillingNetworks::get_datatable_cols($c),
    ]);

    $c->stash(network_rs   => $network_rs,
              template => 'network/list.tt');
}

sub _network_resultset_admin {
    my ($self, $c) = @_;
    return $c->model('DB')->resultset('billing_networks')->search_rs(undef,
        { join => 'billing_network_blocks',
          group_by => 'me.id',
         })->search_rs({
                'me.status' => { '!=' => 'terminated' },
                },
                { '+select' => [ { '' => \[ NGCP::Panel::Utils::BillingNetworks::get_contract_count_stmt() ] , -as => 'contract_cnt' },
                { '' => \[ NGCP::Panel::Utils::BillingNetworks::get_package_count_stmt() ] , -as => 'package_cnt' }, ],
            });
}

sub _network_resultset_reseller {
    my ($self, $c) = @_;

    return $c->model('DB')->resultset('admins')->find(
            { id => $c->user->id, } )
        ->reseller
        ->search_related('billing_networks')->search_rs(undef,
        { join => 'billing_network_blocks',
          group_by => 'me.id',
         })->search_rs({
                'me.status' => { '!=' => 'terminated' },
                },
                { '+select' => [ { '' => \[ NGCP::Panel::Utils::BillingNetworks::get_contract_count_stmt() ] , -as => 'contract_cnt' },
                { '' => \[ NGCP::Panel::Utils::BillingNetworks::get_package_count_stmt() ] , -as => 'package_cnt' }, ],
            });
}

sub root :Chained('network_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('network_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::BillingNetwork::Admin->new;
    } else {
        $form = NGCP::Panel::Form::BillingNetwork::Reseller->new;
    }
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $reseller_id = ($c->user->is_superuser ? $form->values->{reseller}{id} : $c->user->reseller_id);
            $c->model('DB')->schema->txn_do( sub {
                my $bn = $c->model('DB')->resultset('billing_networks')->create({
                    reseller_id => $reseller_id,
                    name => $form->values->{name},
                    description => $form->values->{description},
                });
                for my $block (@{$form->values->{blocks}}) {
                    $bn->create_related("billing_network_blocks", $block);
                }
                delete $c->session->{created_objects}->{reseller};
                $c->session->{created_objects}->{network} = { id => $bn->id };
            });

            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $c->loc('Billing Network successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create billing network.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/network'));
    }

    $c->stash(
        close_target => $c->uri_for,
        create_flag => 1,
        form => $form
    );
}

sub base :Chained('/network/network_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $network_id) = @_;

    unless($network_id && is_int($network_id)) {
        $network_id //= '';
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $network_id },
            desc => $c->loc('Invalid billing network id detected'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->stash->{network_rs}->find($network_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc => $c->loc('Billing network does not exist'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    $c->stash(network        => {$res->get_inflated_columns},
              network_blocks => [ map { { $_->get_inflated_columns }; } $res->billing_network_blocks->all ],
              network_result => $res);
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::BillingNetwork::Reseller->new(ctx => $c);
    my $params = $c->stash->{network};
    $params->{blocks} = $c->stash->{network_blocks};
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    if($posted && $form->validated) {

        try {
            $c->model('DB')->schema->txn_do( sub {

                $c->stash->{'network_result'}->update({
                    name => $form->values->{name},
                    description => $form->values->{description},
                });
                $c->stash->{'network_result'}->billing_network_blocks->delete;
                for my $block (@{$form->values->{blocks}}) {
                    $c->stash->{'network_result'}->create_related("billing_network_blocks", $block);
                }
            });
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Billing network successfully updated'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update billing network'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/network'));

    }

    $c->stash(
        close_target => $c->uri_for,
        edit_flag => 1,
        form => $form
    );
}

sub terminate :Chained('base') :PathPart('terminate') :Args(0) {
    my ($self, $c) = @_;
    my $network = $c->stash->{network_result};

    try {
        #todo: putting the network fetch into a transaction wouldn't help since the count columns a prone to phantom reads...
        unless($network->get_column('contract_cnt') == 0) {
            die(['Cannnot terminate billing network that is still used in profile mappings', "showdetails"]);
        }
        unless($network->get_column('package_cnt') == 0) {
            die(['Cannnot terminate billing network that is still used in profile packages', "showdetails"]);
        }
        $network->update({
            status => 'terminated',
            #terminate_timestamp => NGCP::Panel::Utils::DateTime::current_local,
        });
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $c->stash->{network},
            desc => $c->loc('Billing network successfully terminated'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $c->stash->{network},
            desc  => $c->loc('Failed to terminate billing network'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/network'));
}

sub ajax :Chained('network_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{network_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{network_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub ajax_filter_reseller :Chained('network_list') :PathPart('ajax/filter_reseller') :Args(1) {
    my ($self, $c, $reseller_id) = @_;

    my $resultset = $c->stash->{network_rs}->search({
        'reseller_id' => $reseller_id,
    });
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{network_dt_columns});
    $c->detach( $c->view("JSON") );
}

__PACKAGE__->meta->make_immutable;

1;
