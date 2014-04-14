package NGCP::Panel::Controller::SubscriberProfile;
use Sipwise::Base;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::SubscriberProfile::CatalogAdmin;
use NGCP::Panel::Form::SubscriberProfile::CatalogReseller;
use NGCP::Panel::Form::SubscriberProfile::Profile;
use NGCP::Panel::Form::SubscriberProfile::CatalogClone;
use NGCP::Panel::Form::SubscriberProfile::ProfileClone;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;

sub auto {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub catalog_list :Chained('/') :PathPart('subscriberprofile') :CaptureArgs(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ( $self, $c ) = @_;

    $c->stash->{cat_rs} = $c->model('DB')->resultset('voip_subscriber_profile_catalogs');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $c->stash->{cat_rs} = $c->stash->{cat_rs}->search({
            reseller_id => $c->user->reseller_id
        });
    } else {
        $c->stash->{cat_rs} = $c->stash->{cat_rs}->search({
            reseller_id => $c->user->voip_subscriber->contract->contact->reseller_id,
        });
    }

    $c->stash->{cat_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'description', search => 1, title => $c->loc('Description') },
    ]);
    
    $c->stash(template => 'subprofile/cat_list.tt');
}

sub catalog_root :Chained('catalog_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub catalog_ajax :Chained('catalog_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{cat_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{cat_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub catalog_base :Chained('catalog_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $cat_id) = @_;

    unless($cat_id && $cat_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Invalid subscriber profile catalog id detected',
            desc  => $c->loc('Invalid subscriber profile catalog id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }

    my $res = $c->stash->{cat_rs}->find($cat_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Subscriber profile catalog does not exist',
            desc  => $c->loc('Subscriber profile catalog does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }
    $c->stash(cat => $res);
}

sub catalog_create :Chained('catalog_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::SubscriberProfile::CatalogAdmin->new;
    } else {
        $form = NGCP::Panel::Form::SubscriberProfile::CatalogReseller->new;
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
                $c->stash->{cat_rs}->create($form->values);
              
                delete $c->session->{created_objects}->{reseller};
            });
            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile catalog successfully created')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create subscriber profile catalog.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub catalog_edit :Chained('catalog_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $cat = $c->stash->{cat};
    my $posted = ($c->request->method eq 'POST');
    my $params = { $cat->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = $params->merge($c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::SubscriberProfile::CatalogAdmin->new;
    } else {
        $form = NGCP::Panel::Form::SubscriberProfile::CatalogReseller->new;
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
                $cat->update($form->values);
              
                delete $c->session->{created_objects}->{reseller};
            });
            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile catalog successfully updated')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update subscriber profile catalog.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub catalog_delete :Chained('catalog_base') :PathPart('delete') {
    my ($self, $c) = @_;
    
    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub{
            $schema->resultset('provisioning_voip_subscribers')->search({
                profile_catalog_id => $c->stash->{cat}->id
            })->update({
                profile_catalog_id => undef,
                profile_id => undef,
            });
            $c->stash->{cat}->voip_subscriber_profiles->delete;
            $c->stash->{cat}->delete;
        });
        $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile catalog successfully deleted')}]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete subscriber profile catalog.'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
}

sub catalog_clone :Chained('catalog_base') :PathPart('clone') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = { $c->stash->{cat}->get_inflated_columns };
    $params = $params->merge($c->session->{created_objects});
    my $form = NGCP::Panel::Form::SubscriberProfile::CatalogClone->new;
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
                my $new_cat = $schema->resultset('voip_subscriber_profile_catalogs')->create({
                    %{ $form->values },
                    reseller_id => $c->stash->{cat}->reseller_id,
                });
                foreach my $prof($c->stash->{cat}->voip_subscriber_profiles->all) {
                    my $old = { $prof->get_inflated_columns };
                    foreach(qw/id catalog_id/) {
                        delete $old->{$_};
                    }
                    my $new_prof = $new_cat->voip_subscriber_profiles->create($old);
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


sub profile_list :Chained('catalog_base') :PathPart('profile') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{profile_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'description', search => 1, title => $c->loc('Description') },
    ]);
    
    $c->stash(template => 'subprofile/profile_list.tt');
}

sub profile_root :Chained('profile_list') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
}

sub profile_ajax :Chained('profile_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{cat}->voip_subscriber_profiles;
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

    my $res = $c->stash->{cat}->voip_subscriber_profiles->find($profile_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Subscriber profile does not exist',
            desc  => $c->loc('Subscriber profile does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriberprofile/profile_root', [$c->stash->{cat}->id]));
    }
    $c->stash(
        profile => $res,
        close_target => $c->uri_for_action('/subscriberprofile/profile_root', [$c->stash->{cat}->id]),
    );
}

sub profile_create :Chained('profile_list') :PathPart('create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    my $form = NGCP::Panel::Form::SubscriberProfile::Profile->new(ctx => $c);
    $form->create_structure($form->field_names);
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
                my $name = delete $form->values->{name};
                my $desc = delete $form->values->{description};
                my $profile = $c->stash->{cat}->voip_subscriber_profiles->create({
                    name => $name,
                    description => $desc,
                });
              
                # TODO: should we rather take the name and load the id from db,
                # instead of trusting the id coming from user input?
                foreach my $attr(keys %{ $form->values }) {
                    next unless($form->values->{$attr});
                    $profile->profile_attributes->create({
                        attribute_id => $form->values->{$attr},
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
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriberprofile/profile_root', [$c->stash->{cat}->id]));
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
        $params->{$old_attr->attribute->attribute} = $old_attr->attribute->id;
    }
    my $form = NGCP::Panel::Form::SubscriberProfile::Profile->new(ctx => $c);
    $form->create_structure($form->field_names);
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
                my $name = delete $form->values->{name};
                my $desc = delete $form->values->{description};
                unless($name eq $profile->name && $desc eq $profile->description) {
                    $profile->update({
                        name => $name,
                        description => $desc,
                    });
                }

                # TODO: reuse attributes for efficiency reasons?
                $profile->profile_attributes->delete;
              
                # TODO: should we rather take the name and load the id from db,
                # instead of trusting the id coming from user input?
                foreach my $attr(keys %{ $form->values }) {
                    next unless($form->values->{$attr});
                    $profile->profile_attributes->create({
                        attribute_id => $form->values->{$attr},
                    });
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
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriberprofile/profile_root', [$c->stash->{cat}->id]));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub profile_delete :Chained('profile_base') :PathPart('delete') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    
    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub{
            $schema->resultset('provisioning_voip_subscribers')->search({
                profile_id => $c->stash->{profile}->id,
            })->update({
                # TODO: set this to another profile, or reject deletion if profile is in use
                profile_id => undef,
            });
            $c->stash->{profile}->delete;
        });
        $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully deleted')}]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete subscriber profile.'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriberprofile/profile_root', [$c->stash->{cat}->id]));
}

sub profile_clone :Chained('profile_base') :PathPart('clone') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

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
                my $new_profile = $c->stash->{cat}->voip_subscriber_profiles->create({
                    %{ $form->values },
                    catalog_id => $c->stash->{cat}->id,
                });

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
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/subscriberprofile/profile_root', [$c->stash->{cat}->id]));
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
