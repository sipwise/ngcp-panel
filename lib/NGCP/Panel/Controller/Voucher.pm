package NGCP::Panel::Controller::Voucher;
use Sipwise::Base;
use Text::CSV_XS;
use DateTime::Format::ISO8601;

BEGIN { use parent 'Catalyst::Controller'; }

use NGCP::Panel::Form::Voucher::Admin;
use NGCP::Panel::Form::Voucher::Reseller;
use NGCP::Panel::Form::Voucher::Upload;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Datatables;
use NGCP::Panel::Utils::DateTime;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');

    $c->detach('/denied_page')
        unless($c->config->{features}->{voucher});

    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub voucher_list :Chained('/') :PathPart('voucher') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $voucher_rs = $c->model('DB')->resultset('vouchers');
    if($c->user->roles eq "reseller") {
        $voucher_rs = $voucher_rs->search({
            reseller_id => $c->user->reseller_id,
        });
    }
    $c->stash(voucher_rs => $voucher_rs);
    $c->stash->{voucher_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", "search" => 1, "title" => $c->loc("#") },
        { name => "code", "search" => 1, "title" => $c->loc("Code") },
        { name => "amount", "search" => 1, "title" => $c->loc("Amount") },
        { name => "reseller.name", "search" => 1, "title" => $c->loc("Reseller") },
        { name => "valid_until", "search" => 1, "title" => $c->loc("Valid Until") },
        { name => "used_at", "search" => 1, "title" => $c->loc("Used At") },
        { name => "used_by_subscriber.id", "search" => 1, "title" => $c->loc("Used By Subscriber #") },
    ]);

    $c->stash(template => 'voucher/list.tt');
}

sub root :Chained('voucher_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('voucher_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{voucher_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{voucher_dt_columns});
    
    $c->detach( $c->view("JSON") );
}

sub base :Chained('voucher_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $voucher_id) = @_;

    unless($voucher_id && is_int($voucher_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $voucher_id },
            desc  => $c->loc('Invalid voucher id detected!'),
        );
        $c->response->redirect($c->uri_for());
        return;
    }

    my $res = $c->stash->{voucher_rs}->find($voucher_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $voucher_id },
            desc  => $c->loc('Billing Voucher does not exist!'),
        );
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash(voucher => {$res->get_inflated_columns});
    $c->stash(voucher_result => $res);
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{voucher_result}->delete;
        NGCP::Panel::Utils::Message::info(
            c => $c,
            desc  => $c->loc('Billing Voucher successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $$c->stash->{voucher_result}->id },
            desc  => $c->loc('Failed to delete Billing Voucher'),
        );
    }
    $c->response->redirect($c->uri_for());
    return;
}


sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = $c->stash->{voucher};
    $params->{valid_until} =~ s/^(\d{4}\-\d{2}\-\d{2}).*$/$1/;
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::Voucher::Admin->new;
    } else {
        $form = NGCP::Panel::Form::Voucher::Reseller->new;
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
            'customer.create' => $c->uri_for('/customer/create'),
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
            $form->values->{customer_id} = $form->values->{customer}{id};
            delete $form->values->{customer};
            if($form->values->{valid_until} =~ /^\d{4}\-\d{2}\-\d{2}$/) {
                $form->values->{valid_until} = NGCP::Panel::Utils::DateTime::from_string($form->values->{valid_until})
                    ->add(days => 1)->subtract(seconds => 1);
            }

            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $c->stash->{voucher_result}->update($form->values);
            });

            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Billing voucher successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update billing voucher'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/voucher'));
    }

    $c->stash(edit_flag => 1);
    $c->stash(form => $form);
}

sub create :Chained('voucher_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::Voucher::Admin->new;
    } else {
        $form = NGCP::Panel::Form::Voucher::Reseller->new;
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
            'customer.create' => $c->uri_for('/customer/create'),
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
            $form->values->{customer_id} = $form->values->{customer}{id};
            delete $form->values->{customer};
            $form->values->{created_at} = NGCP::Panel::Utils::DateTime::current_local;
            if($form->values->{valid_until} =~ /^\d{4}\-\d{2}\-\d{2}$/) {
                $form->values->{valid_until} = NGCP::Panel::Utils::DateTime::from_string($form->values->{valid_until})
                    ->add(days => 1)->subtract(seconds => 1);
            }
            my $voucher = $c->model('DB')->resultset('vouchers')->create($form->values);
            $c->session->{created_objects}->{voucher} = { id => $voucher->id };
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Billing voucher successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create billing voucher'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/voucher'));
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub voucher_upload :Chained('voucher_list') :PathPart('upload') :Args(0) {
    my ($self, $c) = @_;
    
    my $form = NGCP::Panel::Form::Voucher::Upload->new;
    my $upload = $c->req->upload('upload_vouchers');
    my $posted = $c->req->method eq 'POST';
    my @params = (
        upload_fees => $posted ? $upload : undef,
        );
    $form->process(
        posted => $posted,
        params => { @params },
        action => $c->uri_for_action('/voucher/voucher_upload', $c->req->captures),
    );
    if($posted && $form->validated) {

        unless($upload) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                desc => $c->loc('No Billing Voucher file specified!'),
            );
            $c->response->redirect($c->uri_for('/voucher'));
            return;
        }

        my $csv = Text::CSV_XS->new({allow_whitespace => 1, binary => 1, keep_meta_info => 1});
        my @cols = $c->config->{voucher_csv}->{element_order};
        if($c->user->roles eq "admin") {
            unshift @{ $cols[0] }, 'reseller_id';
        }
        $csv->column_names (@cols);
        my @fails = ();
        my $linenum = 0;

        my @vouchers = ();
        try {
            $c->model('DB')->txn_do(sub {
                if ($c->req->params->{purge_existing}) {
                    $c->stash->{'voucher_rs'}->delete;
                }

                while(my $row = $csv->getline_hr($upload->fh)) {
                    ++$linenum;
                    if($csv->is_missing(1)) {
                        push @fails, $linenum;
                        next;
                    }
                    if($row->{valid_until} =~ /^\d{4}\-\d{2}\-\d{2}$/) {
                        $row->{valid_until} = NGCP::Panel::Utils::DateTime::from_string($row->{valid_until})
                            ->add(days => 1)->subtract(seconds => 1);
                    }
                    $row->{customer_id} = undef if(defined $row->{customer_id} && $row->{customer_id} eq "");
                    push @vouchers, $row;
                }
                unless ($csv->eof()) {
                    die "Some lines could not be parsed. Did not reach eof. Last successful: $linenum.";
                }
                $c->stash->{voucher_rs}->populate(\@vouchers);
            });

            my $text = $c->loc('Billing Vouchers successfully uploaded');
            if(@fails) {
                $text .= $c->loc(", but skipped the following line numbers: ") . (join ", ", @fails);
            }
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $text,
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to upload Billing Vouchers'),
            );
        };

        $c->response->redirect($c->uri_for('/voucher'));
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

__PACKAGE__->meta->make_immutable;
1;
# vim: set tabstop=4 expandtab:
