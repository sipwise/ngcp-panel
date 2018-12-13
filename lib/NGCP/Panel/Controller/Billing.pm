package NGCP::Panel::Controller::Billing;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;
use DateTime::Format::ISO8601;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Datatables;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Billing;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub profile_list :Chained('/') :PathPart('billing') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    my $dispatch_to = '_profile_resultset_' . $c->user->roles;
    my $profiles_rs = $self->$dispatch_to($c);
    $c->stash(profiles_rs => $profiles_rs);
    $c->stash->{profile_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", "search" => 1, "title" => $c->loc("#") },
        { name => "name", "search" => 1, "title" => $c->loc("Name") },
        { name => "reseller.name", "search" => 1, "title" => $c->loc("Reseller") },
        #{ name => "v_count_used", "search" => 0, "title" => $c->loc("Used") },
        NGCP::Panel::Utils::Billing::get_datatable_cols($c),
    ]);

    $c->stash(template => 'billing/list.tt');
}

sub _profile_resultset_admin {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('billing_profiles')->search({
            'me.status' => { '!=' => 'terminated' },
            },
            { '+select' => [ { '' => \[ NGCP::Panel::Utils::Billing::get_contract_count_stmt() ] , -as => 'contract_cnt' },
                           { '' => \[ NGCP::Panel::Utils::Billing::get_package_count_stmt() ] , -as => 'package_cnt' }, ],
            });
    return $rs;
}

sub _profile_resultset_reseller {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('admins')
        ->find($c->user->id)->reseller->billing_profiles
        ->search_rs({
            'me.status' => { '!=' => 'terminated' },
            },
            { '+select' => [ { '' => \[ NGCP::Panel::Utils::Billing::get_contract_count_stmt() ] , -as => 'contract_cnt' },
                           { '' => \[ NGCP::Panel::Utils::Billing::get_package_count_stmt() ] , -as => 'package_cnt' }, ],
            });
    return $rs;
}

sub root :Chained('profile_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('profile_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{profiles_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{profile_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub ajax_filter_reseller :Chained('profile_list') :PathPart('ajax/filter_reseller') :Args(1) {
    my ($self, $c, $reseller_id) = @_;

    my $resultset = $c->stash->{profiles_rs}->search({
        'me.reseller_id' => $reseller_id,
    });
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{profile_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub base :Chained('profile_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $profile_id) = @_;

    unless($profile_id && is_int($profile_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $profile_id },
            desc  => $c->loc('Invalid profile id detected!'),
        );
        $c->response->redirect($c->uri_for());
        return;
    }

    my $res = $c->stash->{profiles_rs}->find($profile_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $profile_id },
            desc  => $c->loc('Billing Profile does not exist!'),
        );
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash(profile => {$res->get_inflated_columns});
    $c->stash(profile_result => $res);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c ) = @_;
    $c->forward('process_edit', [0] );
}
sub process_edit :Private {
    my ($self, $c, $duplicate) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = $c->stash->{profile};
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    if( $duplicate ) {
        NGCP::Panel::Utils::Billing::get_billing_profile_uniq_params( params => $params );
        if($c->user->is_superuser) {
            $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingProfile::Admin", $c);
        } else {
            $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingProfile::Reseller", $c);
        }
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingProfile::Reseller", $c);
    }
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
            if (exists $form->values->{reseller}) {
                if($c->user->is_superuser) {
                    $form->values->{reseller_id} = $form->values->{reseller}{id};
                } else {
                    $form->values->{reseller_id} = $c->user->reseller_id;
                }
                delete $form->values->{reseller};
            }
            $form->values->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
            my $old_prepaid = $c->stash->{profile_result}->prepaid;

            my $schema = $c->model('DB');
            $schema->txn_do(sub {

                $c->stash->{profile_result}->update($form->values);

                NGCP::Panel::Utils::Billing::switch_prepaid(c => $c,
                    profile_id => $c->stash->{profile_result}->id,
                    old_prepaid => $old_prepaid,
                    new_prepaid => $c->stash->{profile_result}->prepaid,
                );

            });

            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Billing profile successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update billing profile'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/billing'));
    }
    $c->stash( 'duplicate_flag' => 1 ) if $duplicate;
    $c->stash( 'edit_flag'      => 1 );
    $c->stash( 'form'           => $form );
}

sub create :Chained('profile_list') :PathPart('create') :Args(0) {
    my ($self, $c, $no_reseller) = @_;
    $c->forward('process_create', [$no_reseller, 0 ]);
}
sub duplicate :Chained('base') :PathPart('duplicate') {
    my ($self, $c, $no_reseller) = @_;
    my $posted = ($c->request->method eq 'POST');
    if(!$posted){
        $c->forward('process_edit', [1] );
    }else{
        $c->forward('process_create', [ $no_reseller, 1 ] );
    }
}
sub process_create :Private {
    my ($self, $c, $no_reseller, $duplicate ) = @_;

    my $schema = $c->model('DB');
    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->is_superuser && !$no_reseller) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingProfile::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingProfile::Reseller", $c);
    }
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
            if($c->user->is_superuser && $no_reseller) {
                $form->values->{reseller_id} = $c->user->reseller_id;
            } elsif($c->user->is_superuser) {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
            } else {
                $form->values->{reseller_id} = $c->user->reseller_id;
            }
            $form->values->{create_timestamp} = $form->values->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
            delete $form->values->{reseller};
            delete $form->values->{id} if $duplicate;
            my $profile = $c->model('DB')->resultset('billing_profiles')->create($form->values);

            if( $duplicate ) {

                NGCP::Panel::Utils::Billing::clone_billing_profile_tackles(
                    c           => $c,
                    profile_old => $c->stash->{'profile_result'},
                    profile_new => $profile,
                    #profile_new => $c->stash->{profiles_rs}->find(
                    #    $c->session->{created_objects}->{billing_profile}->{id},
                    #),
                    schema      => $schema,
                );
            }

            $c->session->{created_objects}->{billing_profile} = { id => $profile->id };
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Billing profile successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create billing profile'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/billing'));
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub create_without_reseller :Chained('profile_list') :PathPart('create/noreseller') :Args(0) {
    my ($self, $c) = @_;

    $self->create($c, 1);
}

sub terminate :Chained('base') :PathPart('terminate') :Args(0) {
    my ($self, $c) = @_;
    my $profile = $c->stash->{profile_result};

    if ($profile->id == 1) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc => $c->loc('Cannot terminate default billing profile with the id 1'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/billing'));
    }

    try {
        #todo: putting the profile fetch into a transaction wouldn't help since the count columns a prone to phantom reads...
        unless($profile->get_column('contract_cnt') == 0) {
            die(['Cannnot terminate billing profile that is still used in profile mappings', "showdetails"]);
        }
        unless($profile->get_column('package_cnt') == 0) {
            die(['Cannnot terminate billing profile that is still used in profile packages', "showdetails"]);
        }
        $profile->update({
            status => 'terminated',
            terminate_timestamp => NGCP::Panel::Utils::DateTime::current_local,
        });
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $c->stash->{profile},
            desc => $c->loc('Billing profile successfully terminated'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $c->stash->{profile},
            desc  => $c->loc('Failed to terminate billing profile'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/billing'));
}

sub fees_list :Chained('base') :PathPart('fees') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash->{fee_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'source', search => 1, title => $c->loc('Source Pattern') },
        { name => 'destination', search => 1, title => $c->loc('Destination Pattern') },
        { name => 'match_mode', search => 0, title => $c->loc('Match Mode'),
          custom_renderer => 'function ( data, type, full ) {'.
            'if(full.match_mode == "regex_longest_pattern"){return "' . $c->loc('Regular expression - longest pattern') . '";}'.
            'else if(full.match_mode == "regex_longest_match"){return "' . $c->loc('Regular expression - longest match') . '";}'.
            'else if(full.match_mode == "prefix"){return "' . $c->loc('Prefix string') . '";}'.
            'else if(full.match_mode == "exact_destination"){return "' . $c->loc('Exact string (destination)') . '";}'.
          '}',
         },
        { name => 'direction', search => 1, title => $c->loc('Direction') },
        { name => 'billing_zone.detail', search => 1, title => $c->loc('Billing Zone') },
    ]);
    $c->stash(template => 'billing/fees.tt');
}

