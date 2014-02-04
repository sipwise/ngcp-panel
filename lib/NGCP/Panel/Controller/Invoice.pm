package NGCP::Panel::Controller::Billing;
use Sipwise::Base;
#use Text::CSV_XS;
#use DateTime::Format::ISO8601;

BEGIN { extends 'Catalyst::Controller'; }

#use NGCP::Panel::Utils::Contract;
#use NGCP::Panel::Utils::Message;
#use NGCP::Panel::Utils::Navigation;
#use NGCP::Panel::Utils::Datatables;
#use NGCP::Panel::Utils::Preferences;
#use NGCP::Panel::Utils::DateTime;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub invoice_list :Chained('/') :PathPart('invoice') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $dispatch_to = '_invoice_resultset_' . $c->user->roles;
    my $profiles_rs = $self->$dispatch_to($c);
    $c->stash(invoice_rs => $invoice_rs);
    $c->stash->{invoice_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", "search" => 1, "title" => $c->loc("#") },
        { name => "name", "search" => 1, "title" => $c->loc("Name") },
        { name => "reseller.name", "search" => 1, "title" => $c->loc("Reseller") },
    ]);

    $c->stash(template => 'invoice/list.tt');
}

sub _invoice_resultset_admin {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('invoice_profiles');
    return $rs;
}

sub _invoice_resultset_reseller {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('admins')
        ->find($c->user->id)->reseller->invoice_profiles;
    return $rs;
}

sub root :Chained('invoice_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('invoice_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{profiles_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{invoice_dt_columns});
    
    $c->detach( $c->view("JSON") );
}

sub base :Chained('invoice_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $invoice_id) = @_;

    unless($invoice_id && $invoice_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => $c->loc('Invalid profile id detected!')}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash->{zone_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'zone', search => 1, title => $c->loc('Zone') },
        { name => 'detail', search => 1, title => $c->loc('Zone Details') },
    ]);
    
    my $res = $c->stash->{profiles_rs}->find($invoice_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => $c->loc('Billing Profile does not exist!')}]);
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash(profile => {$res->get_inflated_columns});
    $c->stash(invoice_result => $res);
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
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
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
            my $old_prepaid = $c->stash->{invoice_result}->prepaid;

            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $c->stash->{invoice_result}->update($form->values);

                # if prepaid flag changed, update all subscribers for customers
                # who currently have the invoice profile active
                my $rs = $schema->resultset('invoice_mappings')->search({
                    invoice_invoice_id => $c->stash->{invoice_result}->id,
                });
                my $contract_rs = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'));
                if($old_prepaid && !$c->stash->{invoice_result}->prepaid) {
                    foreach my $map($rs->all) {
                        my $contract = $map->contract;
                        next unless($contract->contact->reseller_id); # skip non-customers
                        my $chosen_contract = $contract_rs->find({id => $contract->id});
                        next unless( defined $chosen_contract && $chosen_contract->get_column('invoice_mapping_id') == $map->id ); # is not current mapping
                        foreach my $sub($contract->voip_subscribers->all) {
                            my $prov_sub = $sub->provisioning_voip_subscriber;
                            next unless($sub->provisioning_voip_subscriber);
                            my $pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                                c => $c, attribute => 'prepaid', prov_subscriber => $prov_sub);
                            if($pref->first) {
                                $pref->first->delete;
                            }
                        }
                    }
                } elsif(!$old_prepaid && $c->stash->{invoice_result}->prepaid) {
                    foreach my $map($rs->all) {
                        my $contract = $map->contract;
                        next unless($contract->contact->reseller_id); # skip non-customers
                        my $chosen_contract = $contract_rs->find({id => $contract->id});
                        next unless( defined $chosen_contract && $chosen_contract->get_column('invoice_mapping_id') == $map->id ); # is not current mapping
                        foreach my $sub($contract->voip_subscribers->all) {
                            my $prov_sub = $sub->provisioning_voip_subscriber;
                            next unless($prov_sub);
                            my $pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                                c => $c, attribute => 'prepaid', prov_subscriber => $prov_sub);
                            if($pref->first) {
                                $pref->first->update({ value => 1 });
                            } else {
                                $pref->create({ value => 1 });
                            }
                        }
                    }
                }
        
            });

            delete $c->session->{created_objects}->{reseller};
            $c->flash(messages => [{type => 'success', text => $c->loc('Billing profile successfully updated')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc("Failed to update invoice profile."),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
    }

    $c->stash(edit_flag => 1);
    $c->stash(form => $form);
}

sub create :Chained('invoice_list') :PathPart('create') :Args(0) {
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
            delete $form->values->{reseller};
            my $profile = $c->model('DB')->resultset('invoice_profiles')->create($form->values);
            $c->session->{created_objects}->{invoice_profile} = { id => $profile->id };
            delete $c->session->{created_objects}->{reseller};

            $c->flash(messages => [{type => 'success', text => $c->loc('Billing profile successfully created')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc("Failed to create invoice profile."),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub create_without_reseller :Chained('invoice_list') :PathPart('create/noreseller') :Args(0) {
    my ($self, $c) = @_;

    $self->create($c, 1); 
}


sub fees_list :Chained('base') :PathPart('fees') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $c->stash->{fee_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'source', search => 1, title => $c->loc('Source Pattern') },
        { name => 'destination', search => 1, title => $c->loc('Destination Pattern') },
        { name => 'direction', search => 1, title => $c->loc('Match Direction') },
        { name => 'invoice_zone.detail', search => 1, title => $c->loc('Billing Zone') },
    ]);
    $c->stash(template => 'invoice/fees.tt');
}

sub fees :Chained('fees_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;

}

sub fees_base :Chained('fees_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $fee_id) = @_;

    unless($fee_id && $fee_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => $c->loc('Invalid invoice fee id detected!')}]);
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }
    
    my $res = $c->stash->{'invoice_result'}->invoice_fees
        ->search(undef, {join => 'invoice_zone',})
        ->find($fee_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => $c->loc('Billing Fee does not exist!')}]);
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }
    $c->stash(fee => {$res->get_columns}); #get_columns should not be used
    $c->stash->{fee}->{'invoice_zone.id'} = $res->invoice_zone->id
        if (defined $res->invoice_zone);
    $c->stash(fee_result => $res);
}

sub fees_ajax :Chained('fees_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{'invoice_result'}->invoice_fees;
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{fee_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub fees_create :Chained('fees_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    my $invoice_id = $c->stash->{profile}->{id};
    my $form = NGCP::Panel::Form::BillingFee->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $form,
        fields => {'invoice_zone.create' => $c->uri_for("$invoice_id/zones/create")},
        back_uri => $c->req->uri,
    );
    if($form->validated) {
        $form->values->{source} ||= '.';
        $c->stash->{'invoice_result'}
          ->invoice_fees->create($form->values);
        delete $c->session->{created_objects}->{invoice_zone};

        $c->flash(messages => [{type => 'success', text => $c->loc('Billing Fee successfully created!')}]);
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
        action => $c->uri_for_action('/invoice/fees_upload', $c->req->captures),
    );
    if($form->validated) {

        # TODO: check by formhandler?
        unless($upload) {
            $c->flash(messages => [{type => 'error', text => $c->loc('No Billing Fee file specified!')}]);
            $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
            return;
        }

        my $csv = Text::CSV_XS->new({allow_whitespace => 1, binary => 1, keep_meta_info => 1});
        my @cols = $c->config->{fees_csv}->{element_order};
        $csv->column_names (@cols);
        if ($c->req->params->{purge_existing}) {
            $c->stash->{'invoice_result'}->invoice_fees->delete_all;
        }

        my @fails = ();
        my $linenum = 0;
        try {
            $c->model('DB')->txn_do(sub {
                while(my $row = $csv->getline_hr($upload->fh)) {
                    ++$linenum;
                    if($csv->is_missing(1)) {
                        push @fails, $linenum;
                        next;
                    }
                    my $zone = $c->stash->{'invoice_result'}
                        ->invoice_zones
                        ->find_or_create({
                            zone => $row->{zone},
                            detail => $row->{zone_detail}
                        });
                    $row->{invoice_zone_id} = $zone->id;
                    delete $row->{zone};
                    delete $row->{zone_detail};
                    $c->stash->{'invoice_result'}
                        ->invoice_fees->create($row);
                }
            });
            my $text = $c->loc('Billing Fee successfully uploaded');
            if(@fails) {
                $text .= $c->loc(", but skipped the following line numbers: ") . (join ", ", @fails);
            }

            $c->flash(messages => [{type => 'success', text => $text}]);
        } catch($e) {
            $c->log->error("failed to upload csv: $e");
            $c->flash(messages => [{type => 'error', text => $c->loc('Failed to upload Billing Fees')}]);
        };

        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub fees_edit :Chained('fees_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    
    my $invoice_id = $c->stash->{profile}->{id};
    my $posted = ($c->request->method eq 'POST');
    my $params = $c->stash->{fee};
    $params->{invoice_zone}{id} = delete $params->{invoice_zone_id};
    $params = $params->merge($c->session->{created_objects});
    my $form = NGCP::Panel::Form::BillingFee->new;
    $form->field('invoice_zone')->field('id')->ajax_src('../../zones/ajax');
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $form,
        fields => {'invoice_zone.create' => $c->uri_for("$invoice_id/zones/create")},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        $form->values->{source} ||= '.';
        $form->values->{invoice_zone_id} = $form->values->{invoice_zone}{id};
        delete $form->values->{invoice_zone};
        $c->stash->{'fee_result'}
            ->update($form->values);
        delete $c->session->{created_objects}->{invoice_zone};
        $c->flash(messages => [{type => 'success', text => $c->loc('Billing Profile successfully changed!')}]);
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }
    
    $c->stash(edit_fee_flag => 1);
    $c->stash(form => $form);
}

sub fees_delete :Chained('fees_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    unless ( defined($c->stash->{'fee_result'}) ) {
        $c->flash(messages => [{type => 'error', text => $c->loc('Billing fee not found!')}]);
        return;
    }
    $c->stash->{'fee_result'}->delete;

    $c->flash(messages => [{type => 'success', text => $c->loc('Billing profile successfully deleted!')}]);
    $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
}

sub zones_list :Chained('base') :PathPart('zones') :CaptureArgs(0) {
    my ($self, $c) = @_;
    
    $c->stash( zones_root_uri =>
        $c->uri_for_action('/invoice/zones', [$c->req->captures->[0]])
    );
    $c->stash(template => 'invoice/zones.tt');
}

sub zones_ajax :Chained('zones_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{'invoice_result'}->invoice_zones;
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
            my $zone = $c->stash->{'invoice_result'}->invoice_zones->create($form->values);
            $c->session->{created_objects}->{invoice_zone} = { id => $zone->id };
            $c->flash(messages => [{type => 'success', text => $c->loc('Billing Zone successfully created')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create invoice zone.'),
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
    
    unless($zone_id && $zone_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => $c->loc('Invalid invoice zone id detected')}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{zones_root_uri});
    }
    
    my $res = $c->stash->{'invoice_result'}->invoice_zones
        ->find($zone_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => $c->loc('Billing zone does not exist!')}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{zones_root_uri});
    }
    $c->stash(zone_result => $res);
}

