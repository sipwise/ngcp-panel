package NGCP::Panel::Controller::Billing;
use Sipwise::Base;
use Text::CSV_XS;
use I18N::Langinfo qw(langinfo DAY_1 DAY_2 DAY_3 DAY_4 DAY_5 DAY_6 DAY_7);
use DateTime::Format::ISO8601;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::BillingProfile::Admin;
use NGCP::Panel::Form::BillingProfile::Reseller;
use NGCP::Panel::Form::BillingFee;
use NGCP::Panel::Form::BillingZone;
use NGCP::Panel::Form::BillingPeaktimeWeekdays;
use NGCP::Panel::Form::BillingPeaktimeSpecial;
use NGCP::Panel::Form::BillingFeeUpload;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Datatables;

my @WEEKDAYS = map { langinfo($_) } (DAY_2, DAY_3, DAY_4, DAY_5, DAY_6, DAY_7, DAY_1);
#Monday Tuesday Wednesday Thursday Friday Saturday Sunday

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub profile_list :Chained('/') :PathPart('billing') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $dispatch_to = '_profile_resultset_' . $c->user->auth_realm;
    my $profiles_rs = $self->$dispatch_to($c);
    $c->stash(profiles_rs => $profiles_rs);
    $c->stash->{profile_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", "search" => 1, "title" => "#" },
        { name => "name", "search" => 1, "title" => "Name" },
        { name => "reseller.name", "search" => 1, "title" => "Reseller" },
    ]);

    $c->stash(template => 'billing/list.tt');
}

sub _profile_resultset_admin {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('billing_profiles');
    return $rs;
}

sub _profile_resultset_reseller {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('admins')
        ->find($c->user->id)->reseller->billing_profiles;
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

sub base :Chained('profile_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $profile_id) = @_;

    unless($profile_id && $profile_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid profile id detected!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash->{zone_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => '#' },
        { name => 'zone', search => 1, title => 'Zone' },
        { name => 'detail', search => 1, title => 'Zone Details' },
    ]);
    
    my $res = $c->stash->{profiles_rs}->find($profile_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Billing Profile does not exist!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash(profile => {$res->get_inflated_columns});
    $c->stash(profile_result => $res);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = $c->stash->{profile};
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = $params->merge($c->session->{created_objects});
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::BillingProfile::Admin->new;
    } else {
        $form = NGCP::Panel::Form::BillingProfile::Reseller->new;
    }
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
            if($c->user->is_superuser) {
                $form->values->{reseller_id} = $form->values->{reseller}{id};   
            } else {
                $form->values->{reseller_id} = $c->user->reseller_id;
            }
            delete $form->values->{reseller};
            $c->stash->{profile_result}->update($form->values);

            $c->flash(messages => [{type => 'success', text => 'Billing profile successfully updated'}]);
        } catch($e) {
            $c->log->error("failed to update billing profile: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to update billing profile'}]);
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/billing'));
    }

    $c->stash(edit_flag => 1);
    $c->stash(form => $form);
}

sub create :Chained('profile_list') :PathPart('create') :Args(0) {
    my ($self, $c, $no_reseller) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = $params->merge($c->session->{created_objects});
    if($c->user->is_superuser && $no_reseller) {
        $form = NGCP::Panel::Form::BillingProfile::Reseller->new;
    } elsif($c->user->is_superuser) {
        $form = NGCP::Panel::Form::BillingProfile::Admin->new;
    } else {
        $form = NGCP::Panel::Form::BillingProfile::Reseller->new;
    }
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
            if($c->user->is_superuser && $no_reseller) {
                $form->values->{reseller_id} = $c->user->reseller_id;
            } elsif($c->user->is_superuser) {
                $form->values->{reseller_id} = $form->values->{reseller}{id};   
            } else {
                $form->values->{reseller_id} = $c->user->reseller_id;
            }
            delete $form->values->{reseller};
            my $profile = $c->model('DB')->resultset('billing_profiles')->create($form->values);
            $c->session->{created_objects}->{billing_profile} = { id => $profile->id };

            $c->flash(messages => [{type => 'success', text => 'Billing profile successfully created'}]);
        } catch($e) {
            $c->log->error("failed to create billing profile: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to create billing profile'}]);
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


sub fees_list :Chained('base') :PathPart('fees') :CaptureArgs(0) {
    my ($self, $c) = @_;
    
    $c->stash(template => 'billing/fees.tt');
}

sub fees :Chained('fees_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;

}

sub fees_base :Chained('fees_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $fee_id) = @_;

    unless($fee_id && $fee_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid billing fee id detected!'}]);
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }
    
    my $res = $c->stash->{'profile_result'}->billing_fees
        ->search(undef, {join => 'billing_zone',})
        ->find($fee_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Billing Fee does not exist!'}]);
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }
    $c->stash(fee => {$res->get_columns}); #get_columns should not be used
    $c->stash->{fee}->{'billing_zone.id'} = $res->billing_zone->id
        if (defined $res->billing_zone);
    $c->stash(fee_result => $res);
}

sub fees_ajax :Chained('fees_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{'profile_result'}->billing_fees
        ->search(undef, {
            join => 'billing_zone',
            columns => [
                {'zone' => 'billing_zone.zone'},
               'id','source','destination','direction'
            ]
        });
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "source", "destination", "direction", "zone"],
                 ["source", "destination", "direction"]]);
    
    $c->detach( $c->view("JSON") );
}