sub fees :Chained('fees_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;

}

sub fees_base :Chained('fees_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $fee_id) = @_;

    unless($fee_id && is_int($fee_id)) {
        $fee_id //= '';
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => $c->stash->{profile},
            log  => $fee_id,
            desc => $c->loc('Invalid billing fee id detected!'),
        );
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }

    my $res = $c->stash->{'profile_result'}->billing_fees
        ->search(undef, {join => 'billing_zone',})
        ->find($fee_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => $c->stash->{profile},
            log  => $fee_id,
            desc => $c->loc('Billing Fee does not exist!'),
        );
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }
    $c->stash(fee => {$res->get_columns}); #get_columns should not be used
    $c->stash->{fee}->{'billing_zone_id'} = $res->billing_zone->id
        if (defined $res->billing_zone);
    $c->stash(fee_result => $res);
}

sub fees_ajax :Chained('fees_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{'profile_result'}->billing_fees;
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{fee_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub fees_create :Chained('fees_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    my $profile_id = $c->stash->{profile}->{id};
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingFee", $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $form,
        fields => {'billing_zone.create' => $c->uri_for("$profile_id/zones/create")},
        back_uri => $c->req->uri,
    );
    if($form->validated) {
        $form->values->{source} ||= '.';
        $form->values->{match_mode} ||= 'regex_longest_pattern';
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            NGCP::Panel::Utils::Billing::insert_unique_billing_fees(
                c => $c,
                schema => $schema,
                profile => $c->stash->{'profile_result'},
                fees => [$form->values],
                return_created => 1,
            );
        });
        delete $c->session->{created_objects}->{billing_zone};
        NGCP::Panel::Utils::Message::info(
            c => $c,
            desc => $c->loc('Billing Fee successfully created!'),
        );
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub fees_upload :Chained('fees_list') :PathPart('upload') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingFeeUpload", $c);
    my $upload = $c->req->upload('upload_fees');
    my $posted = $c->req->method eq 'POST';
    my @params = ( upload_fees => $posted ? $upload : undef, );
    $form->process(
        posted => $posted,
        params => { @params },
        action => $c->uri_for_action('/billing/fees_upload', $c->req->captures),
    );
    if($form->validated) {

        # TODO: check by formhandler?
        unless($upload) {
            NGCP::Panel::Utils::Message::error(
                c    => $c,
                desc => $c->loc('No Billing Fee file specified!'),
            );
            $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
            return;
        }
        if ($c->req->params->{purge_existing}) {
            $c->stash->{'profile_result'}->billing_fees_raw->delete;
            $c->stash->{'profile_result'}->billing_fees->delete;
        }
        my $data = $upload->slurp;
        my($fees, $fails, $text_success);
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                ( $fees, $fails, $text_success ) = NGCP::Panel::Utils::Billing::process_billing_fees(
                    c       => $c,
                    data    => \$data,
                    profile => $c->stash->{'profile_result'},
                    schema  => $schema,
                );
            });

            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $$text_success,
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to upload Billing Fees'),
            );
        }

        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub fees_download :Chained('fees_list') :PathPart('download') :Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->model('DB');
    my $data = NGCP::Panel::Utils::Billing::combine_billing_fees(
        c       => $c,
        profile => $c->stash->{'profile_result'},
        schema  => $schema,
    );
    $c->response->header ('Content-Disposition' => 'attachment; filename="billing_fees_'.$c->stash->{profile}->{id}.'.txt"');
    $c->response->content_type('text/csv');
    $c->response->body($$data);
    return;
}

sub fees_edit :Chained('fees_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $profile_id = $c->stash->{profile}->{id};
    my $posted = ($c->request->method eq 'POST');
    my $params = $c->stash->{fee};
    $params->{billing_zone}{id} = delete $params->{billing_zone_id};
    $params = merge($params, $c->session->{created_objects});
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingFee", $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $form,
        fields => {'billing_zone.create' => $c->uri_for("$profile_id/zones/create")},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        $form->values->{source} ||= '.';
        $form->values->{match_mode} ||= 'regex_longest_pattern';
        $form->values->{billing_zone_id} = $form->values->{billing_zone}{id};
        delete $form->values->{billing_zone};
        $c->stash->{'fee_result'}
            ->update($form->values);
        delete $c->session->{created_objects}->{billing_zone};
        NGCP::Panel::Utils::Message::info(
            c => $c,
            desc => $c->loc('Billing fee successfully changed!'),
        );
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }

    $c->stash(edit_fee_flag => 1);
    $c->stash(form => $form);
}

sub fees_delete :Chained('fees_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    unless ( defined($c->stash->{'fee_result'}) ) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => $c->stash->{profile},
            desc => $c->loc('Billing fee not found!'),
        );
        return;
    }
    $c->stash->{'fee_result'}->delete;

    NGCP::Panel::Utils::Message::info(
        c => $c,
        data => $c->stash->{profile},
        desc => $c->loc('Billing fee successfully deleted!'),
    );
    $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
}

sub zones_list :Chained('base') :PathPart('zones') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash->{zone_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'zone', search => 1, title => $c->loc('Zone') },
        { name => 'detail', search => 1, title => $c->loc('Zone Details') },
    ]);

    $c->stash( zones_root_uri =>
        $c->uri_for_action('/billing/zones', [$c->req->captures->[0]])
    );

    $c->stash(template => 'billing/zones.tt');
}

sub zones_ajax :Chained('zones_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{'profile_result'}->billing_zones;
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{zone_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub zones_create :Chained('zones_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingZone", $c);
    my $posted = ($c->request->method eq 'POST');
    $form->process(
        posted => $posted,
        params => $c->request->params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $zone = $c->stash->{'profile_result'}->billing_zones->create($form->values);
            $c->session->{created_objects}->{billing_zone} = { id => $zone->id };
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $c->loc('Billing Zone successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create billing zone'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{zones_root_uri});
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub zones :Chained('zones_list') :PathPart('') :Args(0) {
}

sub zones_base :Chained('zones_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $zone_id) = @_;

    unless($zone_id && is_int($zone_id)) {
        $zone_id //= '';
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => $c->stash->{profile},
            log  => $zone_id,
            desc => $c->loc('Invalid billing zone id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{zones_root_uri});
    }

    my $res = $c->stash->{'profile_result'}->billing_zones
        ->find($zone_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => $c->stash->{profile},
            log  => $zone_id,
            desc => $c->loc('Billing zone does not exist!'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{zones_root_uri});
    }
    $c->stash(zone_result => $res);
}

sub zones_delete :Chained('zones_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    my $zone_info = { $c->stash->{zone_result}->get_inflated_columns };
    try {
        $c->stash->{zone_result}->billing_fees->delete_all;
        $c->stash->{zone_result}->delete;
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $zone_info,
            desc => $c->loc('Billing zone successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $zone_info,
            desc  => $c->loc('Failed to delete billing zone'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{zones_root_uri});
}

sub peaktimes_list :Chained('base') :PathPart('peaktimes') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $c->stash(peaktimes_root_uri =>
        $c->uri_for_action('/billing/peaktimes', [$c->req->captures->[0]])
    );

    my $rs = $c->stash->{profile_result}->billing_peaktime_weekdays;
    $rs = $rs->search(undef, {order_by => 'start'});

    $c->stash->{special_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'start', search => 1, title => $c->loc('Start Date') },
        { name => 'end', search => 1, title => $c->loc('End Date') },
    ]);

    $c->stash(weekdays_result => $rs);
    $c->stash(template => 'billing/peaktimes.tt');
}

sub peaktimes :Chained('peaktimes_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    $self->load_weekdays($c);
}

sub peaktime_weekdays_base :Chained('peaktimes_list') :PathPart('weekday') :CaptureArgs(1) {
    my ($self, $c, $weekday_id) = @_;
    unless (defined $weekday_id && $weekday_id >= 0 && $weekday_id <= 6) {
        $weekday_id //= '';
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => $c->stash->{profile},
            log  => $weekday_id,
            desc => $c->loc('This weekday does not exist'),
        );
        $c->response->redirect($c->uri_for_action(
            "/billing/peaktimes", [$c->req->captures->[0]],
        ));
    }
    $c->stash(weekday_id => $weekday_id);
}

sub peaktime_weekdays_edit :Chained('peaktime_weekdays_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingPeaktimeWeekdays", $c);
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
    );
    if($form->validated) {
        $form->values->{weekday} = $c->stash->{weekday_id};
        $form->values->{start} = '00:00:00' unless($form->values->{start});
        $form->values->{end} = '23:59:59' unless($form->values->{end});
        $c->stash->{'weekdays_result'}
            ->create($form->values);
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => { %{$c->request->params},
                      billing_profile_id => $c->stash->{profile}{id}, },
            desc => $c->loc('Timerange has been successfully created'),
        );
    }

    my $delete_param = $c->request->params->{delete};
    if($delete_param) {
        my $rs = $c->stash->{weekdays_result}
            ->find($delete_param);
        unless ($rs) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                desc => $c->loc('The timerange you wanted to delete does not exist'),
            );
            $c->response->redirect($c->uri_for_action(
                "/billing/peaktimes", [$c->req->captures->[0]],
            ));
            return;
        }
        $rs->delete();
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => { $rs->get_inflated_columns },
            desc => $c->loc('Timerange has been successfully deleted'),
        );
    }

    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingPeaktimeWeekdays", $c)
        unless $form->has_errors;

    $self->load_weekdays($c);
    $c->stash(weekday => $c->stash->{weekdays}->[$c->stash->{weekday_id}]);
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub load_weekdays {
    my ($self, $c) = @_;

    my @WEEKDAYS = @{NGCP::Panel::Utils::DateTime::get_weekday_names($c)};

    my @weekdays;
    for(0 .. 6) {
        $weekdays[$_] = {
            name => $WEEKDAYS[$_],
            ranges => [],
            edit_link => $c->uri_for_action("/billing/peaktime_weekdays_edit",
                [$c->req->captures->[0], $_]),
        };
    }

    foreach my $range ($c->stash->{weekdays_result}->all) {
        push @{ $weekdays[$range->weekday]->{ranges} }, {
            start => $range->start,
            end => $range->end,
            id => $range->id,
        }
    }

    $c->stash(weekdays => \@weekdays);
}

sub peaktime_specials_ajax :Chained('peaktimes_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{'profile_result'}->billing_peaktime_specials;
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{special_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub peaktime_specials_base :Chained('peaktimes_list') :PathPart('date') :CaptureArgs(1) {
    my ($self, $c, $special_id) = @_;

    unless($special_id && is_int($special_id)) {
        $special_id //= '';
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc => $c->loc('Invalid peaktime date id detected!'),
        );
        $c->response->redirect($c->stash->{peaktimes_root_uri});
        return;
    }

    my $res = $c->stash->{'profile_result'}->billing_peaktime_specials
        ->find($special_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => $c->stash->{profile},
            log  => $special_id,
            desc => $c->loc('Peaktime date does not exist!'),
        );
        $c->response->redirect($c->stash->{peaktimes_root_uri});
        return;
    }
    $self->load_weekdays($c);
    $c->stash(special_result => $res);
}

sub peaktime_specials_edit :Chained('peaktime_specials_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $data_res = $c->stash->{special_result};
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingPeaktimeSpecial", $c);
    my $params = { $data_res->get_inflated_columns };
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
            $c->stash->{special_result}->update($form->values);
            NGCP::Panel::Utils::Message::info(
                c => $c,
                data => { %{$c->request->params},
                          billing_profile_id => $c->stash->{profile}{id}, },
                desc => $c->loc('Special offpeak entry successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                data => { %{$c->request->params},
                          billing_profile_id => $c->stash->{profile}{id}, },
                desc  => $c->loc('Failed to update special offpeak entry'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{peaktimes_root_uri});
    }

    $c->stash(peaktimes_special_editflag => 1);
    $c->stash(peaktimes_special_form => $form);
}

sub peaktime_specials_delete :Chained('peaktime_specials_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    my $special_result_info = { $c->stash->{special_result}->get_inflated_columns };
    try {
        $c->stash->{special_result}->delete;
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $special_result_info,
            desc => $c->loc('Special offpeak entry successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data => $special_result_info,
            desc  => $c->loc('Failed to delete special offpeak entry'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{peaktimes_root_uri});
}

sub peaktime_specials_create :Chained('peaktimes_list') :PathPart('date/create') :Args(0) {
    my ($self, $c) = @_;
    $self->load_weekdays($c);

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::BillingPeaktimeSpecial", $c);
    my $params = {};
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
    if($form->validated) {
        try {
            $c->stash->{'profile_result'}->billing_peaktime_specials
                ->create($form->values);
            NGCP::Panel::Utils::Message::info(
                c => $c,
                data => { %{$c->request->params},
                          billing_profile_id => $c->stash->{profile}{id}, },
                desc => $c->loc('Special offpeak entry successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                data => { %{$c->request->params},
                          billing_profile_id => $c->stash->{profile}{id}, },
                desc  => $c->loc('Failed to create special offpeak entry'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{peaktimes_root_uri});
    }

    $c->stash(peaktimes_special_form => $form);
    $c->stash(peaktimes_special_createflag => 1);
}


1;

__END__

=head1 NAME

NGCP::Panel::Controller::Billing - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 profile_list

basis for the billing controller

=head2 root

just shows a list of billing profiles using datatables

=head2 ajax

Get billing_profiles and output them as JSON.

=head2 base

Fetch a billing_profile by its id.

=head2 edit

Show a modal to edit one billing_profile.

=head2 create

Show a modal to add a new billing_profile.

=head2 fees_list

basis for the billing_fees logic. for a certain billing_profile identified
by base.

=head2 fees

Shows a list of billing_fees for one billing_profile using datatables.

=head2 fees_base

Fetch a billing_fee (identified by id).

=head2 fees_ajax

Get billing_fees and output them as JSON.

=head2 fees_create

Show a modal to add a new billing_fee.

=head2 fees_upload

Show a modal to upload a CSV file of billing_fees and add them to the
Database.

=head2 fees_edit

Show a modal to edit a billing_fee.

=head2 fees_delete

Delete a billing_fee.

=head2 zones_list

basis for billing zones. part of a certain billing profile.

=head2 zones_ajax

sends a JSON representation of billing_zones under the current billing profile.

=head2 zones_create

Show a modal to create a new billing_zone in the current billing profile.

=head2 zones

Show a datatables list of billing_zones in the current billing profile.

=head2 zones_base

Fetch a billing_zone (identified by id).

=head2 zones_delete

Delete a billing_zone (defined by zones_base).

=head2 peaktimes_list

basis for billing_peaktime_* time definitions. part of a certain billing_profile.

=head2 peaktimes

show a list with peaktime weekdays and peaktime dates.

=head2 peaktime_weekdays_base

Define a certain weekday by id (for further processing in chain).

=head2 peaktime_weekdays_edit

Show a modal to edit one weekday.

=head2 load_weekdays

creates a weekdays structure from the stash variable weekdays_result
puts the result under weekdays on stash (will be used by template)

=head2 peaktime_specials_ajax

Returns an ajax representation of billing_peaktime_specials under the current
billing_profile. The rows are modified so that the final form will be
(id, date, startend).

This depends on inflation being activated in the schema.

=head2 peaktime_specials_base

Get one billing_peaktime_special from the database for further processing.

=head2 peaktime_specials_edit

Edit one billing_peaktime_special per modal and the form
NGCP::Panel::Form::BillingPeaktimeSpecial.

=head2 peaktime_specials_delete

Delete a billing_peaktime_special.

=head2 peaktime_specials_create

Create a new billing_peaktime_special under the current billing_profile.
Uses NGCP::Panel::Form::BillingPeaktimeSpecial.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
