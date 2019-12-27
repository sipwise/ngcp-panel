package NGCP::Panel::Controller::BatchProvisioning;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

#use NGCP::Panel::Form;

#use NGCP::Panel::Utils::Contract;
#use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Datatables;
#use NGCP::Panel::Utils::DateTime;
#use NGCP::Panel::Utils::Billing;
use NGCP::Panel::Utils::ProvisioningTemplates qw();
use URI::Encode qw();

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
    map { $templates->{$_}->{name} = $_; } keys %$templates;

    #use Data::Dumper;
    #$c->log->debug(Dumper($templates));

    $c->stash->{provisioning_templates} = $templates;

    $c->stash->{template_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "name", search => 1, title => $c->loc('Name') },
        { name => "description", search => 1, title => $c->loc('Description') },
    ]);

    $c->stash(template => 'batchprovisioning/list.tt');
}

sub root :Chained('template_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('template_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    #[ { type => "xy", description => "blah" } ];

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
        #pref_rs => $pref_rs,
        #enums   => \@enums,
        base_uri => $c->uri_for_action('/batchprovisioning/root'),
        #edit_uri => $c->uri_for_action('/customer/pbx_device_preferences_edit', $c->req->captures ),
    );
    return;
}

sub do_template_upload :Chained('template_base') :PathPart('upload') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::ProvisioningTemplateUpload", $c);
    my $upload = $c->req->upload('csv');
    my $posted = $c->req->method eq 'POST';
    my @params = ( csv => $posted ? $upload : undef, );
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

            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('CSV file ([_1] lines) processed, [_2] error(s).',$linecount, scalar @$errors),
            );
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
