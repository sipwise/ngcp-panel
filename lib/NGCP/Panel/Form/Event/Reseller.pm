package NGCP::Panel::Form::Event::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden'
);

has_field 'type' => (
    type => 'Text',
    label => 'The event type.',
    required => 1,
);

#has_field 'type' => (
#    type => 'Select',
#    label => 'The top-up request type.',
#    options => [
#        { value => 'cash', label => 'Cash top-up' },
#        { value => 'voucher', label => 'Voucher top-up' },
#    ],
#    required => 1,
#);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    label => 'The subscriber the event is related to.',
    required => 1,
);

has_field 'old_status' => (
    type => 'Text',
    label => 'Status information before the event, if applicable.',
    required => 0,
);

has_field 'new_status' => (
    type => 'Text',
    label => 'Status information after the event, if applicable.',
    required => 0,
);

has_field 'timestamp' => (
    type => '+NGCP::Panel::Field::DateTime',
    label => 'The timestamp of the event.',
    required => 1,
);


has_field 'primary_number_id' => (
    type => 'PosInteger',
    label => 'The subscriber\'s primary number.',
    required => 0,
);
has_field 'primary_number_ac' => (
    type => 'Text',
    label => 'The subscriber\'s primary number area code.',
    required => 0,
);
has_field 'primary_number_cc' => (
    type => 'Text',
    label => 'The subscriber\'s primary number country code.',
    required => 0,
);
has_field 'primary_number_sn' => (
    type => 'Text',
    label => 'The subscriber\'s primary number subscriber number.',
    required => 0,
);
has_field 'subscriber_profile_id' => (
    type => 'PosInteger',
    label => 'The subscriber\'s profile.',
    required => 0,
);
has_field 'subscriber_profile_name' => (
    type => 'Text',
    label => 'The subscriber\'s profile name.',
    required => 0,
);
has_field 'subscriber_profile_set_id' => (
    type => 'PosInteger',
    label => 'The subscriber\'s profile set.',
    required => 0,
);
has_field 'subscriber_profile_set_name' => (
    type => 'Text',
    label => 'The subscriber\'s profile set name.',
    required => 0,
);


has_field 'pilot_subscriber_id' => (
    type => 'PosInteger',
    label => 'The pilot subscriber of the subscriber the event is related to.',
    required => 0,
);


has_field 'pilot_primary_number_id' => (
    type => 'PosInteger',
    label => 'The primary number of the subscriber\'s pilot subscriber.',
    required => 0,
);
has_field 'pilot_primary_number_ac' => (
    type => 'Text',
    label => 'The primary number area code of the subscriber\'s pilot subscriber.',
    required => 0,
);
has_field 'pilot_primary_number_cc' => (
    type => 'Text',
    label => 'The primary number country code of the subscriber\'s pilot subscriber.',
    required => 0,
);
has_field 'pilot_primary_number_sn' => (
    type => 'Text',
    label => 'The primary number subscriber number of the subscriber\'s pilot subscriber.',
    required => 0,
);
has_field 'pilot_subscriber_profile_id' => (
    type => 'PosInteger',
    label => 'The profile of the subscriber\'s pilot subscriber.',
    required => 0,
);
has_field 'pilot_subscriber_profile_name' => (
    type => 'Text',
    label => 'The profile name of the subscriber\'s pilot subscriber.',
    required => 0,
);
has_field 'pilot_subscriber_profile_set_id' => (
    type => 'PosInteger',
    label => 'The profile set of the subscriber\'s pilot subscriber.',
    required => 0,
);
has_field 'pilot_subscriber_profile_set_name' => (
    type => 'Text',
    label => 'The profile set name of the subscriber\'s pilot subscriber.',
    required => 0,
);

has_field 'first_non_primary_alias_username_before' => (
    type => 'Text',
    label => 'The subscriber\'s non-primary alias with lowest id, before number updates during the operation.',
    required => 0,
);
has_field 'first_non_primary_alias_username_after' => (
    type => 'Text',
    label => 'The subscriber\'s non-primary alias with lowest id, after number updates during the operation.',
    required => 0,
);
has_field 'pilot_first_non_primary_alias_username_before' => (
    type => 'Text',
    label => 'The non-primary alias with lowest id of the subscriber\'s pilot subscriber, before number updates during the operation.',
    required => 0,
);
has_field 'pilot_first_non_primary_alias_username_after' => (
    type => 'Text',
    label => 'The non-primary alias with lowest id of the subscriber\'s pilot subscriber, after number updates during the operation.',
    required => 0,
);

1;
