package NGCP::Panel::Controller::SubscriberProfile;
use Sipwise::Base;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::SubscriberProfile::Admin;
use NGCP::Panel::Form::SubscriberProfile::Reseller;
use NGCP::Panel::Form::SubscriberProfile::Clone;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;

sub auto {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub profile_list :Chained('/') :PathPart('subscriberprofile') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{profiles_rs} = $c->model('DB')->resultset('voip_subscriber_profiles');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $c->stash->{profiles_rs} = $c->stash->{profiles_rs}->search({
            reseller_id => $c->user->reseller_id
        });
    } else {
        $c->stash->{profiles_rs} = $c->stash->{profiles_rs}->search({
            reseller_id => $c->user->voip_subscriber->contract->contact->reseller_id,
        });
    }

    $c->stash->{profile_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'description', search => 1, title => $c->loc('Description') },
    ]);
    
    $c->stash(template => 'subprofile/list.tt');
}

sub root :Chained('profile_list') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
}

sub ajax :Chained('profile_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{profiles_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{profile_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub base :Chained('profile_list') :PathPart('') :CaptureArgs(1) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c, $profile_id) = @_;

    unless($profile_id && $profile_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Invalid subscriber profile id detected',
            desc  => $c->loc('Invalid subscriber profile id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/rewrite'));
    }

    my $res = $c->stash->{profiles_rs}->find($profile_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Subscriber profile does not exist',
            desc  => $c->loc('Subscriber profile does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }
    $c->stash(profile_result => $res);
}

sub create :Chained('profile_list') :PathPart('create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::SubscriberProfile::Admin->new(ctx => $c);
        $form->create_structure($form->field_names);
    } else {
        $form = NGCP::Panel::Form::SubscriberProfile::Reseller->new(ctx => $c);
        $form->create_structure($form->field_names);
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
                    $reseller_id = $form->values->{reseller}{id};
                } else {
                    $reseller_id = $c->user->reseller_id;
                }
                delete $form->values->{reseller};
                my $name = delete $form->values->{name};
                my $desc = delete $form->values->{description};
                my $profile = $c->stash->{profiles_rs}->create({
                    reseller_id => $reseller_id,
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

                delete $c->session->{created_objects}->{reseller};
            });
            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully created')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create subscriber profile.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub edit :Chained('base') :PathPart('edit') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $profile = $c->stash->{profile_result};
    my $posted = ($c->request->method eq 'POST');
    my $params = { $profile->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = $params->merge($c->session->{created_objects});
    foreach my $old_attr($profile->profile_attributes->all) {
        $params->{$old_attr->attribute->attribute} = $old_attr->attribute->id;
    }
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::SubscriberProfile::Admin->new(ctx => $c);
        $form->create_structure($form->field_names);
    } else {
        $form = NGCP::Panel::Form::SubscriberProfile::Reseller->new(ctx => $c);
        $form->create_structure($form->field_names);
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
                    $reseller_id = $form->values->{reseller}{id};
                } else {
                    $reseller_id = $c->user->reseller_id;
                }
                delete $form->values->{reseller};
                my $name = delete $form->values->{name};
                my $desc = delete $form->values->{description};
                unless($name eq $profile->name && $desc eq $profile->description) {
                    $profile->update({
                        name => $name,
                        description => $desc,
                    });
                }

                # TODO: reuse attributes for efficiency reasons?
                $profile->profile_attributes->delete_all;
              
                # TODO: should we rather take the name and load the id from db,
                # instead of trusting the id coming from user input?
                foreach my $attr(keys %{ $form->values }) {
                    next unless($form->values->{$attr});
                    $profile->profile_attributes->create({
                        attribute_id => $form->values->{$attr},
                    });
                }

                delete $c->session->{created_objects}->{reseller};
            });
            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully updated')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update subscriber profile.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{profile_result}->delete;
        $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully deleted')}]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete subscriber profile.'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
}

sub clone :Chained('base') :PathPart('clone') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = { $c->stash->{profile_result}->get_inflated_columns };
    $params = $params->merge($c->session->{created_objects});
    my $form = NGCP::Panel::Form::SubscriberProfile::Clone->new;
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
                my $new_profile = $c->stash->{profiles_rs}->create({
                    %{ $form->values },
                    reseller_id => $c->stash->{profile_result}->reseller_id,
                });

                my @old_attributes = $c->stash->{profile_result}->profile_attributes->all;
                for my $attr (@old_attributes) {
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
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
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
