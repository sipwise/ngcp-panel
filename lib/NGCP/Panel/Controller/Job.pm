package NGCP::Panel::Controller::Job;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
#use NGCP::Panel::Utils::ProfilePackages qw();
#use NGCP::Panel::Utils::Voucher qw();

sub auto :Private {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub job_list :Chained('/') :PathPart('job') :CaptureArgs(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(ccareadmin) :AllowedRole(ccare) {
    my ($self, $c) = @_;

    #my $dispatch_role = $c->user->roles =~ /admin$/ ? 'admin' : 'reseller';
    #my $dispatch_to = '_package_resultset_' . $dispatch_role;
    my $job_rs = 1; #$self->$dispatch_to($c);

    $c->stash->{job_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        #NGCP::Panel::Utils::ProfilePackages::get_datatable_cols($c),
    ]);

    $c->stash(job_rs   => $job_rs,
              template => 'job/list.tt');
}

sub job_list_restricted :Chained('job_list') :PathPart('') :CaptureArgs(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
}

sub root :Chained('job_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('job_list_restricted') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Job::X", $c);
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
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            #$form->values->{reseller_id} = ($c->user->is_superuser ? $form->values->{reseller}{id} : $c->user->reseller_id);
            #delete $form->values->{reseller};
            #foreach(qw/balance_interval timely_duration/){
            #    $form->values->{$_.'_unit'} = $form->values->{$_}{unit} || undef;
            #    $form->values->{$_.'_value'} = $form->values->{$_}{value} || undef;
            #    delete $form->values->{$_};
            #}
            #my @mappings_to_create = ();
            #push(@mappings_to_create,@{delete $form->values->{initial_profiles}});
            #push(@mappings_to_create,@{delete $form->values->{underrun_profiles}});
            #push(@mappings_to_create,@{delete $form->values->{topup_profiles}});
            #$c->model('DB')->schema->txn_do( sub {
            #    my $profile_package = $c->model('DB')->resultset('profile_packages')->create($form->values);
            #    foreach my $mapping (@mappings_to_create) {
            #        $profile_package->profiles->create($mapping);
            #    }
            #    delete $c->session->{created_objects}->{reseller};
            #    $c->session->{created_objects}->{package} = { id => $profile_package->id };
            #});

            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $c->loc('Job successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create job.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/job'));
    }

    $c->stash(
        close_target => $c->uri_for,
        create_flag => 1,
        form => $form
    );
}

sub base :Chained('/job/job_list_restricted') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $job_id) = @_;

    unless($job_id && is_int($job_id)) {
        $job_id //= '';
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $job_id },
            desc => $c->loc('Invalid job id detected'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->stash->{job_rs}->find($job_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc => $c->loc('Job does not exist'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    $c->stash(job        => {$res->get_inflated_columns},
              #initial_profiles => [ map { { $_->get_inflated_columns }; } $res->initial_profiles->all ],
              #underrun_profiles => [ map { { $_->get_inflated_columns }; } $res->underrun_profiles->all ],
              #topup_profiles => [ map { { $_->get_inflated_columns }; } $res->topup_profiles->all ],
              package_result => $res);
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Job::X", $c);
    my $params = $c->stash->{job};
    #$params->{initial_profiles} = $c->stash->{initial_profiles};
    #$params->{underrun_profiles} = $c->stash->{underrun_profiles};
    #$params->{topup_profiles} = $c->stash->{topup_profiles};
    #$params->{reseller}{id} = delete $params->{reseller_id};
    #foreach(qw/balance_interval timely_duration/){
    #    $params->{$_} = { unit => delete $params->{$_.'_unit'}, value => delete $params->{$_.'_value'} };
    #}
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
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            #foreach(qw/balance_interval timely_duration/){
            #    $form->values->{$_.'_unit'} = $form->values->{$_}{unit} || undef;
            #    $form->values->{$_.'_value'} = $form->values->{$_}{value} || undef;
            #    delete $form->values->{$_};
            #}
            #my @mappings_to_create = ();
            #push(@mappings_to_create,@{delete $form->values->{initial_profiles}});
            #push(@mappings_to_create,@{delete $form->values->{underrun_profiles}});
            #push(@mappings_to_create,@{delete $form->values->{topup_profiles}});
            #$c->model('DB')->schema->txn_do( sub {
            #
            #    my $profile_package = $c->stash->{'package_result'}->update($form->values);
            #    $profile_package->profiles->delete;
            #    foreach my $mapping (@mappings_to_create) {
            #        $profile_package->profiles->create($mapping);
            #    }
            #});
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Job successfully updated'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update job'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/job'));

    }

    $c->stash(
        close_target => $c->uri_for,
        edit_flag => 1,
        form => $form
    );
}

sub delete_job :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    my $job = $c->stash->{job_result};

    try {
        ##todo: putting the package fetch into a transaction wouldn't help since the count columns a prone to phantom reads...
        #unless($package->get_column('contract_cnt') == 0) {
        #    die(['Cannnot delete profile package that is still assigned to contracts', "showdetails"]);
        #}
        #unless($package->get_column('voucher_cnt') == 0) {
        #    die(['Cannnot delete profile package that is assigned to vouchers', "showdetails"]);
        #}

        $job->delete;
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $c->stash->{package},
            desc => $c->loc('Job successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $c->stash->{package},
            desc  => $c->loc('Failed to delete job'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/job'));
}

sub ajax :Chained('job_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{job_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{job_dt_columns});
    $c->detach( $c->view("JSON") );
}

1;
