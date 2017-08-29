package NGCP::Panel::Controller::CallListSuppression;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Datatables;
use NGCP::Panel::Utils::MySQL;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::CallList qw();


sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list :Chained('/') :PathPart('calllistsuppression') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    my $rs = $c->model('DB')->resultset('call_list_suppressions');
    $c->stash(rs => $rs);
    $c->stash->{calllistsuppression_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", "search" => 1, "title" => $c->loc("#") },
        { name => "domain", "search" => 1, "title" => $c->loc("Domain") },
        { name => "direction", "search" => 1, "title" => $c->loc("Direction") },
        { name => "pattern", "search" => 1, "title" => $c->loc("Pattern") },
        { name => "mode", "search" => 1, "title" => $c->loc("Mode") },
        { name => "label", "search" => 1, "title" => $c->loc("Label") },
    ]);

    $c->stash(template => 'calllistsuppression/list.tt');
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $rs = $c->stash->{rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{calllistsuppression_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub base :Chained('list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $sup_id) = @_;

    unless($sup_id && is_int($sup_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid call list suppression id detected',
            desc  => $c->loc('Invalid call list suppression id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/calllistsuppression'));
    }

    my $res = $c->stash->{rs}->find($sup_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Call list suppression does not exist',
            desc  => $c->loc('Call list suppression does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/calllistsuppression'));
    }
    $c->stash(sup => $res);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c ) = @_;

    my $form;
    my $sup = $c->stash->{sup};
    my $posted = ($c->request->method eq 'POST');
    my $params = { $sup->get_inflated_columns };
    $params = merge($params, $c->session->{created_objects});
    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::CallListSuppression::Suppression", $c);
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
                my $dup_item = $schema->resultset('call_list_suppressions')->find({
                    domain => $form->values->{domain},
                    pattern => $form->values->{pattern},
                    direction => $form->values->{direction},
                });
                if($dup_item && $dup_item->id != $sup->id) {
                    die( ["The combination of domain, direction and pattern should be unique", "showdetails"] );
                }

                $sup->update($form->values);

                #delete $c->session->{created_objects}->{reseller};
            });
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Call list suppression successfully updated'),
            );
            $c->flash(messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update call list suppression'),
            );
            $c->flash(messages => delete $c->flash->{messages});
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/calllistsuppression'));
    }
    $c->stash(edit_flag => 1);
    $c->stash(form => $form);
}

sub create :Chained('list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $schema = $c->model('DB');
    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::CallListSuppression::Suppression", $c);
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
            my $dup_item = $schema->resultset('call_list_suppressions')->find({
                domain => $form->values->{domain},
                pattern => $form->values->{pattern},
                direction => $form->values->{direction},
            });
            if($dup_item) {
                die( ["The combination of domain, direction and pattern already exists", "showdetails"] );
            }
            my $sup = $c->model('DB')->resultset('call_list_suppressions')->create($form->values);
            $c->session->{created_objects}->{call_list_suppression} = { id => $sup->id };
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Call list suppression successfully created'),
            );
            $c->flash(messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create call list suppression'),
            );
            $c->flash(messages => delete $c->flash->{messages});
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/calllistsuppression'));
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub{
            $c->stash->{sup}->delete;
        });
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => { $c->stash->{sup}->get_inflated_columns },
            desc => $c->loc('Call list suppression successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete call list suppression.'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/calllistsuppression'));
}


sub upload :Chained('list') :PathPart('upload') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::CallListSuppression::Upload", $c);
    my $upload = $c->req->upload('upload_calllistsuppression');
    my $posted = $c->req->method eq 'POST';
    my @params = ( upload_lnp => $posted ? $upload : undef, );
    $form->process(
        posted => $posted,
        params => { @params },
        action => $c->uri_for('/calllistsuppression/upload'),
    );
    if($form->validated) {

        # TODO: check by formhandler?
        unless($upload) {
            NGCP::Panel::Utils::Message::error(
                c    => $c,
                desc => $c->loc('No call list suppression file specified!'),
            );
            $c->flash(messages => delete $c->flash->{messages});
            $c->response->redirect($c->uri_for('/calllistsuppression'));
            return;
        }
        my $data = $upload->slurp;
        my($fails, $text_success);
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
                         table => 'billing.call_list_suppressions',
                    );
                    $c->stash->{rs}->delete;
                    $end = time;
                    $c->log->debug("Purging call list suppressions took " . ($end - $start) . "s");
                }
                ( $fails, $text_success ) = NGCP::Panel::Utils::CallList::upload_suppressions_csv(
                    c       => $c,
                    data    => \$data,
                    schema  => $schema,
                );
            });

            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $$text_success,
            );
            $c->flash(messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to upload call list suppressions'),
            );
            $c->flash(messages => delete $c->flash->{messages});
        }

        $c->response->redirect($c->uri_for('/calllistsuppression'));
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub download :Chained('list') :PathPart('download') :Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->model('DB');
    $c->response->header ('Content-Disposition' => 'attachment; filename="call_list_suppressions.csv"');
    $c->response->content_type('text/csv');
    $c->response->status(200);
    NGCP::Panel::Utils::CallList::create_suppressions_csv(
        c => $c,
    );
    return;
}

__PACKAGE__->meta->make_immutable;

1;
