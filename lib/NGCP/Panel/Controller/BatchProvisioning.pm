package NGCP::Panel::Controller::BatchProvisioning;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Datatables;
use NGCP::Panel::Utils::ProvisioningTemplates qw();
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
        $templates->{$template->{name}} = $template;
    }

    $c->stash->{provisioning_templates} = $templates;

    $c->stash->{template_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "name", search => 1, title => $c->loc('Name') },
        { name => "description", search => 1, title => $c->loc('Description') },
        { name => "static", search => 0, },
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

sub template_base :Chained('template_list') :PathPart('') :CaptureArgs(1) {
    my ( $self, $c, $template ) = @_;
    my $decoder = URI::Encode->new;
    $c->stash->{provisioning_template_name} = $decoder->decode($template);
}

sub do_template_form :Chained('template_base') :PathPart('form') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(create_flag => 1);

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

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::ProvisioningTemplateUpload", $c);
    my $upload = $c->req->upload('csv');
    my $posted = $c->req->method eq 'POST';
    my @params = ( csv => ($posted ? $upload : undef), );
    $form->process(
        posted => $posted,
        params => { @params },
        action => $c->uri_for_action('/batchprovisioning/do_template_upload', $c->req->captures),
    );

    if($form->validated) {

        # TODO: check by formhandler?
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
    $c->stash(form => $form);
}

1;