sub zones_delete :Chained('zones_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{zone_result}->delete;
        $c->flash(messages => [{type => 'success', text => $c->loc('Billing zone successfully deleted')}]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete invoice zone.'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{zones_root_uri});
}

sub peaktimes_list :Chained('base') :PathPart('peaktimes') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $c->stash(peaktimes_root_uri =>
        $c->uri_for_action('/invoice/peaktimes', [$c->req->captures->[0]])
    );
    
    my $rs = $c->stash->{invoice_result}->invoice_peaktime_weekdays;
    $rs = $rs->search(undef, {order_by => 'start'});

    $c->stash->{special_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'start', search => 1, title => $c->loc('Start Date') },
        { name => 'end', search => 1, title => $c->loc('End Date') },
    ]);

    $c->stash(weekdays_result => $rs);
    $c->stash(template => 'invoice/peaktimes.tt');
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
            text => $c->loc('This weekday does not exist.')
        }]);
        $c->response->redirect($c->uri_for_action(
            "/invoice/peaktimes", [$c->req->captures->[0]],
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
        $form->values->{weekday} = $c->stash->{weekday_id};
        $form->values->{start} = '00:00:00' unless($form->values->{start});
        $form->values->{end} = '23:59:59' unless($form->values->{end});
        $c->stash->{'weekdays_result'}
            ->create($form->values);
    }
    
    my $delete_param = $c->request->params->{delete};
    if($delete_param) {
        my $rs = $c->stash->{weekdays_result}
            ->find($delete_param);
        unless ($rs) {
            $c->flash(messages => [{
                type => 'error',
                text => $c->loc('The timerange you wanted to delete does not exist.')
            }]);
            $c->response->redirect($c->uri_for_action(
                "/invoice/peaktimes", [$c->req->captures->[0]],
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

    my @WEEKDAYS = (
            $c->loc('Monday'),
            $c->loc('Tuesday'),
            $c->loc('Wednesday'),
            $c->loc('Thursday'),
            $c->loc('Friday'),
            $c->loc('Saturday'),
            $c->loc('Sunday')
        );

    my @weekdays;
    for(0 .. 6) {
        $weekdays[$_] = {
            name => $WEEKDAYS[$_],
            ranges => [],
            edit_link => $c->uri_for_action("/invoice/peaktime_weekdays_edit",
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

    my $resultset = $c->stash->{'invoice_result'}->invoice_peaktime_specials;
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{special_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub peaktime_specials_base :Chained('peaktimes_list') :PathPart('date') :CaptureArgs(1) {
    my ($self, $c, $special_id) = @_;
    
        unless($special_id && $special_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => $c->loc('Invalid peaktime date id detected!')}]);
        $c->response->redirect($c->stash->{peaktimes_root_uri});
        return;
    }
    
    my $res = $c->stash->{'invoice_result'}->invoice_peaktime_specials
        ->find($special_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => $c->loc('Peaktime date does not exist!')}]);
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
    my $form = NGCP::Panel::Form::BillingPeaktimeSpecial->new;
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
            $c->flash(messages => [{type => 'success', text => $c->loc('Special offpeak entry successfully updated')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update special offpeak entry.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{peaktimes_root_uri});
    }

    $c->stash(peaktimes_special_editflag => 1);
    $c->stash(peaktimes_special_form => $form);
}

sub peaktime_specials_delete :Chained('peaktime_specials_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    try {
        $c->stash->{special_result}->delete;
            $c->flash(messages => [{type => 'success', text => 'Special offpeak entry successfully deleted'}]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete special offpeak entry.'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{peaktimes_root_uri});
}

sub peaktime_specials_create :Chained('peaktimes_list') :PathPart('date/create') :Args(0) {
    my ($self, $c) = @_;
    $self->load_weekdays($c);
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::BillingPeaktimeSpecial->new;
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
            $c->stash->{'invoice_result'}->invoice_peaktime_specials
                ->create($form->values);
            $c->flash(messages => [{type => 'success', text => $c->loc('Special offpeak entry successfully created')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create special offpeak entry.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{peaktimes_root_uri});
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

=head2 invoice_list

basis for the invoice controller

=head2 root

just shows a list of invoice profiles using datatables

=head2 ajax

Get invoice_profiles and output them as JSON.

=head2 base

Fetch a invoice_profile by its id.

=head2 edit

Show a modal to edit one invoice_profile.

=head2 create

Show a modal to add a new invoice_profile.

=head2 fees_list

basis for the invoice_fees logic. for a certain invoice_profile identified
by base.

=head2 fees

Shows a list of invoice_fees for one invoice_profile using datatables.

=head2 fees_base

Fetch a invoice_fee (identified by id).

=head2 fees_ajax

Get invoice_fees and output them as JSON.

=head2 fees_create

Show a modal to add a new invoice_fee.

=head2 fees_upload

Show a modal to upload a CSV file of invoice_fees and add them to the
Database.

=head2 fees_edit

Show a modal to edit a invoice_fee.

=head2 fees_delete

Delete a invoice_fee.

=head2 zones_list

basis for invoice zones. part of a certain invoice profile.

=head2 zones_ajax

sends a JSON representation of invoice_zones under the current invoice profile.

=head2 zones_create

Show a modal to create a new invoice_zone in the current invoice profile.

=head2 zones

Show a datatables list of invoice_zones in the current invoice profile.

=head2 zones_base

Fetch a invoice_zone (identified by id).

=head2 zones_delete

Delete a invoice_zone (defined by zones_base).

=head2 peaktimes_list

basis for invoice_peaktime_* time definitions. part of a certain invoice_profile.

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

Returns an ajax representation of invoice_peaktime_specials under the current
invoice_profile. The rows are modified so that the final form will be
(id, date, startend).

This depends on inflation being activated in the schema.

=head2 peaktime_specials_base

Get one invoice_peaktime_special from the database for further processing.

=head2 peaktime_specials_edit

Edit one invoice_peaktime_special per modal and the form
NGCP::Panel::Form::BillingPeaktimeSpecial.

=head2 peaktime_specials_delete

Delete a invoice_peaktime_special.

=head2 peaktime_specials_create

Create a new invoice_peaktime_special under the current invoice_profile.
Uses NGCP::Panel::Form::BillingPeaktimeSpecial.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