sub fees_create :Chained('fees_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    my $profile_id = $c->stash->{profile}->{id};
    my $form = NGCP::Panel::Form::BillingFee->new;
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
        $c->stash->{'profile_result'}
          ->billing_fees->create($form->values);
        delete $c->session->{created_objects}->{billing_zone};

        $c->flash(messages => [{type => 'success', text => 'Billing Fee successfully created!'}]);
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub fees_upload :Chained('fees_list') :PathPart('upload') :Args(0) {
    my ($self, $c) = @_;
    
    my $form = NGCP::Panel::Form::BillingFeeUpload->new;
    my $upload = $c->req->upload('upload_fees');
    my $posted = $c->req->method eq 'POST';
    my @params = (
        upload_fees => $posted ? $upload : undef,
        );
    $form->process(
        posted => $posted,
        params => { @params },
        action => $c->uri_for_action('/billing/fees_upload', $c->req->captures),
    );
    if($form->validated) {

        # TODO: check by formhandler?
        unless($upload) {
            $c->flash(messages => [{type => 'error', text => 'No Billing Fee file specified!'}]);
            $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
            return;
        }

        my $csv = Text::CSV_XS->new({allow_whitespace => 1, binary => 1});
        my @cols = $c->config->{fees_csv}->{element_order};
        $csv->column_names (@cols);
        if ($c->req->params->{purge_existing}) {
            $c->stash->{'profile_result'}->billing_fees->delete_all;
        }


        while (my $row = $csv->getline_hr($upload->fh)) {
            my $zone = $c->stash->{'profile_result'}
                ->billing_zones
                ->find_or_create({
                    zone => $row->{zone},
                    detail => $row->{zone_detail}
                });
            $row->{billing_zone_id} = $zone->id;
            delete $row->{zone};
            delete $row->{zone_detail};
            $c->stash->{'profile_result'}
                ->billing_fees->create($row);
        }
        $c->flash(messages => [{type => 'success', text => 'Billing Fee successfully uploaded!'}]);
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub fees_edit :Chained('fees_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    
    my $profile_id = $c->stash->{profile}->{id};
    my $posted = ($c->request->method eq 'POST');
    my $params = $c->stash->{fee};
    $params->{billing_zone}{id} = delete $params->{billing_zone_id};
    $params = $params->merge($c->session->{created_objects});
    my $form = NGCP::Panel::Form::BillingFee->new;
    $form->field('billing_zone')->field('id')->ajax_src('../../zones/ajax');
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
        $form->values->{billing_zone_id} = $form->values->{billing_zone}{id};
        delete $form->values->{billing_zone};
        $c->stash->{'fee_result'}
            ->update($form->values);
        delete $c->session->{created_objects}->{billing_zone};
        $c->flash(messages => [{type => 'success', text => 'Billing Profile successfully changed!'}]);
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }
    
    $c->stash(edit_fee_flag => 1);
    $c->stash(form => $form);
}

sub fees_delete :Chained('fees_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    unless ( defined($c->stash->{'fee_result'}) ) {
        $c->flash(messages => [{type => 'error', text => 'Billing fee not found!'}]);
        return;
    }
    $c->stash->{'fee_result'}->delete;

    $c->flash(messages => [{type => 'success', text => 'Billing profile successfully deleted!'}]);
    $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
}

sub zones_list :Chained('base') :PathPart('zones') :CaptureArgs(0) {
    my ($self, $c) = @_;
    
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
    
    my $form = NGCP::Panel::Form::BillingZone->new;
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
            $c->flash(messages => [{type => 'success', text => 'Billing Zone successfully created'}]);
        } catch($e) {
            $c->log->error("failed to create billing zone: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to create billing zone'}]);
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
    
    unless($zone_id && $zone_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid billing zone id detected'}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{zones_root_uri});
    }
    
    my $res = $c->stash->{'profile_result'}->billing_zones
        ->find($zone_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Billing zone does not exist!'}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{zones_root_uri});
    }
    $c->stash(zone_result => $res);
}

sub zones_delete :Chained('zones_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{zone_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'Billing zone successfully deleted'}]);
    } catch($e) {
        $c->log->error("failed to delete billing zone: $e");
        $c->flash(messages => [{type => 'error', text => 'Failed to delete billing zone'}]);
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
        $c->flash(messages => [{
            type => 'error',
            text => 'This weekday does not exist.'
        }]);
        $c->response->redirect($c->uri_for_action(
            "/billing/peaktimes", [$c->req->captures->[0]],
        ));
    }
    $c->stash(weekday_id => $weekday_id);
}

sub peaktime_weekdays_edit :Chained('peaktime_weekdays_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    
    my $form = NGCP::Panel::Form::BillingPeaktimeWeekdays->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
    );
    if($form->validated) {
        $c->stash->{'weekdays_result'}
            ->create({
                %{ $form->fif },
                weekday => $c->stash->{weekday_id},
             });
    }
    
    my $delete_param = $c->request->params->{delete};
    if($delete_param) {
        my $rs = $c->stash->{weekdays_result}
            ->find($delete_param);
        unless ($rs) {
            $c->flash(messages => [{
                type => 'error',
                text => 'The timerange you wanted to delete does not exist.'
            }]);
            $c->response->redirect($c->uri_for_action(
                "/billing/peaktimes", [$c->req->captures->[0]],
            ));
            return;
        }
        $rs->delete();
    }

    $form = NGCP::Panel::Form::BillingPeaktimeWeekdays->new
        unless $form->has_errors;

    $self->load_weekdays($c);
    $c->stash(weekday => $c->stash->{weekdays}->[$c->stash->{weekday_id}]);
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub load_weekdays {
    my ($self, $c) = @_;

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

    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "start", "end",],
                 ["start", "end"]]);
    
    for my $row (@{ $c->stash->{aaData} }) {
        $row->{date} = DateTime::Format::ISO8601->parse_datetime($row->{start})->date;
        $row->{startend} = 
            DateTime::Format::ISO8601->parse_datetime($row->{start})->hms
            . " - " . 
            DateTime::Format::ISO8601->parse_datetime($row->{end})->hms;
    }
    
    $c->detach( $c->view("JSON") );
}

