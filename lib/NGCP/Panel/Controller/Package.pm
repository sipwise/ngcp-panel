package NGCP::Panel::Controller::Package;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form::ProfilePackage::Admin;
use NGCP::Panel::Form::ProfilePackage::Reseller;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::Voucher qw();

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub package_list :Chained('/') :PathPart('package') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $dispatch_to = '_package_resultset_' . $c->user->roles;
    my $package_rs = $self->$dispatch_to($c);

    $c->stash->{package_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        NGCP::Panel::Utils::ProfilePackages::get_datatable_cols($c),
    ]);

    $c->stash(package_rs   => $package_rs,
              template => 'package/list.tt');
}

sub _package_resultset_admin {
    my ($self, $c) = @_;
    return $c->model('DB')->resultset('profile_packages')->search_rs(
        undef,
        { group_by => 'me.id',
         })->search_rs(
            undef,
            { '+select' => [ { '' => \[ NGCP::Panel::Utils::ProfilePackages::get_contract_count_stmt() ] , -as => 'contract_cnt' },
                             { '' => \[ NGCP::Panel::Utils::ProfilePackages::get_voucher_count_stmt() ] , -as => 'voucher_cnt' },
                             ],
            });
}

sub _package_resultset_reseller {
    my ($self, $c) = @_;

    return $c->model('DB')->resultset('admins')->find(
            { id => $c->user->id, } )
        ->reseller
        ->search_related('profile_packages')->search_rs(
        undef,
        { group_by => 'me.id',
         })->search_rs(
            undef,
            { '+select' => [ { '' => \[ NGCP::Panel::Utils::ProfilePackages::get_contract_count_stmt() ] , -as => 'contract_cnt' },
                             { '' => \[ NGCP::Panel::Utils::ProfilePackages::get_voucher_count_stmt() ] , -as => 'voucher_cnt' },
                             ],
            });
}

sub root :Chained('package_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('package_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::ProfilePackage::Admin->new(ctx => $c);
    } else {
        $form = NGCP::Panel::Form::ProfilePackage::Reseller->new(ctx => $c);
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
            $form->values->{reseller_id} = ($c->user->is_superuser ? $form->values->{reseller}{id} : $c->user->reseller_id);
            delete $form->values->{reseller};
            foreach(qw/balance_interval timely_duration/){
                $form->values->{$_.'_unit'} = $form->values->{$_}{unit} || undef;
                $form->values->{$_.'_value'} = $form->values->{$_}{value} || undef;
                delete $form->values->{$_};
            }
            my @mappings_to_create = ();
            push(@mappings_to_create,@{delete $form->values->{initial_profiles}});
            push(@mappings_to_create,@{delete $form->values->{underrun_profiles}});
            push(@mappings_to_create,@{delete $form->values->{topup_profiles}});
            $c->model('DB')->schema->txn_do( sub {
                my $profile_package = $c->model('DB')->resultset('profile_packages')->create($form->values);
                foreach my $mapping (@mappings_to_create) {
                    $profile_package->profiles->create($mapping);
                }
                delete $c->session->{created_objects}->{reseller};
                $c->session->{created_objects}->{package} = { id => $profile_package->id };
            });

            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $c->loc('Profile package successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create profile package.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/package'));
    }

    $c->stash(
        close_target => $c->uri_for,
        create_flag => 1,
        form => $form
    );
}

