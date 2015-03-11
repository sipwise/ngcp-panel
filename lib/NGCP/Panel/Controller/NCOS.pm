package NGCP::Panel::Controller::NCOS;
use Sipwise::Base;

BEGIN { use parent 'Catalyst::Controller'; }

use NGCP::Panel::Form::NCOS::ResellerLevel;
use NGCP::Panel::Form::NCOS::AdminLevel;
use NGCP::Panel::Form::NCOS::Pattern;
use NGCP::Panel::Form::NCOS::LocalAC;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Datatables;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub levels_list :Chained('/') :PathPart('ncos') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $dispatch_to = '_levels_resultset_' . $c->user->roles;
    my $levels_rs = $self->$dispatch_to($c);
    $c->stash(levels_rs => $levels_rs);

    $c->stash->{level_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'level', search => 1, title => $c->loc('Level Name') },
        { name => 'mode', search => 1, title => $c->loc('Mode') },
        { name => 'description', search => 1, title => $c->loc('Description') },
    ]);

    $c->stash(template => 'ncos/list.tt');
}

sub _levels_resultset_admin {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('ncos_levels');
    return $rs;
}

sub _levels_resultset_reseller {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('admins')
        ->find($c->user->id)->reseller->ncos_levels;
    return $rs;
}

sub root :Chained('levels_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('levels_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{levels_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{level_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub base :Chained('levels_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $level_id) = @_;

    unless($level_id && is_int($level_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid NCOS level id detected',
            desc  => $c->loc('Invalid NCOS level id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for);
    }

    my $res = $c->stash->{levels_rs}->find($level_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'NCOS level does not exist',
            desc  => $c->loc('NCOS level does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for);
    }
    $c->stash(level_result => $res);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $level = $c->stash->{level_result};
    my $params = { $level->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::NCOS::AdminLevel->new;
    } else {
        $form = NGCP::Panel::Form::NCOS::ResellerLevel->new;
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
            $form->values->{reseller_id} = $form->values->{reseller}{id};
            delete $form->values->{reseller};
            $level->update($form->values);
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('NCOS level successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update NCOS level'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/ncos'));
    }

    $c->stash(
        close_target => $c->uri_for,
        edit_flag => 1,
        form => $form,
    );
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            for my $pref(qw/adm_ncos_id subadm_ncos_id ncos_id adm_cf_ncos_id/) {
                my $rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, attribute => $pref,
                );
                next unless($rs);
                $rs = $rs->search({
                    value => $c->stash->{level_result}->id,
                });
                $rs->delete;
            }
            $c->stash->{level_result}->delete;
        });
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            desc => $c->loc('NCOS level successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete NCOS level'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for);
}

sub create :Chained('levels_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::NCOS::AdminLevel->new;
    } else {
        $form = NGCP::Panel::Form::NCOS::ResellerLevel->new;
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
            my $level = $c->stash->{levels_rs};
            unless($c->user->is_superuser) {
                $form->values->{reseller}{id} = $c->user->reseller_id;
            }
            $level->create($form->values);
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('NCOS level successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create NCOS level'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/ncos'));
    }

    $c->stash(
        close_target => $c->uri_for,
        create_flag => 1,
        form => $form,
    );
}

sub pattern_list :Chained('base') :PathPart('pattern') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $pattern_rs = $c->stash->{level_result}->ncos_pattern_lists;
    $c->stash(pattern_rs => $pattern_rs);
    $c->stash(pattern_base_uri =>
        $c->uri_for_action("/ncos/pattern_root", [$c->req->captures->[0]]));

    $c->stash->{pattern_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'pattern', search => 1, title => $c->loc('Pattern') },
        { name => 'description', search => 1, title => $c->loc('Description') },
    ]);
    
    $c->stash(local_ac_checked => $c->stash->{level_result}->local_ac,
              template         => 'ncos/pattern_list.tt');
}

sub pattern_root :Chained('pattern_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub pattern_ajax :Chained('pattern_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{pattern_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{pattern_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub pattern_base :Chained('pattern_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $pattern_id) = @_;

    unless($pattern_id && is_int($pattern_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid NCOS pattern id detected',
            desc  => $c->loc('Invalid NCOS pattern id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{pattern_base_uri});
    }

    my $res = $c->stash->{pattern_rs}->find($pattern_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'NCOS pattern does not exist',
            desc  => $c->loc('NCOS pattern does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{pattern_base_uri});
    }
    $c->stash(pattern_result => $res);
}

sub pattern_edit :Chained('pattern_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::NCOS::Pattern->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $c->stash->{pattern_result},
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $c->stash->{pattern_result}->update($form->values);
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                data => { $c->stash->{pattern_result}->get_inflated_columns },
                desc => $c->loc('NCOS pattern successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update NCOS pattern'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{pattern_base_uri});
    }

    $c->stash(
        close_target => $c->stash->{pattern_base_uri},
        form => $form,
        edit_flag => 1
    );
}

sub pattern_delete :Chained('pattern_base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{pattern_result}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{pattern_result}->get_inflated_columns },
            desc => $c->loc('NCOS pattern successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete NCOS pattern'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{pattern_base_uri});
}

sub pattern_create :Chained('pattern_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::NCOS::Pattern->new;
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
            $c->stash->{pattern_rs}->create($form->values);
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('NCOS pattern successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create NCOS pattern'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{pattern_base_uri});
    }

    $c->stash(
        close_target => $c->stash->{pattern_base_uri},
        form => $form,
        create_flag => 1
    );
}

sub pattern_edit_local_ac :Chained('pattern_list') :PathPart('edit_local_ac') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::NCOS::LocalAC->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $c->stash->{level_result},
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $c->stash->{level_result}->update($form->values);
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('NCOS level setting successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update NCOS level setting'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{pattern_base_uri});
    }

    $c->stash(
        close_target => $c->stash->{pattern_base_uri},
        form => $form,
        edit_flag => 1
    );
}


__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

NGCP::Panel::Controller::NCOS - manage NCOS levels/patterns

=head1 DESCRIPTION

Show/Edit/Create/Delete NCOS Levels.

Show/Edit/Create/Delete Number patterns.

=head1 METHODS

=head2 auto

Grants access to admin and reseller role.

=head2 levels_list

Basis for billing.ncos_levels.

=head2 root

Display NCOS Levels through F<ncos/list.tt> template.

=head2 ajax

Get billing.ncos_levels from db and output them as JSON.
The format is meant for parsing with datatables.

=head2 base

Fetch a billing.ncos_levels row from the database by its id.
The resultset is exported to stash as "level_result".

=head2 edit

Show a modal to edit the NCOS Level determined by L</base>.

=head2 delete

Delete the NCOS Level determined by L</base>.

=head2 create

Show modal to create a new NCOS Level using the form
L<NGCP::Panel::Form::NCOSLevel>.

=head2 pattern_list

Basis for billing.ncos_pattern_list.
Fetches all patterns related to the level determined by L</base> and stashes
the resultset under "pattern_rs".

=head2 pattern_root

Display NCOS Number Patterns through F<ncos/pattern_list.tt> template.

=head2 pattern_ajax

Get patterns from db using the resultset from L</pattern_list> and
output them as JSON. The format is meant for parsing with datatables.

=head2 pattern_base

Fetch a billing.ncos_pattern_list row from the database by its id.
The resultset is exported to stash as "pattern_result".

=head2 pattern_edit

Show a modal to edit the Number Pattern determined by L</pattern_base>.

=head2 pattern_delete

Delete the Number Pattern determined by L</pattern_base>.

=head2 pattern_create

Show modal to create a new Number Pattern for the current Level using the form
L<NGCP::Panel::Form::NCOSPattern>.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