sub peaktime_specials_base :Chained('peaktimes_list') :PathPart('date') :CaptureArgs(1) {
    my ($self, $c, $special_id) = @_;
    
        unless($special_id && $special_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid peaktime date id detected!'}]);
        $c->response->redirect($c->stash->{peaktimes_root_uri});
        return;
    }
    
    my $res = $c->stash->{'profile_result'}->billing_peaktime_specials
        ->find($special_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Peaktime date does not exist!'}]);
        $c->response->redirect($c->stash->{peaktimes_root_uri});
        return;
    }
    $self->load_weekdays($c);
    $c->stash(special_result => $res);
}

sub peaktime_specials_edit :Chained('peaktime_specials_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $data_res = $c->stash->{special_result};
    return unless (defined $data_res);
    my $data = {
        date => $data_res->start->date,
        'time.start' => $data_res->start->hms,
        'time.end' => $data_res->end->hms
    };
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::BillingPeaktimeSpecial->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $data,
        action => $c->uri_for_action('/billing/peaktime_specials_edit', $c->req->captures),
    );
    if($posted && $form->validated) {
        my $dates = $form->get_dates;
        $c->stash->{special_result}->update( $dates );

        $c->flash(messages => [{type => 'success', text => 'Peaktime date successfully changed!'}]);
        $c->response->redirect($c->stash->{peaktimes_root_uri});
        return;
    }

    $c->stash(peaktimes_special_editflag => 1);
    $c->stash(peaktimes_special_form => $form);
}

sub peaktime_specials_delete :Chained('peaktime_specials_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    return unless (defined $c->stash->{special_result});
    $c->stash->{special_result}->delete;
}

sub peaktime_specials_create :Chained('peaktimes_list') :PathPart('date/create') :Args(0) {
    my ($self, $c) = @_;
    $self->load_weekdays($c);
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::BillingPeaktimeSpecial->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        action => $c->uri_for_action('/billing/peaktime_specials_create', $c->req->captures),
    );
    if($form->validated) {
        my $dates = $form->get_dates;
        $c->stash->{'profile_result'}->billing_peaktime_specials
            ->create( $dates );

        $c->flash(messages => [{type => 'success', text => 'Peaktime date successfully created!'}]);
        $c->response->redirect($c->stash->{peaktimes_root_uri});
        return;
    }

    $c->stash(peaktimes_special_form => $form);
    $c->stash(peaktimes_special_createflag => 1);
}

$CLASS->meta->make_immutable;

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
