package NGCP::Panel::Controller::Contact;
use NGCP::Panel::Utils::Generic qw(:all);
use Geography::Countries qw/countries country CNT_I_FLAG CNT_I_CODE2/;
use Sipwise::Base;
use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::DateTime qw();

sub auto :Private {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list_contact :Chained('/') :PathPart('contact') :CaptureArgs(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(ccareadmin) :AllowedRole(ccare) {
    my ($self, $c) = @_;

    my $contacts = $c->model('DB')->resultset('contacts')->search({
        'me.status' => { '!=' => 'terminated' },
    });
    unless($c->user->is_superuser) {
        $contacts = $contacts->search({ reseller_id => $c->user->reseller_id });
    }
    $c->stash(contacts => $contacts);

    $c->stash(template => 'contact/list.tt');

    $c->stash->{contact_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", int_search => 1, title => $c->loc("#") },
        { name => "reseller.name", search => 0, title => $c->loc("Reseller") },
        { name => "firstname", search => 0, title => $c->loc("First Name") },
        { name => "lastname", search => 0, title => $c->loc("Last Name") },
        { name => "company", search => 0, title => $c->loc("Company") },
        { name => "email", search => 1, title => $c->loc("Email") },
    ]);
}

sub timezone_ajax :Chained('/') :PathPart('contact/timezone_ajax') :Args() {
    my ($self, $c, $parent_owner_type, $parent_owner_id) = @_;

    my $default_tz_data = NGCP::Panel::Utils::DateTime::get_default_timezone_name($c, $parent_owner_type, $parent_owner_id);

    my $tz_rs = $c->model('DB')->resultset('timezones');
    my $tz_cols = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "name", search => 1, title => $c->loc('Timezone') },
    ]);

    NGCP::Panel::Utils::Datatables::process($c, $tz_rs, $tz_cols, undef, { topData => $default_tz_data } );

    $c->detach( $c->view("JSON") );
}

sub root :Chained('list_contact') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('list_contact') :PathPart('create') :Args(0) {
    my ($self, $c, $no_reseller) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->is_superuser && $no_reseller) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Contact::Reseller", $c);
        $params->{reseller}{id} = $c->user->reseller_id;
        # we'll delete this after validation, as we don't need the reseller in this case
    } elsif($c->user->is_superuser) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Contact::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Contact::Reseller", $c);
        $params->{reseller}{id} = $c->user->reseller_id;
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
                delete $form->values->{reseller};
            }
            $form->values->{country} = $form->values->{country}{id};
            $form->values->{timezone} = $form->values->{timezone}{name} || undef;
            my $contact = $c->stash->{contacts}->create($form->values);
            delete $c->session->{created_objects}->{reseller};
            $c->session->{created_objects}->{contact} = { id => $contact->id };
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Contact successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create contact'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contact'));
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub create_without_reseller :Chained('list_contact') :PathPart('create/noreseller') :Args(0) {
    my ($self, $c) = @_;

    $self->create($c, 1);
}

sub base :Chained('list_contact') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $contact_id) = @_;

    unless($contact_id && is_int($contact_id)) {
        $contact_id ||= '';
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $contact_id },
            desc => $c->loc('Invalid contact id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contact'));
    }
    my $res = $c->stash->{contacts};
    $c->stash(contact => $res->find($contact_id));
    unless($c->stash->{contact}) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { $c->stash->{contact}->get_inflated_columns },
            desc => $c->loc('Contact not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contact'));
    }
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c, $no_reseller) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = { $c->stash->{contact}->get_inflated_columns };
    $params = merge($params, $c->session->{created_objects});
    $params->{country}{id} = delete $params->{country};
    $params->{timezone}{name} = delete $params->{timezone};
    if($c->user->is_superuser && $no_reseller) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Contact::Reseller", $c);
        $params->{reseller}{id} = $c->user->reseller_id;
    } elsif($c->user->is_superuser && $c->stash->{contact}->reseller) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Contact::Admin", $c);
        $params->{reseller}{id} = $c->stash->{contact}->reseller_id;
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Contact::Reseller", $c);
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
                delete $form->values->{reseller};
            } elsif($c->user->is_superuser) {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
            }
            delete $form->values->{reseller};
            $form->values->{country} = $form->values->{country}{id};
            $form->values->{timezone} = $form->values->{timezone}{name} || undef;
            $c->stash->{contact}->update($form->values);
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Contact successfully changed'),
            );
            delete $c->session->{created_objects}->{reseller};
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update contact'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contact'));
    }

    $c->stash(
        form => $form,
        edit_flag => 1,
    );
}

sub edit_without_reseller :Chained('base') :PathPart('edit/noreseller') :Args(0) {
    my ($self, $c) = @_;

    $self->edit($c, 1);
}

sub delete_contact :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            my $contact = $c->stash->{contact};
            my $id = $contact->id;
            my $contract_rs = $schema->resultset('contracts')->search({
                contact_id => $id,
                status => { '!=' => 'terminated' },
            });
            my $subscriber_rs = $schema->resultset('voip_subscribers')->search({
                contact_id => $id,
                status => { '!=' => 'terminated' },
            });
            if ($contract_rs->first or $subscriber_rs->first) { #2. if active contracts or subscribers -> error
                die( ["Contact is still in use.", "showdetails"] );
            } else {
                $contract_rs = $schema->resultset('contracts')->search({
                    contact_id => $id,
                    status => { '=' => 'terminated' },
                });
                $subscriber_rs = $schema->resultset('voip_subscribers')->search({
                    contact_id => $id,
                    status => { '=' => 'terminated' },
                });
                if ($contract_rs->first or $subscriber_rs->first) { #1. terminate if terminated contracts or subscribers
                    $c->log->debug("terminate contact id ".$id);
                    $contact->update({
                        status => "terminated",
                        terminate_timestamp => NGCP::Panel::Utils::DateTime::current_local,
                    });
                    NGCP::Panel::Utils::Message::info(
                        c => $c,
                        data => { $contact->get_inflated_columns },
                        desc  => $c->loc('Contact successfully terminated'),
                    );
                } else { #3. delete otherwise
                    $c->log->debug("delete contact id ".$contact->id);
                    $contact->delete;
                    NGCP::Panel::Utils::Message::info(
                        c => $c,
                        data => { $contact->get_inflated_columns },
                        desc  => $c->loc('Contact successfully deleted'),
                    );
                }
            }
        });
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data => { $c->stash->{contact}->get_inflated_columns },
            desc  => $c->loc('Failed to delete contact'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contact'));
}

sub ajax :Chained('list_contact') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    $self->ajax_list_contacts($c, {'reseller' => 'any'});

    $c->detach( $c->view("JSON") );
}

sub ajax_noreseller :Chained('list_contact') :PathPart('ajax_noreseller') :Args(0) {
    my ($self, $c) = @_;
    $self->ajax_list_contacts($c, {'reseller' => 'no_reseller'});
    $c->detach( $c->view("JSON") );
}

sub ajax_reseller :Chained('list_contact') :PathPart('ajax_reseller') :Args(0) {
    my ($self, $c) = @_;
    $self->ajax_list_contacts($c, {'reseller' => 'not_empty'});
    $c->detach( $c->view("JSON") );
}

sub ajax_list_contacts{
    my ($self, $c, $params) = @_;
    $params //= {};
    my $reseller_query = [];
    if('any' eq $params->{reseller}){
        $reseller_query->[0] = undef;
    }elsif('no_reseller' eq $params->{reseller}){
        $reseller_query->[0] = { reseller_id => undef,};
    }elsif('not_empty' eq $params->{reseller}){
        $reseller_query->[0] = { reseller_id => { '!=' => undef },};
    }
    NGCP::Panel::Utils::Datatables::process(
        $c,
        $c->stash->{contacts}->search_rs(
            $reseller_query->[0],
            $reseller_query->[1],
        ),
        $c->stash->{contact_dt_columns},
        sub {
            my ($result) = @_;
            my $contract_rs = $result->contracts->search({
                status => { '!=' => 'terminated' },
            });
            my $subscriber_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                contact_id => $result->id,
                status => { '!=' => 'terminated' },
            });
            my %data = (deletable => ($contract_rs->first or $subscriber_rs->first) ? 0 : 1);
            return %data
        },
	{ 'count_limit' => 1000, },
    );

}

sub countries_ajax :Chained('/') :PathPart('contact/country/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(ccareadmin) :AllowedRole(ccare) {
    my ($self, $c) = @_;

    my $from = $c->request->params->{iDisplayStart} // 0;
    my $len = $c->request->params->{iDisplayLength} // 4;
    my $to = $from + $len - 1;
    my $search = $c->request->params->{sSearch};
    my $top = $c->request->params->{iIdOnTop};

    my $top_entry;
    my @aaData = map {
        my @c = country($_);
        if($c[CNT_I_CODE2]) {
            my $e = { name => $_, id => $c[CNT_I_CODE2] };
            if($top && !$top_entry && $top eq $e->{id}) {
                $top_entry = $e;
                (); # we insert it as top element after the map
            } else {
                $e;
            }
        } else { (); }
    } countries;
    if($top_entry) {
        unshift @aaData, $top_entry;
    }

    if(defined $search) {
        @aaData = map {
            if($_->{id} =~ /$search/i || $_->{name} =~ /$search/i) {
                $_;
            } else { (); }
        } @aaData;
    }

    my $count = @aaData;
    @aaData = @aaData[$from .. ($to < $#aaData ? $to : $#aaData)];

    $c->stash(aaData               => \@aaData,
              iTotalRecords        => $count,
              iTotalDisplayRecords => $count,
              iTotalRecordCountClipped        => \0,
              iTotalDisplayRecordCountClipped => \0,
              sEcho                => int($c->request->params->{sEcho} // 1),
    );

    $c->detach( $c->view("JSON") );
}



1;

# vim: set tabstop=4 expandtab:
