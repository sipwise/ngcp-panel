package NGCP::Panel::Controller::Lnp;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Datatables;
use NGCP::Panel::Utils::Lnp;
use NGCP::Panel::Utils::MySQL;

use NGCP::Panel::Form::Lnp::Carrier;
use NGCP::Panel::Form::Lnp::Number;
use NGCP::Panel::Form::Lnp::Upload;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list :Chained('/') :PathPart('lnp') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    my $carrier_rs = $c->model('DB')->resultset('lnp_providers');
    $c->stash(carrier_rs => $carrier_rs);
    $c->stash->{carrier_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", "search" => 1, "title" => $c->loc("#") },
        { name => "name", "search" => 1, "title" => $c->loc("Name") },
        { name => "prefix", "search" => 1, "title" => $c->loc("Prefix") },
        { name => "authoritative", "search" => 0, "title" => $c->loc("Authoritative") },
        { name => "skip_rewrite", "search" => 0, "title" => $c->loc("Skip Rewrite") },
        #better leave this out for performance reasons:
        #{ name => "numbers_count", "search" => 0, "title" => $c->loc("#Numbers"),
        #  literal_sql=>"select count(n.id) from `billing`.`lnp_numbers` n where n.`lnp_provider_id` = `me`.`id`" },
    ]);

    my $number_rs = $c->model('DB')->resultset('lnp_numbers');
    $c->stash(number_rs => $number_rs);
    $c->stash->{number_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", "search" => 0, "title" => $c->loc("#") },
        { name => "number", "search" => 1, "title" => $c->loc("Number") },
        { name => "routing_number", "search" => 0, "title" => $c->loc("Routing Number") },
        { name => "lnp_provider.name", "search" => 1, "title" => $c->loc("Carrier") },
        { name => "start", "search" => 0, "title" => $c->loc("Start Date") },
        { name => "end", "search" => 0, "title" => $c->loc("End Date") },
    ]);

    $c->stash(template => 'lnp/list.tt');
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub carrier_ajax :Chained('list') :PathPart('carrier_ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{carrier_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{carrier_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub number_ajax :Chained('list') :PathPart('number_ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{number_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{number_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub carrier_base :Chained('list') :PathPart('carrier') :CaptureArgs(1) {
    my ($self, $c, $carrier_id) = @_;

    unless($carrier_id && is_int($carrier_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $carrier_id },
            desc  => $c->loc('Invalid LNP carrier id detected!'),
        );
        $c->flash(carrier_messages => delete $c->flash->{messages});
        $c->response->redirect($c->uri_for());
        return;
    }

    my $res = $c->stash->{carrier_rs}->find($carrier_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $carrier_id },
            desc  => $c->loc('LNP carrier does not exist!'),
        );
        $c->flash(carrier_messages => delete $c->flash->{messages});
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash(carrier => {$res->get_inflated_columns});
    $c->stash(carrier_result => $res);
}

sub carrier_edit :Chained('carrier_base') :PathPart('edit') {
    my ($self, $c ) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = $c->stash->{carrier};
    $params = merge($params, $c->session->{created_objects});
    $form = NGCP::Panel::Form::Lnp::Carrier->new(ctx => $c);
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
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $c->stash->{carrier_result}->update($form->values);
            });

            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('LNP carrier successfully updated'),
            );
            $c->flash(carrier_messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update LNP carrier'),
            );
            $c->flash(carrier_messages => delete $c->flash->{messages});
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/lnp'));
    }
    $c->stash( 'carrier_edit_flag'      => 1 );
    $c->stash( 'carrier_form'           => $form );
}

sub carrier_create :Chained('list') :PathPart('carrier_create') :Args(0) {
    my ($self, $c) = @_;

    my $schema = $c->model('DB');
    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    $form = NGCP::Panel::Form::Lnp::Carrier->new(ctx => $c);
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
            my $carrier = $c->model('DB')->resultset('lnp_providers')->create($form->values);

            $c->session->{created_objects}->{lnp_provider} = { id => $carrier->id };
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('LNP carrier successfully created'),
            );
            $c->flash(carrier_messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create LNP carrier'),
            );
            $c->flash(carrier_messages => delete $c->flash->{messages});
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/lnp'));
    }

    $c->stash(carrier_create_flag => 1);
    $c->stash(carrier_form => $form);
}

sub carrier_delete :Chained('carrier_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    my $carrier = $c->stash->{carrier_result};

    my $number_count = $carrier->lnp_numbers->count;
    if ($number_count > 0) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc  => $c->loc("LNP numbers still linked to LNP carrier."),
        );
        $c->flash(carrier_messages => delete $c->flash->{messages});
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/lnp'));
        return;
    }

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            $carrier->delete;
        });
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $c->stash->{carrier},
            desc => $c->loc('LNP carrier successfully deleted'),
        );
        $c->flash(carrier_messages => delete $c->flash->{messages});
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $c->stash->{carrier},
            desc  => $c->loc('Failed to delete LNP carrier'),
        );
        $c->flash(carrier_messages => delete $c->flash->{messages});
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/lnp'));
}

sub number_base :Chained('list') :PathPart('number') :CaptureArgs(1) {
    my ($self, $c, $number_id) = @_;

    unless($number_id && is_int($number_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $number_id },
            desc  => $c->loc('Invalid LNP number id detected!'),
        );
        $c->flash(number_messages => delete $c->flash->{messages});
        $c->response->redirect($c->uri_for());
        return;
    }

    my $res = $c->stash->{number_rs}->find($number_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $number_id },
            desc  => $c->loc('LNP number does not exist!'),
        );
        $c->flash(number_messages => delete $c->flash->{messages});
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash(number => {$res->get_inflated_columns});
    $c->stash(number_result => $res);
}

sub number_edit :Chained('number_base') :PathPart('edit') {
    my ($self, $c ) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = $c->stash->{number};
    $params->{lnp_provider}{id} = delete $params->{lnp_provider_id};
    $params->{start} //= '';
    $params->{start} =~ s/T\d{2}:\d{2}:\d{2}$//;
    $params->{end} //= '';
    $params->{end} =~ s/T\d{2}:\d{2}:\d{2}$//;
    $params = merge($params, $c->session->{created_objects});
    $form = NGCP::Panel::Form::Lnp::Number->new(ctx => $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => { 'lnp_provider.create' => $c->uri_for('/lnp/carrier_create') },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        $form->values->{lnp_provider_id} = $form->values->{lnp_provider}{id};
        delete $form->values->{lnp_provider};
        my $carrier = $c->model('DB')->resultset('lnp_providers')->find($form->values->{lnp_provider_id});
        unless($carrier) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                data => { id => $form->values->{lnp_provider_id} },
                    desc  => $c->loc('Invalid LNP provider id detected!'),
                );
            $c->flash(number_messages => delete $c->flash->{messages});
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/lnp'));
            return;
        }
        if ($c->model('DB')->resultset('lnp_numbers')->search({
                number => $form->values->{number}
            },undef)->count > 0) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                data => { number => $form->values->{number} },
                desc  => $c->loc("LNP number already exists!"),
            );
            $c->flash(number_messages => delete $c->flash->{messages});
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/lnp'));
            return;
        }
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                if(length $form->values->{start}) {
                    $form->values->{start} .= 'T00:00:00';
                } else {
                    $form->values->{start} = undef;
                }
                if(length $form->values->{end}) {
                    $form->values->{end} .= 'T23:59:59';
                } else {
                    $form->values->{end} = undef;
                }
                $form->values->{routing_number} = undef unless(length $form->values->{routing_number});
                $c->stash->{number_result}->update($form->values);
            });

            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('LNP number successfully updated'),
            );
            $c->flash(number_messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update LNP number'),
            );
            $c->flash(number_messages => delete $c->flash->{messages});
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/lnp'));
    }
    $c->stash( 'number_edit_flag'      => 1 );
    $c->stash( 'number_form'           => $form );
}

sub number_create :Chained('list') :PathPart('number_create') :Args(0) {
    my ($self, $c) = @_;

    my $schema = $c->model('DB');
    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    $form = NGCP::Panel::Form::Lnp::Number->new(ctx => $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => { 'lnp_provider.create' => $c->uri_for('/lnp/carrier_create') },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        $form->values->{lnp_provider_id} = $form->values->{lnp_provider}{id};
        delete $form->values->{lnp_provider};
        my $carrier = $c->model('DB')->resultset('lnp_providers')->find($form->values->{lnp_provider_id});
        unless($carrier) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                data => { id => $form->values->{lnp_provider_id} },
                desc  => $c->loc('Invalid LNP provider id detected!'),
            );
            $c->flash(number_messages => delete $c->flash->{messages});
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/lnp'));
            return;
        }
        if ($c->model('DB')->resultset('lnp_numbers')->search({
                number => $form->values->{number}
            },undef)->count > 0) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                data => { number => $form->values->{number} },
                desc  => $c->loc("LNP number already exists!"),
            );
            $c->flash(number_messages => delete $c->flash->{messages});
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/lnp'));
            return;
        }
        try {
            if(length $form->values->{start}) {
                $form->values->{start} .= 'T00:00:00';
            } else {
                delete $form->values->{start} ;
            }
            if(length $form->values->{end}) {
                $form->values->{end} .= 'T23:59:59';
            } else {
                delete $form->values->{end};
            }
            my $number = $carrier->lnp_numbers->create($form->values);
            $c->session->{created_objects}->{lnp_number} = { id => $number->id };
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('LNP number successfully created'),
            );
            $c->flash(number_messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create LNP number'),
            );
            $c->flash(number_messages => delete $c->flash->{messages});
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/lnp'));
    }

    $c->stash(number_create_flag => 1);
    $c->stash(number_form => $form);
}

sub number_delete :Chained('number_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    my $number = $c->stash->{number_result};

    try {
        $number->delete;
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $c->stash->{number},
            desc => $c->loc('LNP number successfully deleted'),
        );
        $c->flash(number_messages => delete $c->flash->{messages});
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $c->stash->{number},
            desc  => $c->loc('Failed to terminate LNP number'),
        );
        $c->flash(number_messages => delete $c->flash->{messages});
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/lnp'));
}



sub numbers_upload :Chained('list') :PathPart('upload') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::Lnp::Upload->new(ctx => $c);
    my $upload = $c->req->upload('upload_lnp');
    my $posted = $c->req->method eq 'POST';
    my @params = ( upload_lnp => $posted ? $upload : undef, );
    $form->process(
        posted => $posted,
        params => { @params },
        action => $c->uri_for('/lnp/upload'),
    );
    if($form->validated) {

        # TODO: check by formhandler?
        unless($upload) {
            NGCP::Panel::Utils::Message::error(
                c    => $c,
                desc => $c->loc('No LNP number file specified!'),
            );
            $c->flash(carrier_messages => delete $c->flash->{messages});
            $c->response->redirect($c->uri_for('/lnp'));
            return;
        }
        my $data = $upload->slurp;
        my($numbers, $fails, $text_success);
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                if($c->req->params->{purge_existing}) {
                    my ($start, $end);
                    $start = time;
                    NGCP::Panel::Utils::MySQL::truncate_table(
                         c => $c,
                         schema => $schema,
                         do_transaction => 0,
                         table => 'billing.lnp_numbers',
                    );
                    $c->stash->{carrier_rs}->delete;
                    $end = time;
                    $c->log->debug("Purging LNP entries took " . ($end - $start) . "s");
                }
                ( $numbers, $fails, $text_success ) = NGCP::Panel::Utils::Lnp::upload_csv(
                    c       => $c,
                    data    => \$data,
                    schema  => $schema,
                );
            });

            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $$text_success,
            );
            $c->flash(carrier_messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to upload LNP numbers'),
            );
            $c->flash(carrier_messages => delete $c->flash->{messages});
        }

        $c->response->redirect($c->uri_for('/lnp'));
        return;
    }

    $c->stash(carrier_create_flag => 1);
    $c->stash(carrier_form => $form);
}

sub numbers_download :Chained('list') :PathPart('download') :Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->model('DB');
    $c->response->header ('Content-Disposition' => 'attachment; filename="lnp_list.csv"');
    $c->response->content_type('text/csv');
    $c->response->status(200);
    NGCP::Panel::Utils::Lnp::create_csv(
        c => $c,
    );
    return;
}

__PACKAGE__->meta->make_immutable;

1;
