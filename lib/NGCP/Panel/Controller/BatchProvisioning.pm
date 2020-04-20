package NGCP::Panel::Controller::BatchProvisioning;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Datatables;
use NGCP::Panel::Utils::DateTime qw();
use NGCP::Panel::Utils::ProvisioningTemplates qw();
use NGCP::Panel::Form::ProvisioningTemplate::Admin qw();
use NGCP::Panel::Form::ProvisioningTemplate::Reseller qw();
use URI::Encode qw();
use YAML::XS qw();

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(ccareadmin) :AllowedRole(ccare) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    $c->detach('/denied_page')
        unless($c->config->{features}->{batch_provisioning});
    return 1;
}

sub template_list :Chained('/') :PathPart('batchprovisioning') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    my $templates = { %{$c->config->{provisioning_templates} // {}} };
    map {
        $templates->{$_}->{name} = $_;
        $templates->{$_}->{static} = 1;
        $templates->{$_}->{id} = undef;
        $templates->{$_}->{reseller} = undef;
    } keys %$templates;

    my $rs = $c->model('DB')->resultset('provisioning_templates')->search_rs();
    if($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
    } elsif($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $rs = $rs->search_rs({ -or => [
                                reseller_id => $c->user->reseller_id,
                                reseller_id => undef
                             ], },);
    } else {
        $rs = $rs->search_rs({ -or => [
                                reseller_id => $c->user->contract->contact->reseller_id,
                                reseller_id => undef
                             ], },);
    }
    foreach my $db_template ($rs->all) {
        my $template = { $db_template->get_inflated_columns };
        eval {
            %$template = ( %{YAML::XS::Load($template->{yaml})}, %$template );
            #use Data::Dumper;
            #$c->log->error(Dumper($template));
            delete $template->{yaml};
        };
        if ($@) {
            $c->log->error("error parsing provisioning_template id $template->{id} '$template->{name}': " . $@);
            next;
        }
        $template->{static} = 0;
        $template->{reseller} = $db_template->reseller->name if $db_template->reseller;
        $templates->{$template->{name}} = $template;
    }

    $c->stash->{provisioning_templates} = $templates;

    $c->stash->{template_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "reseller", search => 1, title => $c->loc("Reseller") },
        { name => "name", search => 1, title => $c->loc('Name') },
        { name => "description", search => 1, title => $c->loc('Description') },
        { name => "static", search => 0, field => 1 },
    ]);

    $c->stash(template => 'batchprovisioning/list.tt');
}

sub root :Chained('template_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('template_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    NGCP::Panel::Utils::Datatables::process_static_data($c, [ values %{$c->stash->{provisioning_templates}} ], $c->stash->{template_dt_columns});
    $c->detach($c->view('JSON'));

    return;
}

sub template_base :Chained('template_list') :PathPart('templates') :CaptureArgs(1) {
    my ( $self, $c, $template ) = @_;
    my $decoder = URI::Encode->new;
    $c->stash->{provisioning_template_name} = $decoder->decode($template);
}

sub do_template_form :Chained('template_base') :PathPart('form') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(create_flag => 1);
    $c->stash(modal_title => $c->loc("Subscriber with Provisioning Template '[_1]'", $c->stash->{provisioning_template_name}));

    $c->log->debug($c->stash->{provisioning_template_name});
    $c->log->debug($c->uri_for_action('/batchprovisioning/root'));
    NGCP::Panel::Utils::ProvisioningTemplates::create_provisioning_template_form(
        c => $c,
        base_uri => $c->uri_for_action('/batchprovisioning/root'),
    );
    return;
}

sub do_template_upload :Chained('template_base') :PathPart('upload') :Args(0) {
    my ($self, $c) = @_;

    $c->log->debug($c->uri_for_action('/batchprovisioning/do_template_upload', $c->req->captures));

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::ProvisioningTemplate::ProvisioningTemplateUpload", $c);
    my $upload = $c->req->upload('csv');
    my $posted = $c->req->method eq 'POST';
    my @params = ( csv => ($posted ? $upload : undef), );
    $form->process(
        posted => $posted,
        params => { @params },
        action => $c->uri_for_action('/batchprovisioning/do_template_upload', $c->req->captures),
    );

    if($form->validated) {

        unless($upload) {
            NGCP::Panel::Utils::Message::error(
                c    => $c,
                desc => $c->loc('No CSV file specified!'),
            );
            $c->response->redirect($c->uri_for_action('/batchprovisioning/root'));
            return;
        }

        my $data = $upload->slurp;
        try {
            my ($linecount,$errors) = NGCP::Panel::Utils::ProvisioningTemplates::process_csv(
                c     => $c,
                data  => \$data,
                purge => $c->req->params->{purge_existing},
            );

            if (scalar @$errors) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    log => $errors,
                    desc => $c->loc('CSV file ([_1] lines) processed, [_2] error(s).', $linecount, scalar @$errors),
                );
            } else {
                NGCP::Panel::Utils::Message::info(
                    c    => $c,
                    desc => $c->loc('CSV file ([_1] lines) processed, [_2] error(s).', $linecount, 0),
                );
            }
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to process CSV file.'),
            );
        }

        $c->response->redirect($c->uri_for_action('/batchprovisioning/root'));
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(modal_title => $c->loc("Subscribers with Provisioning Template '[_1]' from CSV", $c->stash->{provisioning_template_name}));
    $c->stash(form => $form);
}

sub create :Chained('template_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});

    $c->stash->{old_name} = undef;

    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::ProvisioningTemplate::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::ProvisioningTemplate::Reseller", $c);
    }

    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
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
            if (exists $form->values->{reseller}) {
                if($c->user->is_superuser) {
                    $form->values->{reseller_id} = $form->values->{reseller}{id};
                } else {
                    $form->values->{reseller_id} = $c->user->reseller_id;
                }
                delete $form->values->{reseller};
            }
            $form->values->{create_timestamp} = $form->values->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
            my $template = $c->model('DB')->resultset('provisioning_templates')->create($form->values);

            $c->session->{created_objects}->{provisioning_template} = { id => $template->id };
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Provisioning template successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create provisioning template'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/batchprovisioning'));
    }

    $c->stash(create_flag => 1);
    $c->stash(modal_title => $c->loc("Provisioning Template"));
    $c->stash(form => $form);
}

sub edit :Chained('template_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $template = $c->stash->{provisioning_template_name};
    my $params = $c->stash->{provisioning_templates}->{$template};
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});

    $c->stash->{old_name} = $template;

    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::ProvisioningTemplate::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::ProvisioningTemplate::Reseller", $c);
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
            if (exists $form->values->{reseller}) {
                if($c->user->is_superuser) {
                    $form->values->{reseller_id} = $form->values->{reseller}{id};
                } else {
                    $form->values->{reseller_id} = $c->user->reseller_id;
                }
                delete $form->values->{reseller};
            }
            $form->values->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
            my $template = $c->model('DB')->resultset('provisioning_templates')->update($form->values);

            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Provisioning template successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update provisioning template'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/batchprovisioning'));
    }
    $c->stash(edit_flag => 1 );
    $c->stash(modal_title => $c->loc("Provisioning Template"));
    $c->stash(form => $form );
}

1;
