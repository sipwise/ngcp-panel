package NGCP::Panel::Form::CallListSuppression::Suppression;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

use NGCP::Panel::Utils::Form;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'domain' => (
    type => 'Text',
    label => 'Domain',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The domain of subscribers, this call list suppression applies to. An empty domain means to apply it to subscribers of any domain.']
    },
);

has_field 'direction' => (
    type => 'Select',
    label => 'Direction',
    options => [
        { value => 'outgoing', label => 'outgoing' },
        { value => 'incoming', label => 'incoming' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The direction of calls this call list suppression applies to.']
    },
    required => 1,
);

has_field 'pattern' => (
    type => 'Text',
    label => 'Pattern',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['A regular expression the dialed number (CDR \'destination user in\') has to match in case of \'outgoing\' direction, or the inbound number (CDR \'source cli\') in case of \'incoming\' direction.']
    },
);

has_field 'mode' => (
    type => 'Select',
    label => 'Mode',
    options => [
        { value => 'filter', label => 'filter' },
        { value => 'obfuscate', label => 'obfuscate' },
        { value => 'disabled', label => 'disabled' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The suppression mode. For subscriber and subscriber admins, filtering means matching calls are not listed at all, while obfuscation means the number is replaced by the given label.']
    },
    required => 1,
);

has_field 'label' => (
    type => 'Text',
    label => 'Label',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The replacement string in case of obfuscation mode. Admin and reseller users see it for filter mode suppressions.']
    },
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
    render_list => [qw/domain direction pattern mode label/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
