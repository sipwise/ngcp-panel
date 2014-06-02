package NGCP::Panel::Controller::SubscriberProfile;
use Sipwise::Base;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::SubscriberProfile::SetAdmin;
use NGCP::Panel::Form::SubscriberProfile::SetReseller;
use NGCP::Panel::Form::SubscriberProfile::Profile;
use NGCP::Panel::Form::SubscriberProfile::SetCloneReseller;
use NGCP::Panel::Form::SubscriberProfile::SetCloneAdmin;
use NGCP::Panel::Form::SubscriberProfile::ProfileClone;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;

sub auto :Private{
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub set_list :Chained('/') :PathPart('subscriberprofile') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{set_rs} = $c->model('DB')->resultset('voip_subscriber_profile_sets');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $c->stash->{set_rs} = $c->stash->{set_rs}->search({
            reseller_id => $c->user->reseller_id
        });
    } else {
        $c->stash->{set_rs} = $c->stash->{set_rs}->search({
            reseller_id => $c->user->voip_subscriber->contract->contact->reseller_id,
        });
    }

    $c->stash->{set_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'description', search => 1, title => $c->loc('Description') },
    ]);
    
    $c->stash(template => 'subprofile/set_list.tt');
}

sub set_root :Chained('set_list') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
}

sub set_ajax :Chained('set_list') :PathPart('ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{set_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{set_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub set_ajax_reseller :Chained('set_list') :PathPart('ajax/reseller') :Args(1) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c, $reseller_id) = @_;
    my $rs = $c->stash->{set_rs};
    $rs = $rs->search({
        reseller_id => $reseller_id,
    });
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{set_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub set_base :Chained('set_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;

    unless($set_id && $set_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Invalid subscriber profile set id detected',
            desc  => $c->loc('Invalid subscriber profile set id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }

    my $res = $c->stash->{set_rs}->find($set_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Subscriber profile set does not exist',
            desc  => $c->loc('Subscriber profile set does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }
    $c->stash(set => $res);
}

sub set_create :Chained('set_list') :PathPart('create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if($c->user->roles eq "reseller" && !$c->config->{profile_sets}->{reseller_edit});

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::SubscriberProfile::SetAdmin->new;
    } else {
        $form = NGCP::Panel::Form::SubscriberProfile::SetReseller->new;
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
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $reseller_id;
                if($c->user->roles eq "admin") {
                    $form->values->{reseller_id} = $form->values->{reseller}{id};
                } else {
                    $form->values->{reseller_id} = $c->user->reseller_id;
                }
                delete $form->values->{reseller};
                $c->stash->{set_rs}->create($form->values);
              
                delete $c->session->{created_objects}->{reseller};
            });
            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile set successfully created')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create subscriber profile set.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub set_edit :Chained('set_base') :PathPart('edit') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if($c->user->roles eq "reseller" && !$c->config->{profile_sets}->{reseller_edit});

    my $set = $c->stash->{set};
    my $posted = ($c->request->method eq 'POST');
    my $params = { $set->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = $params->merge($c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::SubscriberProfile::SetAdmin->new;
    } else {
        $form = NGCP::Panel::Form::SubscriberProfile::SetReseller->new;
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
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $reseller_id;
                if($c->user->roles eq "admin") {
                    $form->values->{reseller_id} = $form->values->{reseller}{id};
                } else {
                    $form->values->{reseller_id} = $c->user->reseller_id;
                }
                delete $form->values->{reseller};
                $set->update($form->values);
              
                delete $c->session->{created_objects}->{reseller};
            });
            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile set successfully updated')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update subscriber profile set.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub set_delete :Chained('set_base') :PathPart('delete') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if($c->user->roles eq "reseller" && !$c->config->{profile_sets}->{reseller_edit});
    
    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub{
            $schema->resultset('provisioning_voip_subscribers')->search({
                profile_set_id => $c->stash->{set}->id
            })->update({
                profile_set_id => undef,
                profile_id => undef,
            });
            $c->stash->{set}->voip_subscriber_profiles->delete;
            $c->stash->{set}->delete;
        });
        $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile set successfully deleted')}]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete subscriber profile set.'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
}

sub set_clone :Chained('set_base') :PathPart('clone') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if($c->user->roles eq "reseller" && !$c->config->{profile_sets}->{reseller_edit});

    my $posted = ($c->request->method eq 'POST');
    my $params = { $c->stash->{set}->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = $params->merge($c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::SubscriberProfile::SetCloneAdmin->new;
    } else {
        $form = NGCP::Panel::Form::SubscriberProfile::SetCloneReseller->new;
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $reseller_id;
                if($c->user->roles eq "admin") {
                    $reseller_id = $form->params->{reseller}{id};
                } else {
                    $reseller_id = $c->stash->{set}->reseller_id,
                }
                delete $form->params->{reseller};
                my $new_set = $schema->resultset('voip_subscriber_profile_sets')->create({
                    %{ $form->values },
                    reseller_id => $c->stash->{set}->reseller_id,
                });
                foreach my $prof($c->stash->{set}->voip_subscriber_profiles->all) {
                    my $old = { $prof->get_inflated_columns };
                    foreach(qw/id set_id/) {
                        delete $old->{$_};
                    }
                    my $new_prof = $new_set->voip_subscriber_profiles->create($old);
                    my @old_attributes = $prof->profile_attributes->all;
                    foreach my $attr (@old_attributes) {
                        $new_prof->profile_attributes->create({
                            attribute_id => $attr->attribute_id,
                        });
                    }
                }
            });

            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully cloned')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to clone subscriber profile.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
    $c->stash(clone_flag => 1);
}


sub profile_list :Chained('set_base') :PathPart('profile') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{profile_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'profile_set.name', search => 0, title => $c->loc('Profile Set') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'description', search => 1, title => $c->loc('Description') },
        { name => 'set_default', search => 0, title => $c->loc('Default') },
    ]);
    
    $c->stash(template => 'subprofile/profile_list.tt');
}

sub profile_root :Chained('profile_list') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
}

sub profile_ajax :Chained('profile_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{set}->voip_subscriber_profiles;
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{profile_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub profile_base :Chained('profile_list') :PathPart('') :CaptureArgs(1) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c, $profile_id) = @_;

    unless($profile_id && $profile_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Invalid subscriber profile id detected',
            desc  => $c->loc('Invalid subscriber profile id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/rewrite'));
    }

    my $res = $c->stash->{set}->voip_subscriber_profiles->find($profile_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Subscriber profile does not exist',
            desc  => $c->loc('Subscriber profile does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriberprofile/profile_root', [$c->stash->{set}->id]));
    }
    $c->stash(
        profile => $res,
        close_target => $c->uri_for_action('/subscriberprofile/profile_root', [$c->stash->{set}->id]),
    );
}

sub profile_create :Chained('profile_list') :PathPart('create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if($c->user->roles eq "reseller" && !$c->config->{profile_sets}->{reseller_edit});

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    my $form = NGCP::Panel::Form::SubscriberProfile::Profile->new(ctx => $c);
    #$form->create_structure($form->field_names);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $attributes = delete $form->values->{attribute};
                if($form->values->{set_default}) {
                    # new profile is default, clear any previous default profiles
                    $c->stash->{set}->voip_subscriber_profiles->update({
                        set_default => 0,
                    });
                } elsif(!$c->stash->{set}->voip_subscriber_profiles->search({
                      set_default => 1,
                  })->count) {

                  # no previous default profile, make this one default
                  $form->values->{set_default} = 1;
                }
                my $profile = $c->stash->{set}->voip_subscriber_profiles->create($form->values);
              
                # TODO: should we rather take the name and load the id from db,
                # instead of trusting the id coming from user input?
                foreach my $attr(keys %{ $attributes }) {
                    next unless($attributes->{$attr});
                    $profile->profile_attributes->create({
                        attribute_id => $attributes->{$attr},
                    });
                }
            });
            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully created')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create subscriber profile.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriberprofile/profile_root', [$c->stash->{set}->id]));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub profile_edit :Chained('profile_base') :PathPart('edit') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $profile = $c->stash->{profile};
    my $posted = ($c->request->method eq 'POST');
    my $params = { $profile->get_inflated_columns };
    foreach my $old_attr($profile->profile_attributes->all) {
        $params->{attribute}{$old_attr->attribute->attribute} = $old_attr->attribute->id;
    }
    my $form = NGCP::Panel::Form::SubscriberProfile::Profile->new(ctx => $c);
    #$form->create_structure($form->field_names);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $attributes = delete $form->values->{attribute};
                if($form->values->{set_default}) {
                    # new profile is default, clear any previous default profiles
                    $c->stash->{set}->voip_subscriber_profiles->search({
                        id => { '!=' => $profile->id },
                    })->update({
                        set_default => 0,
                    });
                } elsif(!$c->stash->{set}->voip_subscriber_profiles->search({
                      set_default => 1,
                  })->count) {

                  # no previous default profile, make this one default
                  $form->values->{set_default} = 1;
                }
                if($c->user->roles eq "reseller" && !$c->config->{profile_sets}->{reseller_edit}) {
                    # only allow generic fields to be updated
                    delete $form->values->{attribute};
                }

                $profile->update($form->values);


                my %old_attributes = map { $_ => 1 } 
                    $profile->profile_attributes->get_column('attribute_id')->all;

                # TODO: reuse attributes for efficiency reasons?
                $profile->profile_attributes->delete;
              
                # TODO: should we rather take the name and load the id from db,
                # instead of trusting the id coming from user input?
                foreach my $attr(keys %{ $attributes }) {
                    my $id = $attributes->{$attr};
                    next unless($id);
                    # mark as seen, so later we can unprovision the remaining ones,
                    # which are the ones not set here
                    delete $old_attributes{$id};
                    $profile->profile_attributes->create({
                        attribute_id => $id,
                    });
                }

                # go over remaining attributes (those which were set before but are not set anymore)
                # and clear them from usr-preferences
                if(keys %old_attributes) {
                    my $cfs = $c->model('DB')->resultset('voip_preferences')->search({
                        id => { -in => [ keys %old_attributes ] },
                        attribute => { -in => [qw/cfu cfb cft cfna/] },
                    });
                    my @subs = $c->model('DB')->resultset('provisioning_voip_subscribers')
                        ->search({
                            profile_id => $profile->id,
                        })->all;
                    foreach my $sub(@subs) {
                        $sub->voip_usr_preferences->search({
                            attribute_id => { -in => [ keys %old_attributes ] },
                        })->delete;
                        $sub->voip_cf_mappings->search({
                            type => { -in => [ map { $_->attribute } $cfs->all ] },
                        })->delete;
                    }
                }

            });
            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully updated')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update subscriber profile.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriberprofile/profile_root', [$c->stash->{set}->id]));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub profile_delete :Chained('profile_base') :PathPart('delete') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if($c->user->roles eq "reseller" && !$c->config->{profile_sets}->{reseller_edit});
    
    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub{
            my $profile = $c->stash->{profile};
            $schema->resultset('provisioning_voip_subscribers')->search({
                profile_id => $profile->id,
            })->update({
                # TODO: set this to another profile, or reject deletion if profile is in use
                profile_id => undef,
            });
            if($profile->set_default && $c->stash->{set}->voip_subscriber_profiles->count > 1) {
                $c->stash->{set}->voip_subscriber_profiles->search({
                    id => { '!=' => $profile->id },
                })->first->update({
                      set_default => 1,
                });
            }
            $profile->delete;
        });
        $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully deleted')}]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete subscriber profile.'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriberprofile/profile_root', [$c->stash->{set}->id]));
}

sub profile_clone :Chained('profile_base') :PathPart('clone') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if($c->user->roles eq "reseller" && !$c->config->{profile_sets}->{reseller_edit});

    my $posted = ($c->request->method eq 'POST');
    my $params = { $c->stash->{profile}->get_inflated_columns };
    $params = $params->merge($c->session->{created_objects});
    my $form = NGCP::Panel::Form::SubscriberProfile::ProfileClone->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->values->{set_default} = 0;
                $form->values->{set_id} = $c->stash->{set}->id;
                my $new_profile = $c->stash->{set}->voip_subscriber_profiles->create($form->values);
                my @old_attributes = $c->stash->{profile}->profile_attributes->all;
                foreach my $attr (@old_attributes) {
                    $new_profile->profile_attributes->create({
                        attribute_id => $attr->attribute_id,
                    });
                }
            });

            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully cloned')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to clone subscriber profile.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriberprofile/profile_root', [$c->stash->{set}->id]));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
    $c->stash(clone_flag => 1);
}


__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

NGCP::Panel::Controller::SubscriberProfile - Manage Subscriber Profiles

=head1 DESCRIPTION

Show/Edit/Create/Delete Subscriber Profiles, allowing to define which user preferences
an end user can actually view/edit via the CSC.

=head1 AUTHOR

Andreas Granig C<< <agranig@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