sub base :Chained('/package/package_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $package_id) = @_;

    unless($package_id && is_int($package_id)) {
        $package_id //= '';
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $package_id },
            desc => $c->loc('Invalid package id detected'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->stash->{package_rs}->find($package_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc => $c->loc('Profile package does not exist'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    $c->stash(package        => {$res->get_inflated_columns},
              initial_profiles => [ map { { $_->get_inflated_columns }; } $res->initial_profiles->all ],
              underrun_profiles => [ map { { $_->get_inflated_columns }; } $res->underrun_profiles->all ],
              topup_profiles => [ map { { $_->get_inflated_columns }; } $res->topup_profiles->all ],
              package_result => $res);
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::ProfilePackage::Reseller->new(ctx => $c);
    my $params = $c->stash->{package};
    $params->{initial_profiles} = $c->stash->{initial_profiles};
    $params->{underrun_profiles} = $c->stash->{underrun_profiles};
    $params->{topup_profiles} = $c->stash->{topup_profiles};
    $params->{reseller}{id} = delete $params->{reseller_id};
    foreach(qw/balance_interval timely_duration/){
        $params->{$_} = { unit => delete $params->{$_.'_unit'}, value => delete $params->{$_.'_value'} };
    }
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    #remove submitid
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
            foreach(qw/balance_interval timely_duration/){
                $form->values->{$_.'_unit'} = $form->values->{$_}{unit} || undef;
                $form->values->{$_.'_value'} = $form->values->{$_}{value} || undef;
                delete $form->values->{$_};
            }
            my @mappings_to_create = ();
            push(@mappings_to_create,@{delete $form->values->{initial_profiles}});
            push(@mappings_to_create,@{delete $form->values->{underrun_profiles}});
            push(@mappings_to_create,@{delete $form->values->{topup_profiles}});
            $c->model('DB')->schema->txn_do( sub {

                my $profile_package = $c->stash->{'package_result'}->update($form->values);
                $profile_package->profiles->delete;
                foreach my $mapping (@mappings_to_create) {
                    $profile_package->profiles->create($mapping);
                }
            });
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Profile package successfully updated'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update profile package'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/package'));

    }

    $c->stash(
        close_target => $c->uri_for,
        edit_flag => 1,
        form => $form
    );
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    my $package = $c->stash->{package_result};

    try {
        #todo: putting the package fetch into a transaction wouldn't help since the count columns a prone to phantom reads...
        unless($package->get_column('contract_cnt') == 0) {
            die(['Cannnot delete profile package that is still assigned to contracts', "showdetails"]);
        }
        unless($package->get_column('voucher_cnt') == 0) {
            die(['Cannnot delete profile package that is assigned to vouchers', "showdetails"]);
        }

        $package->delete;
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $c->stash->{package},
            desc => $c->loc('Profile package successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $c->stash->{package},
            desc  => $c->loc('Failed to delete profile package'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/package'));
}

sub ajax :Chained('package_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{package_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{package_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub ajax_filter_reseller :Chained('package_list') :PathPart('ajax/filter_reseller') :Args(1) {
    my ($self, $c, $reseller_id) = @_;

    my $resultset = $c->stash->{package_rs}->search({
        'me.reseller_id' => $reseller_id,
    });
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{package_dt_columns});
    $c->detach( $c->view("JSON") );
}


sub details_base :Chained('/') :PathPart('package') :CaptureArgs(1) {
    my ($self, $c, $package_id) = @_;

    my $dispatch_to = '_package_resultset_' . $c->user->roles;
    my $package_rs = $self->$dispatch_to($c);

    unless($package_id && is_int($package_id)) {
        $package_id //= '';
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $package_id },
            desc => $c->loc('Invalid package id detected'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $package_rs->find($package_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc => $c->loc('Profile package does not exist'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    $c->stash->{profile_set_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        #{ name => 'id', search => 1, title => $c->loc('#') },
        { name => 'billing_profile.name', search => 1, title => $c->loc('Billing Profile') },
        { name => 'billing_network.name', search => 1, title => $c->loc('Billing Network') },
    ]);
    $c->stash->{customer_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        NGCP::Panel::Utils::ProfilePackages::get_customer_datatable_cols($c)
    ]);
    $c->stash->{voucher_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        NGCP::Panel::Utils::Voucher::get_datatable_cols($c,1)
    ]);

    $c->stash(package_result => $res);
}

sub details :Chained('details_base') :PathPart('details') :Args(0) {
    my ($self, $c) = @_;
    $c->stash(template => 'package/details.tt');
}

sub details_ajax :Chained('details_base') :PathPart('ajax') :CaptureArgs(0)  {
    my ($self, $c) = @_;

}

sub ajax_initial_profiles :Chained('details_ajax') :PathPart('initial_profiles') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{package_result}->initial_profiles;
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{profile_set_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub ajax_topup_profiles :Chained('details_ajax') :PathPart('topup_profiles') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{package_result}->topup_profiles;
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{profile_set_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub ajax_underrun_profiles :Chained('details_ajax') :PathPart('underrun_profiles') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{package_result}->underrun_profiles;
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{profile_set_dt_columns});
    $c->detach( $c->view("JSON") );
}

__PACKAGE__->meta->make_immutable;

1;
