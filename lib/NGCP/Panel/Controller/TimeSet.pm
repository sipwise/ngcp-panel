package NGCP::Panel::Controller::TimeSet;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::TimeSet;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list :Chained('/') :PathPart('timeset') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{timesets_rs} = $c->model('DB')->resultset('voip_time_sets');
    unless($c->user->roles eq "admin") {
        $c->stash->{timesets_rs} = $c->stash->{timesets_rs}->search({
            reseller_id => $c->user->reseller_id
        });
    }
    $c->stash->{timeset_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        $c->user->roles eq "admin"
            ? { name => 'reseller.name', search => 1, title => $c->loc('Reseller') }
            : (),
        { name => 'name', search => 1, title => $c->loc('Name') },
    ]);

    $c->stash(template => 'timeset/list.tt');
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{timesets_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{timeset_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub fieldajax :Chained('list') :PathPart('fieldajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{timesets_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller_id', search => 1, title => $c->loc('Reseller #') },
        { name => 'name', search => 1, title => $c->loc('Name') },
    ]));
    $c->detach( $c->view("JSON") );
}

sub base :Chained('list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $timeset_id) = @_;

    unless($timeset_id && is_int($timeset_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid timeset enry id detected',
            desc  => $c->loc('Invalid timeset entry id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/timeset'));
    }

    my $rs = $c->stash->{timesets_rs}->find($timeset_id);
    unless(defined($rs)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Timeset entry does not exist',
            desc  => $c->loc('Timeset entry does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/timeset'));
    }
    $c->stash(
        timeset => {$rs->get_inflated_columns},
        timeset_rs => $rs
    );
}

sub create :Chained('list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $upload = $c->req->upload('upload');
    my $params = {
        %{$c->request->params},
        upload => $posted ? $upload : undef,
    };
    $params = merge($params, $c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::TimeSet::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::TimeSet::Reseller", $c);
    }
    $form->process(
        posted => $posted,
        params => $params,
        action => $c->uri_for_action('/timeset/create'),
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
            my $resource = $c->forward('timeset_resource',[$form]);
            $c->model('DB')->schema->txn_do( sub {
                NGCP::Panel::Utils::TimeSet::create_timeset(
                    c => $c,
                    resource => $resource,
                );
            });
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Timeset entry successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create timeset entry'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/timeset'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $upload = $c->req->upload('upload');
    my $params = NGCP::Panel::Utils::TimeSet::get_timeset(c => $c, timeset => $c->stash->{timeset_rs});
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params->{upload} = $posted ? $upload : undef;
    $params = merge($params, $c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::TimeSet::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Timeset::Reseller", $c);
    }
    $form->process(
        posted => $posted,
        params => $params,
        item   => $c->stash->{timeset_rs},
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
            $c->model('DB')->schema->txn_do( sub {
                my $resource = $c->forward('timeset_resource',[$form]);
                NGCP::Panel::Utils::TimeSet::update_timesets(
                    c => $c,
                    timeset => $c->stash->{timeset_rs},
                    resource => $resource,
                );
            });
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Timeset entry successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update timeset entry'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/timeset'));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{timeset_rs}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => $c->stash->{timeset},
            desc => $c->loc('Timeset entry successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete timeset entry'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/timeset'));
}


sub timeset_resource :Private {
    my ($self, $c, $form) = @_;

    my $resource = $form->values;
    delete $resource->{upload};
    if($c->user->roles eq "admin") {
        $resource->{reseller_id} = $form->values->{reseller}{id};
        delete $resource->{reseller};
    }  else {
        $resource->{reseller_id} = $c->user->reseller_id;
    }
    if (!$resource->{name}) {
        my( $calendar_parsed ) = NGCP::Panel::Utils::TimeSet::parse_calendar(
            c => $c,
        );
        #we have checked that $name is not empty in the form validation
        $resource->{name} = $calendar_parsed->{name};
    }
    #data will be taken from the request parameters or cache
    ($resource->{times}) = NGCP::Panel::Utils::TimeSet::parse_calendar_events(c => $c);
    return $resource;
}

sub download :Chained('base') :PathPart('download') :Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->model('DB');
    my $data = NGCP::Panel::Utils::TimeSet::get_timeset_icalendar(
        c       => $c,
        timeset => $c->stash->{'timeset_rs'},
        schema  => $schema,
    );
    $c->response->header('Content-Disposition' => 'attachment; filename="'.$c->stash->{timeset}->{name}.'_'.$c->stash->{timeset}->{id}.'.ics"');
    $c->response->content_type('text/calendar');
    $c->response->body($$data);
    return;
}

sub event_list :Chained('base') :PathPart('event') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{events_rs} = $c->stash->{timeset_rs}->time_periods;

    $c->stash->{event_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'time_set_id', search => 1, title => $c->loc('Time Set #') },
        { name => 'comment', search => 1, title => $c->loc('Comment') },
        { name => 'periods_ical.rrule_ical', search => 0, accessor => "ical", title => $c->loc('iCal')},#, literal_sql => '""'
    ]);

    $c->stash(template => 'timeset/event_list.tt');
}

sub event_root :Chained('event_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub event_ajax :Chained('event_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{events_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{event_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub event_create :Chained('event_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{events_rs};
    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::TimeSet::EventAdvanced", $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    if($posted && $form->validated) {
        try {
            my $rrule = $form->custom_get_values();
            $c->model('DB')->schema->txn_do( sub {
                NGCP::Panel::Utils::TimeSet::create_timeset_events(
                    c => $c,
                    timeset => $c->stash->{timeset_rs},
                    events  => [$rrule],
                );
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Event entry successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create event entry'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/event'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub event_base :Chained('event_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $event_id) = @_;

    unless($event_id && is_int($event_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid event entry id detected',
            desc  => $c->loc('Invalid event entry id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/event'));
    }

    my $rs = $c->stash->{events_rs}->find($event_id);
    unless(defined($rs)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Event entry does not exist',
            desc  => $c->loc('Event entry does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/event'));
    }
    $c->stash(
        event => {$rs->get_inflated_columns},
        event_rs => $rs
    );
}

sub event_edit :Chained('event_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{events_rs};
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::TimeSet::EventAdvanced", $c);
    my $params = merge($form->custom_set_values($c->stash->{event}), $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    if($posted && $form->validated) {
        try {
            my $rrule = $form->custom_get_values();
            use irka;
            irka::loglong($rrule);
            $c->model('DB')->schema->txn_do( sub {
                $c->stash->{event_rs}->update($rrule);
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Event entry successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update event entry'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/event'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub event_delete :Chained('event_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{event_rs}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => $c->stash->{timeset},
            desc => $c->loc('Event entry successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete event entry'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/event'));
}

sub event_upload :Chained('event_list') :PathPart('upload') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::TimeSet::EventUpload", $c);
    my $upload = $c->req->upload('upload');
    my $posted = $c->req->method eq 'POST';
    my @params = ( upload => $posted ? $upload : undef, );
    $form->process(
        posted => $posted,
        params => { @params },
        action => $c->uri_for_action('/timeset/event_upload', $c->req->captures),
    );
    if($form->validated) {
        # TODO: check by formhandler?
        unless($upload) {
            NGCP::Panel::Utils::Message::error(
                c    => $c,
                desc => $c->loc('No iCalendar file specified!'),
            );
            $c->response->redirect($c->uri_for($c->stash->{timeset}->{id}, 'event'));
            return;
        }
        if ($c->req->params->{purge_existing}) {
            $c->stash->{'timeset_rs'}->events->delete;
        }
        my $data = $upload->slurp;
        my($events, $fails, $text_success);
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                ( $events, $fails, $text_success ) = NGCP::Panel::Utils::TimeSet::upload(
                    c          => $c,
                    data       => \$data,
                    timeset    => $c->stash->{'timeset_rs'},
                    schema     => $schema,
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
                desc => $c->loc('Failed to upload iCalendar events'),
            );
        }

        $c->response->redirect($c->uri_for($c->stash->{timeset}->{id}, 'event'));
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}
1;
