package NGCP::Panel::Form::EmailTemplate::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    required => 1,
    maxlength => 255,
);

has_field 'from_email' => (
    type => 'Text',
    label => 'From Email Address',
    required => 1,
);

has_field 'subject' => (
    type => 'Text',
    label => 'Subject',
    required => 1,
    maxlength => 255,
);

has_field 'body' => (
    type => 'TextArea',
    required => 1,
    label => 'Body Template',
    cols => 200,
    rows => 10,
    maxlength => '67108864', # 64MB
    element_class => [qw/ngcp-autoconf-area/],
    default => <<'EOS_DEFAULT_TEXT',
Dear Customer,

A new subscriber [% subscriber %] has been created for you.

Please go to [% url %] to set your password and log into your self-care interface.

Your faithful Sipwise system

-- 
This is an automatically generated message. Do not reply.
EOS_DEFAULT_TEXT
);

has_field 'attachment_name' => (
    type => 'Text',
    label => 'Attachment Name',
    required => 0,
    maxlength => 255,
    default => "",
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/name from_email subject body attachment_name/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate {
    my ($self, $field) = @_;
    my $c = $self->ctx;
    return unless $c;
    my $schema = $c->model('DB');

    my $name = $self->field('name')->value;
    my $reseller_id;
    #Todo: to some utils?
    if ($c->user->roles eq 'admin') {
        if ($self->field('reseller')) {
            $reseller_id = $self->field('reseller')->field('id')->value;
        }
    } else {
        $reseller_id = $c->user->reseller_id
    }
    #/todo
    my $existing_item = $schema->resultset('email_templates')->find({
        name => $name,
        reseller_id => $reseller_id,
    });
    my $current_item = $self->item ? $self->item : $c->stash->{tmpl};
    my $current_item_id = 
        $current_item 
            ? ref $current_item eq 'HASH' 
                ? $current_item->{id} : $current_item->id
            : undef;
    if ($existing_item && (!$current_item_id || $existing_item->id != $current_item_id)) {
        $self->field('name')->add_error($c->loc('This name already exists'));
    }
}

1;

# vim: set tabstop=4 expandtab:
