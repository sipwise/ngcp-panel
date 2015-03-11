package NGCP::Panel::Controller::InvoiceTemplate;
use Sipwise::Base;

BEGIN { extends 'Catalyst::Controller'; }

use File::Type;
use MIME::Base64 qw(encode_base64);

use NGCP::Panel::Utils::InvoiceTemplate;
use NGCP::Panel::Form::Invoice::TemplateAdmin;
use NGCP::Panel::Form::Invoice::TemplateReseller;

sub auto :Private {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub template_list :Chained('/') :PathPart('invoicetemplate') :CaptureArgs(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ( $self, $c ) = @_;

    $c->stash->{tmpl_rs} = $c->model('DB')->resultset('invoice_templates');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $c->stash->{tmpl_rs} = $c->stash->{tmpl_rs}->search({
            'reseller_id' => $c->user->reseller_id
        });
    };

    $c->stash->{tmpl_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'type', search => 1, title => $c->loc('Type') },
    ]);

    $c->stash(template => 'invoice/template_list.tt');
}

sub root :Chained('template_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('template_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{tmpl_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{tmpl_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub reseller_ajax :Chained('template_list') :PathPart('ajax/reseller') :Args(1) {
    my ($self, $c, $reseller_id) = @_;
    my $rs = $c->stash->{tmpl_rs}->search({
        reseller_id => $reseller_id,
    });
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{tmpl_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub base :Chained('template_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $tmpl_id) = @_;

    unless($tmpl_id && is_int($tmpl_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid invoice template id detected',
            desc  => $c->loc('Invalid invoice template id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoicetemplate'));
    }

    my $res = $c->stash->{tmpl_rs}->find($tmpl_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invoice template does not exist',
            desc  => $c->loc('Invoice template does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoicetemplate'));
    }
    $c->stash(tmpl => $res);
}

sub create :Chained('template_list') :PathPart('create') :Args() {
    my ($self, $c, $reseller_id) = @_;

    if(defined $reseller_id && !is_int($reseller_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid reseller id detected',
            desc  => $c->loc('Invalid reseller id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/reseller'));
    }

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = merge($params, $c->session->{created_objects});

    my $form;
    if($c->user->roles eq "admin" && !$reseller_id) {
        $form = NGCP::Panel::Form::Invoice::TemplateAdmin->new(ctx => $c);
    } else {
        $form = NGCP::Panel::Form::Invoice::TemplateReseller->new(ctx => $c);
        if($c->user->roles eq "admin") {
            my $reseller = $c->model('DB')->resultset('resellers')->find($reseller_id);
            unless($reseller) {
                NGCP::Panel::Utils::Message::error(
                    c     => $c,
                    log   => 'Invalid reseller id detected',
                    desc  => $c->loc('Invalid reseller id detected'),
                );
                NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/reseller'));
            }
        }
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
                if($c->user->roles eq "admin") {
                    $form->params->{reseller_id} = $reseller_id ? $reseller_id : $form->params->{reseller}{id};
                } elsif($c->user->roles eq "reseller") {
                    $form->params->{reseller_id} = $c->user->reseller_id;
                }
                delete $form->params->{reseller};

                my $dup_item = $schema->resultset('invoice_templates')->find({
                    reseller_id => $form->params->{reseller_id},
                    name => $form->params->{name},
                });
                if($dup_item) {
                    die( ["Template name should be unique", "showdetails"] );
                }

                my $tmpl_params = $form->params;
                $tmpl_params->{data} //= NGCP::Panel::Utils::InvoiceTemplate::svg_content($c, $tmpl_params->{data});
                my $tmpl = $c->stash->{tmpl_rs}->create($tmpl_params);

                delete $c->session->{created_objects}->{reseller};
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Invoice template successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create invoice template'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoicetemplate'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub edit_info :Chained('base') :PathPart('editinfo') {
    my ($self, $c) = @_;

    my $tmpl = $c->stash->{tmpl};
    my $posted = ($c->request->method eq 'POST');
    my $params = { $tmpl->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});

    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::Invoice::TemplateAdmin->new(ctx => $c);
    } else {
        $form = NGCP::Panel::Form::Invoice::TemplateReseller->new(ctx => $c);
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
                if($c->user->roles eq "admin") {
                    $form->params->{reseller_id} = $form->params->{reseller}{id};
                } elsif($c->user->roles eq "reseller") {
                    $form->params->{reseller_id} = $c->user->reseller_id;
                }
                delete $form->params->{reseller};

                my $dup_item = $schema->resultset('invoice_templates')->find({
                    reseller_id => $form->params->{reseller_id},
                    name => $form->params->{name},
                });
                if($dup_item && $dup_item->id != $tmpl->id) {
                    die( ["Template name should be unique", "showdetails"] );
                }
                
                $tmpl->update($form->params);

                delete $c->session->{created_objects}->{reseller};
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Invoice template successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update invoice template'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoicetemplate'));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub{
            $c->stash->{tmpl}->delete;
        });
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => { $c->stash->{tmpl}->get_inflated_columns },
            desc => $c->loc('Invoice template successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete invoice template.'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoicetemplate'));
}

sub edit_content :Chained('base') :PathPart('editcontent') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(NGCP::Panel::Utils::InvoiceTemplate::get_dummy_data());
    $c->stash(template => 'invoice/template.tt');
}

sub messages_ajax :Chained('template_list') :PathPart('messages') :Args(0) {
    my ($self, $c) = @_;
    $c->stash(
        messages => $c->flash->{messages},
        template => 'helpers/ajax_messages.tt',
    );
    $c->detach($c->view('TT'));
}

sub get_content_ajax :Chained('base') :PathPart('editcontent/get/ajax') :Args(0) {
    my ($self, $c) = @_;
    my $tmpl = $c->stash->{tmpl};

    my $content = NGCP::Panel::Utils::InvoiceTemplate::svg_content($c, $tmpl->data);

    $c->response->content_type('text/html');
    $c->response->body($content);
}

sub set_content_ajax :Chained('base') :PathPart('editcontent/set/ajax') :Args(0) {
    my ($self, $c, @args) = @_;
    my $tmpl = $c->stash->{tmpl};

    my $content = $c->request->body_parameters->{template};
    unless($content) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => 'empty svg file not allowed',
            desc => $c->log('Attempted to save an empty invoice template'),
        );
        return;
    }

    NGCP::Panel::Utils::InvoiceTemplate::sanitize_svg(\$content);

    try {
        $tmpl->update({
            data => $content,
        });

    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc => $c->loc('Failed to store invoice template'),
        );
        return;
    }
    $c->flash(messages => [{type => 'success', text => $c->loc('Invoice template successfully saved')}]);

    $c->response->content_type('application/json');
    $c->response->body('');
    $c->detach($c->view('JSON'));
}

sub preview_content :Chained('base') :PathPart('editcontent/preview') :Args {
    my ($self, $c, @args) = @_;
    my($out_type) = @args;
    $out_type //= '';
    my $tmpl = $c->stash->{tmpl};

    my $svg = $tmpl->data;

    unless(defined $svg) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Trying to preview a non-saved svg template',
            desc  => $c->loc('Template has not been saved yet, please save before previewing.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoicetemplate'));
        return;
    }

    my $pdf = '';
    my $t = NGCP::Panel::Utils::InvoiceTemplate::get_tt();
    my $out = '';
    my $vars = {};

    try {

        my $dummy = NGCP::Panel::Utils::InvoiceTemplate::get_dummy_data();
        NGCP::Panel::Utils::InvoiceTemplate::preprocess_svg(\$svg);
        $t->process(\$svg, $dummy, \$out) || do {
            my $error = $t->error();
            my $msg = "error processing template, type=".$error->type.", info='".$error->info."'";
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                log   => $msg,
                desc  => $c->loc('Failed to render template. Type is ' . $error->type . ', info is ' . $error->info),
            );
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoicetemplate'));
            return;
        };

        NGCP::Panel::Utils::InvoiceTemplate::svg_pdf($c, \$out, \$pdf);
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => $e,
            desc  => $c->loc('Failed to preview template'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoicetemplate'));
        return;
    }
    if($out_type eq 'svg'){
        $out = join('', @{NGCP::Panel::Utils::InvoiceTemplate::preprocess_svg_pdf($c, \$out)});
        $c->response->body($out);
    }else{
        $c->response->content_type('application/pdf');
        $c->response->body($pdf);
    }
    return;
}


sub embed_image :Chained('/') :PathPart('invoicetemplate/embedimage') :Args(0) {
    my ($self, $c) = @_;
    
    my ($in, $out);
    $in = $c->request->parameters;
    $in->{svg_file} = $c->request->upload('svg_file');
    if($in->{svg_file}) {
        my $ft = File::Type->new();
        $out->{image_content} = $in->{svg_file}->slurp;
        $out->{image_content_mimetype} = $ft->mime_type($out->{image_content});
        $out->{image_content_base64} = encode_base64($out->{image_content}, '');
    }
    $c->log->debug('mime-type '.$out->{image_content_mimetype});
    $out->{image_content_mimetype} =~s!image/x-([[:alnum:]]+)!image/$1!i;
    $c->log->debug('mime-type for pdf generation:'.$out->{image_content_mimetype});
    $c->stash(out => $out);
    $c->stash(in => $in);
    $c->stash(template => 'invoice/template_editor_aux_embedimage.tt');
    $c->detach( $c->view('TT') );
    
}




__PACKAGE__->meta->make_immutable;
1;

# vim: set tabstop=4 expandtab:
