package NGCP::Panel::Form::Device::PreferenceAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Device::Preference';

has_field 'autoprov_device_id' => (
    type => 'PosInteger',
    #see comment for the dev_pref
    required => 0,
    label => 'Model id for the dynamic device model preferences',
);

has_field 'reseller_id' => (
    type => 'PosInteger',
    #see comment for the dev_pref
    required => 0,
    label => 'Reseller id for the dynamic device model preferences',
);

has_field 'dev_pref' => (
    type => 'Boolean',
    label => 'This is device model preference.',
    #until we don't create any other preference type as dynamic preference, we can keep this field required, to don't create unnecessary form validation code
    required => 1,
);

1;
# vim: set tabstop=4 expandtab:
