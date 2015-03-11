package NGCP::Panel::Controller::Sound;
use Sipwise::Base;


BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::Sound::AdminSet;
use NGCP::Panel::Form::Sound::ResellerSet;
use NGCP::Panel::Form::Sound::CustomerSet;
use NGCP::Panel::Form::Sound::File;
use NGCP::Panel::Form::Sound::LoadDefault;
use File::Type;
use File::Slurp;
use File::Basename;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Sounds;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Sems;

sub auto :Private {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);

    # only allow access to admin/reseller if cloudpbx is not enabled
    if(!$c->config->{features}->{cloudpbx} && 
       $c->user->roles ne "admin" &&
       $c->user->roles ne "reseller") {

        $c->detach('/denied_page');
    }

    # even for pbx, it's only for admin/reseller/subscriberadmins
    if($c->user->roles eq "subscriber") {
        $c->detach('/denied_page');
    }

    # and then again, it's only for subscriberadmins with pbxaccount product
    if($c->user->roles eq "subscriberadmin") {
        my $contract_id = $c->user->account_id;
        my $contract_select_rs = NGCP::Panel::Utils::Contract::get_contract_rs(
            schema => $c->model('DB'));
        $contract_select_rs = $contract_select_rs->search({ 'me.id' => $contract_id });
        my $product_id = $contract_select_rs->first->get_column('product_id');
        unless($product_id) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => "No product for customer contract id $contract_id found",
                desc  => $c->loc('No product for this customer contract found.'),
            );
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/sound'));
        }
        my $product = $c->model('DB')->resultset('products')->find({ 
            id => $product_id, class => 'pbxaccount',
        });
        unless($product) {
            $c->detach('/denied_page');
        }
        $c->stash->{contract_rs} = $contract_select_rs;
    }

    return 1;
}

sub sets_list :Chained('/') :PathPart('sound') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    if($c->stash->{contract_rs}) {
        NGCP::Panel::Utils::Sounds::stash_soundset_list(
            c => $c, 
            contract => $c->stash->{contract_rs}->first,
        );
    } else {
        NGCP::Panel::Utils::Sounds::stash_soundset_list(c => $c);
    }
    $c->stash(template => 'sound/list.tt');
    return;
}

sub contract_sets_list :Chained('/') :PathPart('sound/contract') :CaptureArgs(1) {
    my ( $self, $c, $contract_id ) = @_;

    unless($contract_id && is_int($contract_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "Invalid contract id $contract_id found",
            desc  => $c->loc('Invalid contract id found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/sound'));
    }
    if($c->user->roles eq "subscriberadmin" && $c->user->account_id != $contract_id) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "access violation, subscriberadmin ".$c->user->uuid." with contract id ".$c->user->account_id." tries to access foreign contract id $contract_id",
            desc  => $c->loc('Invalid contract id found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/sound'));
    }
    my $contract = $c->model('DB')->resultset('contracts')->find($contract_id);
    unless($contract) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "Contract id $contract_id not found",
            desc  => $c->loc('Invalid contract id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/sound'));
    }

    NGCP::Panel::Utils::Sounds::stash_soundset_list(
        c => $c, 
        contract => $contract,
    );
    $c->stash(template => 'sound/list.tt');
    return;
}

sub root :Chained('sets_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    return;
}

sub ajax :Chained('sets_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{sets_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{soundset_dt_columns});
    $c->detach( $c->view("JSON") );
    return;
}

sub contract_ajax :Chained('contract_sets_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{sets_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{soundset_dt_columns});
    $c->detach( $c->view("JSON") );
    return;
}

sub base :Chained('sets_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;

    unless($set_id && is_int($set_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid sound set id detected',
            desc  => $c->loc('Invalid sound set id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/sound'));
    }

    my $res = $c->stash->{sets_rs}->find($set_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Sound set does not exist',
            desc  => $c->loc('Sound set does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/sound'));
    }
    $c->stash(set_result => $res);
    return;
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = { $c->stash->{set_result}->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params->{contract}{id} = delete $params->{contract_id};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::Sound::AdminSet->new;
    } elsif($c->user->roles eq "reseller") {
        $form = NGCP::Panel::Form::Sound::ResellerSet->new;
    } else {
        $form = NGCP::Panel::Form::Sound::CustomerSet->new;
    }
    unless ($c->config->{features}->{cloudpbx} || $params->{contract}{id} ) {
        my $form_render_list = $form->block('fields')->render_list;
        $form->block('fields')->render_list([ grep {$_ !~ m/^contract(_default)?/} @{ $form_render_list } ]);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
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
            if($c->user->roles eq "admin") {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
                $form->values->{contract_id} = $form->values->{contract}{id} // undef;
                if(defined $form->values->{contract_id}) {
                    $form->values->{contract_default} //= 0;
                } else {
                    $form->values->{contract_default} = 0;
                }
            } elsif($c->user->roles eq "reseller") {
                if(defined $c->stash->{set_result}->contract_id) {
                    $form->values->{contract_default} //= 0;
                } else {
                    $form->values->{contract_default} = 0;
                }
            } else {
                $form->values->{contract_default} //= 0;
            }
            delete $form->values->{reseller};
            delete $form->values->{contract};
            $c->model('DB')->txn_do(sub {
                # if contract default is set, clear old ones first
                if($c->stash->{set_result}->contract_id && $form->values->{contract_default} == 1) {
                    $c->stash->{sets_rs}->search({
                        reseller_id => $c->stash->{set_result}->reseller_id,
                        contract_id => $c->stash->{set_result}->contract_id,
                        contract_default => 1,
                    })->update_all({ contract_default => 0 });
                }

                my $old_contract_default = $c->stash->{set_result}->contract_default;
                $c->stash->{set_result}->update($form->values);

                if($c->stash->{set_result}->contract && 
                   $c->stash->{set_result}->contract_default == 1 && $old_contract_default != 1) {
                    # go over each subscriber in the contract and set the contract_sound_set
                    # preference if it doesn't have one set yet
                    my $contract = $c->stash->{set_result}->contract;
                    foreach my $bill_subscriber($contract->voip_subscribers->all) {
                        my $prov_subscriber = $bill_subscriber->provisioning_voip_subscriber;
                        if($prov_subscriber) {
                            my $pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                               c => $c, prov_subscriber => $prov_subscriber, attribute => 'contract_sound_set', 
                            );
                            unless($pref_rs->first) {
                                $pref_rs->create({ value => $c->stash->{set_result}->id });
                            }
                        }
                    }
                }
            });
            delete $c->session->{created_objects}->{reseller};
            delete $c->session->{created_objects}->{contract};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Sound set successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to update sound set'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/sound'));
    }

    $c->stash(
        form => $form,
        edit_flag => 1,
    );
    return;
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {

        my $schema = $c->model('DB');
        $schema->txn_do(sub {

            # remove all usr_preferenes where this set is assigned
            if($c->stash->{set_result}->contract_id) {
                my $pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, attribute => 'contract_sound_set', 
                );
                $pref_rs->search({ value => $c->stash->{set_result}->id })->delete;
            }
            foreach my $p(qw/usr dom peer/) {
                $schema->resultset("voip_".$p."_preferences")->search({
                    'attribute.attribute' => 'sound_set',
                    value => $c->stash->{set_result}->id,
                },{
                    join => 'attribute',
                })->delete_all; # explicit delete_all, otherwise query fails
            }

            $c->stash->{set_result}->delete;
        });
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{set_result}->get_inflated_columns },
            desc => $c->loc('Sound set successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete sound set'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/sound'));
    return;
}

sub create :Chained('sets_list') :PathPart('create') :Args() {
    my ($self, $c, $contract_id) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::Sound::AdminSet->new;
        if($contract_id) {
            my $contract = $c->model('DB')->resultset('contracts')->find($contract_id);
            if($contract) {
                $params->{contract}{id} = $contract->id;
                $params->{reseller}{id} = $contract->contact->reseller_id;
            }
        }
    } elsif($c->user->roles eq "reseller") {
        $form = NGCP::Panel::Form::Sound::ResellerSet->new;
        if($contract_id) {
            my $contract = $c->model('DB')->resultset('contracts')->find($contract_id);
            if($contract && $contract->contact->reseller_id == $c->user->reseller_id) {
                $params->{contract}{id} = $contract->id;
            }
        }
    } else {
        $form = NGCP::Panel::Form::Sound::CustomerSet->new;
    }
    unless ($c->config->{features}->{cloudpbx}) {
        my $form_render_list = $form->block('fields')->render_list;
        $form->block('fields')->render_list([ grep {$_ !~ m/^contract(_default)?/} @{ $form_render_list } ]);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
            'contract.create' => $c->uri_for_action('/customer/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            if($c->user->roles eq "admin") {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
                $form->values->{contract_id} = $form->values->{contract}{id} // undef;
                if(defined $form->values->{contract_id}) {
                    $form->values->{contract_default} //= 0;
                } else {
                    $form->values->{contract_default} = 0;
                }
            } elsif($c->user->roles eq "reseller") {
                $form->values->{reseller_id} = $c->user->reseller_id;
                $form->values->{contract_id} = $form->values->{contract}{id} // undef;
                if(defined $form->values->{contract_id}) {
                    $form->values->{contract_default} //= 0;
                } else {
                    $form->values->{contract_default} = 0;
                }
            } else {
                $form->values->{reseller_id} = $c->user->contract->contact->reseller_id;
                $form->values->{contract_id} = $c->user->account_id;
                $form->values->{contract_default} //= 0;
            }
            delete $form->values->{reseller};
            delete $form->values->{contract};

            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                # if a new contract default is set, clear old ones first
                if($form->values->{contract_id} && $form->values->{contract_default} == 1) {
                    $c->stash->{sets_rs}->search({
                        reseller_id => $form->values->{reseller_id},
                        contract_id => $form->values->{contract_id},
                        contract_default => 1,
                    })->update({ contract_default => 0 });
                }
                my $set = $c->stash->{sets_rs}->create($form->values);

                if($set->contract && $set->contract_default == 1) {
                    # go over each subscriber in the contract and set the contract_sound_set
                    # preference if it doesn't have one set yet
                    my $contract = $set->contract;
                    foreach my $bill_subscriber($contract->voip_subscribers->all) {
                        my $prov_subscriber = $bill_subscriber->provisioning_voip_subscriber;
                        if($prov_subscriber) {
                            my $pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                               c => $c, prov_subscriber => $prov_subscriber, attribute => 'contract_sound_set', 
                            );
                            unless($pref_rs->first) {
                                $pref_rs->create({ value => $set->id });
                            }
                        }
                    }
                }
            });

            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Sound set successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to create sound set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/sound'));
    }

    $c->stash(
        form => $form,
        create_flag => 1,
    );
    return;
}

sub handles_list :Chained('base') :PathPart('handles') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $files_rs = $c->stash->{set_result}->voip_sound_files;

    $c->stash(files_rs => $files_rs);
    $c->stash(handles_base_uri =>
        $c->uri_for_action("/sound/handles_root", [$c->req->captures->[0]]));
    
    my $handles_rs = $c->model('DB')->resultset('voip_sound_groups')
        ->search({
        },{
            select => ['groups.name', \'handles.name', \'handles.id', 'files.filename', 'files.loopplay', 'files.codec', 'files.id'],
            as => [ 'groupname', 'handlename', 'handleid', 'filename', 'loopplay', 'codec', 'fileid'],
            alias => 'groups',
            from => [
                { groups => 'provisioning.voip_sound_groups' },
                [
                    { handles => 'provisioning.voip_sound_handles', -join_type=>'left'},
                    { 'groups.id' => 'handles.group_id'},
                ],
                [
                    { files => 'provisioning.voip_sound_files', -join_type => 'left'},
                    { 'handles.id' => { '=' => \'files.handle_id'}, 'files.set_id' => $c->stash->{set_result}->id},
                ],
            ],
        });

    if($c->stash->{set_result}->contract_id) {
        $handles_rs = $handles_rs->search({ 
            'groups.name' => { '-in' => [qw/pbx music_on_hold digits/] } 
        });
    } else {
        #$handles_rs = $handles_rs->search({ 'groups.name' => { '!=' => 'pbx' } });
    }

    unless($c->config->{features}->{cloudpbx}) {
        $handles_rs = $handles_rs->search({ 'groups.name' => { '!=' => 'pbx' } });
    }
    unless($c->config->{features}->{cloudpbx} || $c->config->{features}->{musiconhold}) {
        $handles_rs = $handles_rs->search({ 'groups.name' => { '!=' => 'music_on_hold' } });
    }
    unless($c->config->{features}->{callingcard}) {
        $handles_rs = $handles_rs->search({ 'groups.name' => { '!=' => 'calling_card' } });
    }
    unless($c->config->{features}->{mobilepush}) {
        $handles_rs = $handles_rs->search({ 'groups.name' => { '!=' => 'mobile_push' } });
    }

    
    my @rows = $handles_rs->all;
    
    my %groups;
    for my $handle (@rows) {
        $groups{ $handle->get_column('groupname') } = []
            unless exists $groups{ $handle->get_column('groupname') };
        push @{ $groups{ $handle->get_column('groupname') } }, $handle;
    }
    $c->stash(sound_groups => \%groups);
    $c->stash(handles_rs => $handles_rs);

    $c->stash(has_edit => 1);
    $c->stash(has_delete => 1);
    $c->stash(template => 'sound/handles_list.tt');
    return;
}

sub handles_root :Chained('handles_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub handles_base :Chained('handles_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $handle_id) = @_;

    unless($handle_id && is_int($handle_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid sound handle id detected',
            desc  => $c->loc('Invalid sound handle id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{handles_base_uri});
    }
    my @tmph = $c->stash->{handles_rs}->all;
    unless($c->stash->{handles_rs}->find({ 'handles.id' => $handle_id })) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Sound handle id does not exist',
            desc  => $c->loc('Sound handle id does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{handles_base_uri});
    }

    my $res = $c->stash->{files_rs}->find_or_create(handle_id => $handle_id);
    unless(defined $res ) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Sound handle not found',
            desc  => $c->loc('Sound handle not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{handles_base_uri});
    }
    $c->stash(file_result => $res);
    return;
}

sub handles_edit :Chained('handles_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $upload = $c->req->upload('soundfile');
    my %params = (
        %{ $c->request->params },
        soundfile => $posted ? $upload : undef,
    );
    my $file_result = $c->stash->{file_result};
    my $form = NGCP::Panel::Form::Sound::File->new;
    $form->process(
        posted => $posted,
        params => \%params,
        item   => $file_result,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    
    if($posted && $form->validated) {
        if (defined $upload) {
            my $soundfile = eval { $upload->slurp };
            my $filename = eval { $upload->filename };
            
            my $ft = File::Type->new();
            unless ($ft->checktype_contents($soundfile) eq 'audio/x-wav') {
                NGCP::Panel::Utils::Message::error(
                    c     => $c,
                    log   => 'Invalid file type detected, only WAV supported',
                    desc  => $c->loc('Invalid file type detected, only WAV supported'),
                );
                NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{handles_base_uri});
            }
            
            my $target_codec = 'WAV';

            # clear audio caches
            SWITCH: for ($file_result->handle->group->name) {
                /^calling_card$/ && do {
                    try {
                        NGCP::Panel::Utils::Sems::clear_audio_cache($c, "appserver", $file_result->set_id, $file_result->handle->name);
                    } catch ($e) {
                        NGCP::Panel::Utils::Message::error(
                            c => $c,
                            error => "Failed to clear audio cache for " . $file_result->handle->group->name . " at appserver",
                            desc  => $c->loc('Failed to clear audio cache.'),
                        );
                        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{handles_base_uri});
                    }
                    last SWITCH;
                };
                /^(pbx|music_on_hold|voucher_recharge|play_balance|conference|digits)$/ && do {
                    my $service;
                    try {
                        if(!$file_result->set->contract_id) {
                            $service = "appserver";
                            NGCP::Panel::Utils::Sems::clear_audio_cache($c, $service, $file_result->set_id, $file_result->handle->name);
                        } else {
                            $service = "pbx";
                            NGCP::Panel::Utils::Sems::clear_audio_cache($c, $service, $file_result->set_id, $file_result->handle->name);
                        }
                    } catch ($e) {
                        NGCP::Panel::Utils::Message::error(
                            c => $c,
                            error => "Failed to clear audio cache for " . $file_result->handle->group->name . " on $service",
                            desc  => $c->loc('Failed to clear audio cache.'),
                        );
                        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{handles_base_uri});
                    }
                    last SWITCH;
                };
                # default
            } # SWITCH

            if ($file_result->handle->name eq 'music_on_hold' && !$file_result->set->contract_id) {
                $target_codec = 'PCMA';
                $filename =~ s/\.[^.]+$/.pcma/;
            }

            try {
                $soundfile = NGCP::Panel::Utils::Sounds::transcode_file(
                    $upload->tempname, 'WAV', $target_codec);
            } catch ($e) {
                NGCP::Panel::Utils::Message::error(
                    c     => $c,
                    log   => 'Transcoding audio file failed',
                    desc  => $c->loc('Transcoding audio file failed'),
                );
                NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{handles_base_uri});
            }
           
            try {
                $file_result->update({
                    loopplay => $form->values->{loopplay},
                    filename => $filename,
                    data => $soundfile,
                    codec => $target_codec,
                });
                NGCP::Panel::Utils::Message::info(
                    c    => $c,
                    desc => $c->loc('Sound handle successfully uploaded'),
                );
            } catch($e) {
                NGCP::Panel::Utils::Message::error(
                    c     => $c,
                    error => $e,
                    desc  => $c->loc('Failed to update uploaded sound handle'),
                );
            }
        } else {
            try {
                $file_result->update({
                    loopplay => $form->values->{loopplay},
                });
                NGCP::Panel::Utils::Message::info(
                    c    => $c,
                    desc => $c->loc('Sound handle successfully updated'),
                );
            } catch($e) {
                NGCP::Panel::Utils::Message::error(
                    c     => $c,
                    error => $e,
                    desc  => $c->loc('Failed to update sound handle'),
                );
            }
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{handles_base_uri});
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
    return;
}

sub handles_delete :Chained('handles_base') :PathPart('delete') {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{file_result}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{file_result}->get_inflated_columns },
            desc => $c->loc('Sound handle successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            error => $e,
            desc  => $c->loc('Failed to delete sound handle'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{handles_base_uri});
    return;
}

sub handles_download :Chained('handles_base') :PathPart('download') :Args(0) {
    my ($self, $c) = @_;
    
    my $file = $c->stash->{file_result};
    my $filename = $file->filename;
    $filename =~ s/\.\w+$/.wav/;
    my $data;

    if($file->codec ne 'WAV') {
        try {
            $data = NGCP::Panel::Utils::Sounds::transcode_data(
                $file->data, $file->codec, 'WAV');
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to transcode audio file'),
            );
            NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{handles_base_uri});
        }
    } else {
        $data = $file->data;
    }
    
    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $filename . '"');
    $c->response->content_type('audio/x-wav');
    $c->response->body($data);
    return;
}

sub handles_load_default :Chained('handles_list') :PathPart('loaddefault') :Args(0) {
    my ($self, $c) = @_;
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::Sound::LoadDefault->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => {},
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    
    if($posted && $form->validated) {
        my $lang = $form->params->{language};
        my $base = "/var/lib/ngcp-soundsets";
        my $set_id = $c->stash->{set_result}->id;
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                foreach my $h($c->stash->{handles_rs}->all) {
                    my $hname = $h->get_column("handlename");
                    my @paths = (
                        "$base/system/$lang/$hname.wav",
                        "$base/customer/$lang/$hname.wav",
                        "/var/lib/asterisk/sounds/$lang/digits/$hname.wav",
                    );
                    my $path;
                    foreach my $p(@paths) {
                        if(-f $p) {
                            $path = $p;
                            last;
                        }
                    }
                    next unless(defined $path);

                    my $handle_id = $h->get_column("handleid");
                    my $file_id = $h->get_column("fileid");
                    my $fres;
                    my $fname = basename($path);
                    if(defined $file_id) {
                        if($form->params->{override}) {
                            $c->log->debug("override $path as $hname for existing id $file_id");
                            my $data;
                            if(!$c->stash->{set_result}->contract_id && 
                               grep {/^$hname$/} (qw/music_on_hold/)) {

                                $fname =~ s/\.wav$/.pcma/;
                                $data = NGCP::Panel::Utils::Sounds::transcode_file(
                                    $path, 'WAV', 'PCMA');
                            } else {
                                $data = read_file($path);
                            }

                            $fres = $schema->resultset('voip_sound_files')->find($file_id);
                            $fres->update({
                                    filename => $fname,
                                    data => $data,
                                    loopplay => $form->params->{loopplay} ? 1 : 0,
                                });
                        } else {
                            $c->log->debug("skip $path as $hname exists via id $file_id and override is not set");
                        }
                    } else {
                        $c->log->debug("inserting $path as $hname with new id");

                        my $codec = 'WAV';
                        my $data;
                        if(!$c->stash->{set_result}->contract_id && 
                           grep {/^$hname$/} (qw/music_on_hold/)) {

                            $fname =~ s/\.wav$/.pcma/;
                            $codec = 'PCMA';
                            $data = NGCP::Panel::Utils::Sounds::transcode_file(
                                $path, 'WAV', $codec);
                        } else {
                            $data = read_file($path);
                        }

                        $fres = $schema->resultset('voip_sound_files')
                            ->create({
                                filename => $fname,
                                data => $data,
                                handle_id => $handle_id,
                                set_id => $set_id,
                                loopplay => $form->params->{loopplay} ? 1 : 0,
                                codec => $codec,
                            });
                    }

                    next unless defined($fres);

                    SWITCH: for ($fres->handle->group->name) {
                        /^calling_card$/ && do {
                            NGCP::Panel::Utils::Sems::clear_audio_cache($c, "appserver", $fres->set_id, $fres->handle->name);
                            last SWITCH;
                        };
                        /^(pbx|music_on_hold|voucher_recharge|play_balance|conference|digits)$/ && do {
                            my $service;
                            if(!$fres->set->contract_id && $_ ne "pbx") {
                                # app server doesn't know about pbx sets, skip them
                                $service = "appserver";
                                NGCP::Panel::Utils::Sems::clear_audio_cache($c, $service, $fres->set_id, $fres->handle->name);
                            } else {
                                $service = "pbx";
                                NGCP::Panel::Utils::Sems::clear_audio_cache($c, $service, $fres->set_id, $fres->handle->name);
                            }
                            last SWITCH;
                        };
                    }
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Sound set successfully loaded with default files.'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to load default sound files.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{handles_base_uri});
        return;
    }

    $c->stash(form => $form);
    $c->stash(edit_default_flag => 1);
    return;
}


__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
