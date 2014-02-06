package NGCP::Panel::Utils::DbStrings;

use warnings;
use strict;

sub localize {

    $c->loc('Lock Level');
    $c->loc('See "lock_voip_account_subscriber" for a list of possible values. A lock value of "none" will not be returned to the caller. Read-only setting.');
    $c->loc('Block Mode for inbound calls');
    $c->loc('Specifies the operational mode of the incoming block list. If unset or set to a false value, it is a blacklist (accept all calls except from numbers listed in the block list), with a true value it is a whitelist (reject all calls except from numbers listed in the block list).');
    $c->loc('Block List for inbound calls');
    $c->loc('Contains wildcarded SIP usernames (the localpart of the whole SIP URI, eg., "user" of SIP URI "user@example.com") that are (not) allowed to call the subscriber. "*", "?" and "~[x-y~]" with "x" and "y" representing numbers from 0 to 9 may be used as wildcards like in shell patterns.');
    $c->loc('Block anonymous inbound calls');
    $c->loc('Incoming anonymous calls (with calling line identification restriction) are blocked if set to true.');
    $c->loc('Block Mode for outbound calls');
    $c->loc('Specifies the operational mode of the outgoing block list. If unset or set to a false value, it is a blacklist (allow all calls except to numbers listed in the block list), with a true value it is a whitelist (deny all calls except to numbers listed in the block list).');
    $c->loc('Block List for outbound calls');
    $c->loc('Contains wildcarded SIP usernames (the localpart of the whole SIP URI, eg., "user" of SIP URI "user@example.com") that are (not) allowed to be called by the subscriber. "*", "?" and "~[x-y~]" with "x" and "y" representing numbers from 0 to 9 may be used as wildcards like in shell patterns.');
    $c->loc('Administrative Block Mode for inbound calls');
    $c->loc('Same as "block_in_mode" but may only be set by administrators.');
    $c->loc('Administrative Block List for inbound calls');
    $c->loc('Same as "block_in_list" but may only be set by administrators and is applied prior to the user setting.');
    $c->loc('Administratively block anonymous inbound calls');
    $c->loc('Same as "block_in_clir" but may only be set by administrators and is applied prior to the user setting.');
    $c->loc('Administrative Block Mode for outbound calls');
    $c->loc('Same as "block_out_mode" but may only be set by administrators.');
    $c->loc('Administrative Block List for outbound calls');
    $c->loc('Same as "block_out_list" but may only be set by administrators and is applied prior to the user setting.');
    $c->loc('Internal Call Forward Unconditional #');
    $c->loc('The id pointing to the "Call Forward Unconditional" entry in the voip_cf_mappings table');
    $c->loc('Internal Call Forward Busy map #');
    $c->loc('The id pointing to the "Call Forward Busy" entry in the voip_cf_mappings table');
    $c->loc('Internal Call Forward Unavailable #');
    $c->loc('The id pointing to the "Call Forward Unavailable" entry in the voip_cf_mappings table');
    $c->loc('Internal Call Forward Timeout #');
    $c->loc('The id pointing to the "Call Forward Timeout" entry in the voip_cf_mappings table');
    $c->loc('Ring Timeout for CFT');
    $c->loc('Specifies how many seconds the system should wait before redirecting the call if "cft" is set.');
    $c->loc('Network-Provided CLI');
    $c->loc('SIP username (the localpart of the whole SIP URI, eg., "user" of SIP URI "user@example.com"). "network-provided calling line identification" - specifies the SIP username that is used for outgoing calls in the SIP "From" and "P-Asserted-Identity" headers (as user- and network-provided calling numbers). The content of the "From" header may be overridden by the "user_cli" preference and client (if allowed by the "allowed_clis" preference) SIP signalling. Automatically set to the primary E.164 number specified in the subscriber details.');
    $c->loc('Hide own number for outbound calls');
    $c->loc('"Calling line identification restriction" - if set to true, the CLI is not displayed on outgoing calls.');
    $c->loc('Country Code');
    $c->loc('The country code that will be used for routing of dialed numbers without a country code. Defaults to the country code of the E.164 number if the subscriber has one.');
    $c->loc('Area Code');
    $c->loc('The area code that will be used for routing of dialed numbers without an area code. Defaults to the area code of the E.164 number if the subscriber has one.');
    $c->loc('Emergency Prefix varible');
    $c->loc('A numeric string intended to be used in rewrite rules for emergency numbers.');
    $c->loc('Internal NCOS Level #');
    $c->loc('Internal Administrative NCOS Level #');
    $c->loc('NCOS Level');
    $c->loc('Specifies the NCOS level that applies to the user.');
    $c->loc('Administrative NCOS Level');
    $c->loc('Same as "ncos", but may only be set by administrators and is applied prior to the user setting.');
    $c->loc('PIN to bypass outbound Block List');
    $c->loc('A PIN code which may be used in a VSC to disable the outgoing user block list and NCOS level for a call.');
    $c->loc('Administrative PIN to bypass outbound Block List');
    $c->loc('Same as "block_out_override_pin" but additionally disables the administrative block list and NCOS level.');
    $c->loc('Peer Authentication User');
    $c->loc('A username used for authentication against the peer host.');
    $c->loc('Peer Authentication Password');
    $c->loc('A password used for authentication against the peer host.');
    $c->loc('Allow inbound calls from foreign subscribers');
    $c->loc('Allow unauthenticated inbound calls from FOREIGN domain to users within this domain. Use with care - it allows to flood your users with voice spam.');
    $c->loc('Peer Authentication Domain');
    $c->loc('A realm (hostname) used to identify and for authentication against a peer host.');
    $c->loc('Enable Peer Authentication');
    $c->loc('Specifies whether registration at the peer host is desired.');
    $c->loc('Total max of overall concurrent calls');
    $c->loc('Maximum number of concurrent sessions (calls) for a subscriber or peer.');
    $c->loc('Total max of outbound concurrent calls');
    $c->loc('Maximum number of concurrent outgoing sessions (calls) coming from a subscriber or going to a peer.');
    $c->loc('Allowed CLIs for outbound calls');
    $c->loc('A list of shell patterns specifying which CLIs are allowed to be set by the subscriber. "*", "?" and "~[x-y~]" with "x" and "y" representing numbers from 0 to 9 may be used as wildcards as usual in shell patterns.');
    $c->loc('Force outbound calls to peer');
    $c->loc('Force calls from this user/domain/peer to be routed to PSTN even if the callee is local. Use with caution, as this setting may increase your costs! When enabling this option in a peer, make sure you trust it, as the NGCP will become an open relay for it!');
    $c->loc('Internal Contract #');
    $c->loc('External Contract #');
    $c->loc('External Subscriber #');
    $c->loc('Find Subscriber by UUID');
    $c->loc('For incoming calls from this peer, find the destination subscriber by a uuid parameter in R-URI which has been sent in Contact at outbound registration.');
    $c->loc('Rewrite Rule Set');
    $c->loc('Specifies the list of caller and callee rewrite rules which should be applied for incoming and outgoing calls.');
    $c->loc('Internal # for inbound caller rewrite rule set');
    $c->loc('Internal # for inbound callee rewrite rule set');
    $c->loc('Internal # for outbound caller rewrite rule set');
    $c->loc('Internal # for outbound callee rewrite rule set');
    $c->loc('Use Number instead of Contact first for outbound calls');
    $c->loc('Send the E164 number instead of SIP AOR as request username when sending INVITE to the subscriber. If a 404 is received the SIP AOR is sent as request URI as fallback.');
    $c->loc('User-Provided Number');
    $c->loc('SIP username (the localpart of the whole SIP URI, eg., "user" of SIP URI "user@example.com"). "user-provided calling line identification" - specifies the SIP username that is used for outgoing calls. If set, this is put in the SIP "From" header (as user-provided calling number) if a client sends a CLI which is not allowed by "allowed_clis" or if "allowed_clis" is not set.');
    $c->loc('Enable Prepaid');
    $c->loc('Force inbound calls to peer');
    $c->loc('Force calls to this user to be treated as if the user was not local. This helps in migration scenarios.');
    $c->loc('Emergency Suffix variable');
    $c->loc('A numeric string intended to be used in rewrite rules for emergency numbers.');
    $c->loc('Enable Session-Timers');
    $c->loc('Enable SIP Session Timers.');
    $c->loc('Session-Timer Refresh Interval');
    $c->loc('SIP Session Timers refresh interval (seconds). Should be always greater than min_timer preference. SBC will make refresh at the half of this interval.');
    $c->loc('Session-Timer Min Refresh Interval');
    $c->loc('Set Min-SE value in SBC. This is also used to build 422 reply if remote Min-SE is smaller than local Min-SE.');
    $c->loc('Session-Timer Max Refresh Interval');
    $c->loc('Sets upper limit on accepted Min-SE value in in SBC.');
    $c->loc('Session-Timer Refresh Method');
    $c->loc('SIP Session Timers refresh method.');
    $c->loc('System Sound Set');
    $c->loc('Sound Set used for system prompts like error announcements etc.');
    $c->loc('Reject Emergency Calls');
    $c->loc('Reject emergency calls from this user or domain.');
    $c->loc('Emergency CLI');
    $c->loc('SIP username (the localpart of the whole SIP URI, eg., "user" of SIP URI "user@example.com"). Emergency CLI which can be used in rewrite rules as substitution value.');
    $c->loc('Force outbound call via socket');
    $c->loc('Outbound socket to be used for SIP communication to this entity');
    $c->loc('Inbound User-Provided Number');
    $c->loc('The SIP header field to fetch the user-provided-number from for inbound calls');
    $c->loc('Inbound Network-Provided Number');
    $c->loc('The SIP header field to fetch the network-provided-number from for inbound calls');
    $c->loc('Outbound From-Username Field');
    $c->loc('The content to put into the From username for outbound calls from the platform to the subscriber');
    $c->loc('Outbound From-Display Field');
    $c->loc('The content to put into the From display-name for outbound calls from the platform to the subscriber');
    $c->loc('Outbound PAI-Username Field');
    $c->loc('The content to put into the P-Asserted-Identity username for outbound calls from the platform to the subscriber (use "None" to not set header at all)');
    $c->loc('Outbound PPI-Username Field');
    $c->loc('The content to put into the P-Preferred-Identity username for outbound calls from the platform to the subscriber (use "None" to not set header at all)');
    $c->loc('Enable Apple/Google Mobile Push');
    $c->loc('Send inbound call to Mobile Push server when called subscriber is not registered. This can not be used together with CFNA as call will be then simply forwarded.');
    $c->loc('Use valid Alias CLI as NPN');
    $c->loc('Search for partial match of user-provided number (UPN) to subscriber\'s  primary E164 number and aliases. If it mathes, take UPN as valid wihout allowed_clis check and copy UPN to network-provided number (NPN).');
    $c->loc('Total max of overall calls of Customer');
    $c->loc('Maximum number of concurrent sessions (calls) for subscribers within the same account');
    $c->loc('Total max of outbound calls of Customer');
    $c->loc('Maximum number of concurrent outgoing sessions (calls) for subscribers within the same account');
    $c->loc('Inbound User-Provided Redirecting Number');
    $c->loc('Specifies the way to obtain the User-Provided Redirecting CLI. Possible options are use NPN of forwarding subscriber or respect inbound Diversion header. Same validation rules as for UPN apply to UPRN. NGCP does not stack UPRNs up if the call is forwarded several times.');
    $c->loc('Outbound Diversion Header');
    $c->loc('The content to put into the Diversion header for outbound calls (use "None" to not set header at all)');
    $c->loc('Internal allowed source IP group #');
    $c->loc('Group of addresses and/or IP nets allowed access.');
    $c->loc('Internal manual allowed source IP group #');
    $c->loc('Group of addresses and/or IP nets allowed access.');
    $c->loc('Allowed source IPs');
    $c->loc('Allow access from the given list of IP addresses and/or IP nets.');
    $c->loc('Manually defined allowed source IPs');
    $c->loc('Allow access from the given list of IP addresses and/or IP nets.');
    $c->loc('Ignore allowed IPs');
    $c->loc('Ignore preferences "allowed_ips" and "man_allowed_ips".');
    $c->loc('Disable NAT SIP pings');
    $c->loc('Don\'t do NAT ping for domain/user. Use with caution: this only makes sense on the access network which does not need pings (e.g. CDMA)');
    $c->loc('IP Header Field');
    $c->loc('The SIP header to take the IP address for logging it into CDRs.');
    $c->loc('RTP-Proxy Mode');
    $c->loc('Set RTP relay mode for this peer/domain/user');
    $c->loc('IPv4/IPv6 briding mode');
    $c->loc('Choose the logic of IPv4/IPv6 autodetection for the RTP relay');
    $c->loc('Allow calls to foreign domains');
    $c->loc('Allow outbound calls of local subscribers to foreign domains');
    $c->loc('Mobile Push Expiry Timeout');
    $c->loc('The expiry interval of sent push request. Client is expected to register within this time, otherwise he should treat the request as outdated and ignore.');
    $c->loc('CloudPBX Subscriber');
    $c->loc('Send the calls from/to the subscribers through the cloud pbx module.');
    $c->loc('SRTP Transcoding Mode');
    $c->loc('Choose the logic for RTP/SRTP transcoding (SAVP profile) for the RTP relay');
    $c->loc('RTCP Feedback Mode');
    $c->loc('Choose the logic for local RTCP feedback (AVPF profile) for the RTP relay');
    $c->loc('CloudPBX Hunt Policy');
    $c->loc('The hunting policy for PBX hunt groups.');
    $c->loc('CloudPBX Serial Hunt Timeout');
    $c->loc('The serial timeout for hunting in PBX hunt groups.');
    $c->loc('CloudPBX Hunt Group List');
    $c->loc('The members (as SIP URIs) of the PBX hunt group.');
    $c->loc('CLI of CloudPBX Pilot Subscriber');
    $c->loc('The base CLI for the PBX extension.');
    $c->loc('Export subscriber to shared XMPP Buddylist');
    $c->loc('Export this subscriber into the shared XMPP buddy list for the customer.');
    $c->loc('Network-Provided Display Name');
    $c->loc('The network-provided display name used for XMPP contacts and optionally SIP outbound header manipulation.');
    $c->loc('Customer Sound Set');
    $c->loc('Customer specific Sound Set used for PBX auto-attendant prompts, customer-specific announcements etc.');
    $c->loc('api test pref');
    $c->loc('api test pref');
    $c->loc('Call Forwards');
    $c->loc('Call Blockings');
    $c->loc('Access Restrictions');
    $c->loc('Number Manipulations');
    $c->loc('NAT and Media Flow Control');
    $c->loc('Remote Authentication');
    $c->loc('Session Timers');
    $c->loc('Internals');
    $c->loc('Cloud PBX');
    $c->loc('XMPP Settings');
    return;
}

sub form_strings {

    #NGCP::Panel::Form::BillingFee
    #NGCP::Panel::Form::BillingFeeUpload
    #NGCP::Panel::Form::BillingPeaktimeSpecial
    #NGCP::Panel::Form::BillingPeaktimeWeekdays
    #NGCP::Panel::Form::BillingZone
    #NGCP::Panel::Form::CustomerBalance
    #NGCP::Panel::Form::CustomerDailyFraud
    #NGCP::Panel::Form::CustomerMonthlyFraud
    #NGCP::Panel::Form::DestinationSet
    #NGCP::Panel::Form::Login
    #NGCP::Panel::Form::PeeringGroup
    #NGCP::Panel::Form::PeeringRule
    #NGCP::Panel::Form::PeeringServer
    #NGCP::Panel::Form::Preferences
    #NGCP::Panel::Form::Reminder
    #NGCP::Panel::Form::Reseller
    #NGCP::Panel::Form::Statistics
    #NGCP::Panel::Form::Subscriber
    #NGCP::Panel::Form::SubscriberCFAdvanced
    #NGCP::Panel::Form::SubscriberCFSimple
    #NGCP::Panel::Form::SubscriberCFTAdvanced
    #NGCP::Panel::Form::SubscriberCFTSimple
    #NGCP::Panel::Form::SubscriberEdit
    #NGCP::Panel::Form::TimeSet
    #NGCP::Panel::Form::Administrator::Admin
    #NGCP::Panel::Form::Administrator::APIDownDelete
    #NGCP::Panel::Form::Administrator::APIGenerate
    #NGCP::Panel::Form::Administrator::Reseller
    #NGCP::Panel::Form::BillingProfile::Admin
    #NGCP::Panel::Form::BillingProfile::Reseller
    #NGCP::Panel::Form::Contact::Admin
    #NGCP::Panel::Form::Contact::Reseller
    #NGCP::Panel::Form::Contract::Basic
    #NGCP::Panel::Form::Contract::PeeringReseller
    #NGCP::Panel::Form::Contract::ProductSelect
    #NGCP::Panel::Form::Customer::PbxAdminSubscriber
    #NGCP::Panel::Form::Customer::PbxExtensionSubscriber
    #NGCP::Panel::Form::Customer::PbxExtensionSubscriberEdit
    #NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditAdmin
    #NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadmin
    #NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadminNoGroup
    #NGCP::Panel::Form::Customer::PbxFieldDevice
    #NGCP::Panel::Form::Customer::PbxFieldDeviceEdit
    #NGCP::Panel::Form::Customer::PbxFieldDeviceSync
    #NGCP::Panel::Form::Customer::PbxGroup
    #NGCP::Panel::Form::Customer::PbxGroupBase
    #NGCP::Panel::Form::Customer::PbxSubscriber
    #NGCP::Panel::Form::Customer::Subscriber
    #NGCP::Panel::Form::Device::Config
    #NGCP::Panel::Form::Device::Firmware
    #NGCP::Panel::Form::Device::Model
    #NGCP::Panel::Form::Device::ModelAdmin
    #NGCP::Panel::Form::Device::Profile
    #NGCP::Panel::Form::Domain::Admin
    #NGCP::Panel::Form::Domain::Reseller
    #NGCP::Panel::Form::Domain::ResellerPbx
    #NGCP::Panel::Form::Faxserver::Active
    #NGCP::Panel::Form::Faxserver::Destination
    #NGCP::Panel::Form::Faxserver::Name
    #NGCP::Panel::Form::Faxserver::Password
    #NGCP::Panel::Form::Faxserver::SendCopy
    #NGCP::Panel::Form::Faxserver::SendStatus
    #NGCP::Panel::Form::NCOS::AdminLevel
    #NGCP::Panel::Form::NCOS::LocalAC
    #NGCP::Panel::Form::NCOS::Pattern
    #NGCP::Panel::Form::NCOS::ResellerLevel
    #NGCP::Panel::Form::RewriteRule::AdminSet
    #NGCP::Panel::Form::RewriteRule::CloneSet
    #NGCP::Panel::Form::RewriteRule::ResellerSet
    #NGCP::Panel::Form::RewriteRule::Rule
    #NGCP::Panel::Form::Sound::AdminSet
    #NGCP::Panel::Form::Sound::CustomerSet
    #NGCP::Panel::Form::Sound::File
    #NGCP::Panel::Form::Sound::ResellerSet
    #NGCP::Panel::Form::Subscriber::AutoAttendant
    #NGCP::Panel::Form::Subscriber::EditWebpass
    #NGCP::Panel::Form::Subscriber::Location
    #NGCP::Panel::Form::Subscriber::SpeedDial
    #NGCP::Panel::Form::Subscriber::SubscriberAPI
    #NGCP::Panel::Form::Subscriber::TrustedSource
    #NGCP::Panel::Form::Subscriber::Webfax
    #NGCP::Panel::Form::Voicemail::Attach
    #NGCP::Panel::Form::Voicemail::Delete
    #NGCP::Panel::Form::Voicemail::Email
    #NGCP::Panel::Form::Voicemail::Pin
    $c->loc('Hour');
    $c->loc('Callee');
    $c->loc('New Name');
    $c->loc('Line/Key');
    $c->loc('Loopplay');
    $c->loc('October');
    $c->loc('Field');
    $c->loc('Password');
    $c->loc('YYYY-MM-DD HH:mm:ss');
    $c->loc('Slot add');
    $c->loc('Subscriber');
    $c->loc('Source');
    $c->loc('Comma-Separated list of Email addresses to send notifications when tresholds are exceeded.');
    $c->loc('Host:');
    $c->loc('First Name');
    $c->loc('Is master');
    $c->loc('SIP Username');
    $c->loc('Caller');
    $c->loc('Send');
    $c->loc('Line add');
    $c->loc('Period');
    $c->loc('PDF');
    $c->loc('Version');
    $c->loc('Offpeak follow rate');
    $c->loc('Create Device Configuration');
    $c->loc('Wednesday');
    $c->loc('The billing zone id this fee belongs to.');
    $c->loc('Rewrite Rule Set');
    $c->loc('Sn');
    $c->loc('Upload');
    $c->loc('PIN');
    $c->loc('The contract used for this subscriber.');
    $c->loc('IVR Slots');
    $c->loc('Soundfile');
    $c->loc('Outbound');
    $c->loc('Voicemail');
    $c->loc('whitelist');
    $c->loc('The status of the contract.');
    $c->loc('The contact id this contract belongs to.');
    $c->loc('End');
    $c->loc('Numbers');
    $c->loc('Manage Time Sets');
    $c->loc('Purge existing');
    $c->loc('Interval free cash');
    $c->loc('PBX Group');
    $c->loc('The contract used for this reseller.');
    $c->loc('#');
    $c->loc('outbound');
    $c->loc('Send Copies');
    $c->loc('Create Domain');
    $c->loc('Create');
    $c->loc('Callforward controls add');
    $c->loc('Rm');
    $c->loc('Fraud daily notify');
    $c->loc('Name in Fax Header');
    $c->loc('The fraud detection threshold per month (in cents, e.g. 10000).');
    $c->loc('Uri');
    $c->loc('only once');
    $c->loc('Is PBX Group?');
    $c->loc('Start Date/Time');
    $c->loc('The fraud detection threshold per day (in cents, e.g. 1000).');
    $c->loc('Login');
    $c->loc('Year');
    $c->loc('Inbound');
    $c->loc('Create Zone');
    $c->loc('The type of feature to use on this line/key');
    $c->loc('Download in PEM Format');
    $c->loc('Day');
    $c->loc('Email');
    $c->loc('Read only');
    $c->loc('Serial Hunting Timeout');
    $c->loc('External ID');
    $c->loc('Administrative');
    $c->loc('fraud detection threshold per day, specifying cents');
    $c->loc('Period add');
    $c->loc('blacklist');
    $c->loc('incoming and outgoing');
    $c->loc('Supports Private Line');
    $c->loc('Extension Number, e.g. 101');
    $c->loc('The length of each following interval in seconds (e.g. 30).');
    $c->loc('everyday');
    $c->loc('Currency');
    $c->loc('Bootstrap Sync Parameters');
    $c->loc('Whether the subscriber can configure other subscribers within his Customer account.');
    $c->loc('The fully qualified domain name (e.g. sip.example.org).');
    $c->loc('Is superuser');
    $c->loc('The username for SIP and XMPP services.');
    $c->loc('Create Contact');
    $c->loc('Interval charge');
    $c->loc('Supports Busy Lamp Field');
    $c->loc('Interval free time');
    $c->loc('Create Group');
    $c->loc('Firmware File');
    $c->loc('Match pattern');
    $c->loc('The surname of the contact.');
    $c->loc('Company');
    $c->loc('global (including CSC)');
    $c->loc('The base fee charged per billing interval (a monthly fixed fee, e.g. 10) in Euro/Dollars/etc. This fee can be used on the invoice.');
    $c->loc('global');
    $c->loc('Whether free minutes may be used when calling this destination.');
    $c->loc('Zone Detail');
    $c->loc('Clone');
    $c->loc('The end time in format hh:mm:ss');
    $c->loc('Close');
    $c->loc('Line/Key Type');
    $c->loc('September');
    $c->loc('E.164 Number');
    $c->loc('Onpeak follow interval');
    $c->loc('Start');
    $c->loc('foreign calls');
    $c->loc('Contact URI');
    $c->loc('during Time Set');
    $c->loc('Number');
    $c->loc('Whether customers using this profile are handled prepaid.');
    $c->loc('Monthly Fraud Limit');
    $c->loc('VAT Rate');
    $c->loc('Delete');
    $c->loc('Profile');
    $c->loc('Manage Destination Sets');
    $c->loc('The name of the reseller.');
    $c->loc('Mday');
    $c->loc('Alias Number');
    $c->loc('Alias numbers');
    $c->loc('Alias number');
    $c->loc('where e-mail notifications are sent, a list of e-mail addreses separated by comma');
    $c->loc('Level Name');
    $c->loc('April');
    $c->loc('Contact Email');
    $c->loc('File Type');
    $c->loc('Device Configuration');
    $c->loc('Hunting Policy');
    $c->loc('Edit time sets');
    $c->loc('Detail');
    $c->loc('URI/Number');
    $c->loc('Options to lock customer if the daily limit is exceeded.');
    $c->loc('The included free money per billing interval (in Euro, Dollars etc., e.g. 10).');
    $c->loc('Mode');
    $c->loc('The reseller id this profile belongs to.');
    $c->loc('The human-readable display name (e.g. John Doe)');
    $c->loc('The number to send the fax to');
    $c->loc('Alias number add');
    $c->loc('Billing profile');
    $c->loc('TLS');
    $c->loc('Destination');
    $c->loc('Zone');
    $c->loc('Fraud daily limit');
    $c->loc('March');
    $c->loc('Offpeak follow interval');
    $c->loc('Country Code, e.g. 1 for US or 43 for Austria');
    $c->loc('The password to log into the CSC Panel');
    $c->loc('Name');
    $c->loc('TCP');
    $c->loc('Whether the fees already incluside VAT.');
    $c->loc('E164 Number');
    $c->loc('The username to log into the CSC Panel');
    $c->loc('Area Code, e.g. 212 for NYC or 1 for Vienna');
    $c->loc('Show passwords');
    $c->loc('VAT Included');
    $c->loc('string, rule description');
    $c->loc('terminated');
    $c->loc('Fraud Monthly Notify');
    $c->loc('Onpeak follow rate');
    $c->loc('Download CA Certificate');
    $c->loc('The contact priority for serial forking (float value, higher is stronger) between -1.00 to 1.00');
    $c->loc('Web Password');
    $c->loc('Generate Certificate');
    $c->loc('SIP Domain');
    $c->loc('The number of Lines/Keys in this range, indexed from 0 in the config template array phone.lineranges~[~].lines~[~]');
    $c->loc('PDF14');
    $c->loc('A human readable profile name.');
    $c->loc('foreign');
    $c->loc('Download PKCS12');
    $c->loc('New Description');
    $c->loc('Call data');
    $c->loc('Max Subscribers');
    $c->loc('A POSIX regex matching against \'sip:user@domain\' (e.g. \'^sip:.+@example\.org$\' matching the whole URI, or \'999\' matching if the URI contains \'999\')');
    $c->loc('Tuesday');
    $c->loc('Onpeak init rate');
    $c->loc('Subscriber Number, e.g. 12345678');
    $c->loc('The Name of this range, e.g. Phone Keys or Attendant Console 1 Keys, accessible in the config template array via phone.lineranges~[~].name');
    $c->loc('Pattern');
    $c->loc('Postcode');
    $c->loc('If active and a customer is selected, this sound set is used for all existing and new subscribers within this customer if no specific sound set is specified for the subscribers');
    $c->loc('If active, this sound set is used for all existing and new subscribers if no specific sound set is specified for them');
    $c->loc('The cost of each following interval in cents per second (e.g. 0.90).');
    $c->loc('July');
    $c->loc('June');
    $c->loc('Device Profile');
    $c->loc('The call direction when to apply this fee (either for inbound or outbound calls).');
    $c->loc('The email address of the contact.');
    $c->loc('Thursday');
    $c->loc('Download in PKCS12 Format');
    $c->loc('The VAT rate in percentage (e.g. 20).');
    $c->loc('The status of the reseller.');
    $c->loc('The subscriber to use on this line/key');
    $c->loc('The two-letter ISO 3166-1 country code of the contact (e.g. US or DE).');
    $c->loc('Monday');
    $c->loc('Country');
    $c->loc('The main E.164 number (containing a cc, ac and sn attribute) used for inbound and outbound calls.');
    $c->loc('From Pattern');
    $c->loc('A unique identifier string (only alphanumeric chars and _).');
    $c->loc('The person\'s name, which is then used in XMPP contact lists or auto-provisioned phones, and which can be used as network-provided display name in SIP calls.');
    $c->loc('Line/Key Range');
    $c->loc('A POSIX regex matching against the full Request-URI (e.g. \'^sip:.+@example\.org$\' or \'^sip:431\')');
    $c->loc('The status of the subscriber.');
    $c->loc('Default for Subscribers');
    $c->loc('Cf actions');
    $c->loc('Active');
    $c->loc('Key');
    $c->loc('Is active');
    $c->loc('Receive Reports');
    $c->loc('Minute');
    $c->loc('Lines/Keys in this range can be used as regular phone lines. Value is accessible in the config template via phone.lineranges~[~].lines~[~].can_private');
    $c->loc('Options to lock customer if the monthly limit is exceeded.');
    $c->loc('MAC Address Image');
    $c->loc('Simple');
    $c->loc('The currency symbol or ISO code, used on invoices and webinterfaces.');
    $c->loc('Offpeak init interval');
    $c->loc('pending');
    $c->loc('The cost of the first interval in cents per second (e.g. 0.90).');
    $c->loc('The line/key to use');
    $c->loc('Group');
    $c->loc('Download');
    $c->loc('Whether this subscriber is used as PBX group.');
    $c->loc('The SIP username for the User-Agents');
    $c->loc('after ring timeout');
    $c->loc('all outgoing calls');
    $c->loc('The street name of the contact.');
    $c->loc('Number of Lines/Keys');
    $c->loc('Source IP');
    $c->loc('The company name of the contact.');
    $c->loc('February');
    $c->loc('Include local area code');
    $c->loc('The SIP password for the User-Agents');
    $c->loc('POST');
    $c->loc('locked');
    $c->loc('Last Name');
    $c->loc('Deliver Incoming Faxes');
    $c->loc('Parallel Ringing');
    $c->loc('Weight');
    $c->loc('Friday');
    $c->loc('Free-Time Balance');
    $c->loc('Display Name');
    $c->loc('Linerange add');
    $c->loc('Profile Name');
    $c->loc('The lock level of the subscriber.');
    $c->loc('An external id, e.g. provided by a 3rd party provisioning');
    $c->loc('Destination add');
    $c->loc('The detailed name for the zone (e.g. US Mobile Numbers).');
    $c->loc('Status');
    $c->loc('Web Username');
    $c->loc('Contract #');
    $c->loc('A short name for the zone (e.g. US).');
    $c->loc('The password to log into the CSC Panel.');
    $c->loc('December');
    $c->loc('Username');
    $c->loc('GET');
    $c->loc('Create Device Model');
    $c->loc('Destination Number');
    $c->loc('Bootstrap Sync HTTP Method');
    $c->loc('Lock Level');
    $c->loc('active');
    $c->loc('trough');
    $c->loc('Via Route');
    $c->loc('Customer');
    $c->loc('An external id, e.g. provided by a 3rd party provisioning.');
    $c->loc('A POSIX regular expression to match the calling number (e.g. ^.+$).');
    $c->loc('Save');
    $c->loc('Priority (q-value)');
    $c->loc('Callee prefix');
    $c->loc('Lawful intercept');
    $c->loc('Device Vendor');
    $c->loc('Reseller');
    $c->loc('City');
    $c->loc('Caller pattern');
    $c->loc('Subscriber can configure other subscribers within the Customer Account');
    $c->loc('Repeat');
    $c->loc('Onpeak init interval');
    $c->loc('for (seconds)');
    $c->loc('Offpeak init rate');
    $c->loc('Sign In');
    $c->loc('The domain name or domain id this subscriber belongs to.');
    $c->loc('Push Provisioning URL');
    $c->loc('Download CA Cert');
    $c->loc('The billing profile id used to charge this contract.');
    $c->loc('The city name of the contact.');
    $c->loc('outgoing');
    $c->loc('or File');
    $c->loc('The username to log into the CSC Panel.');
    $c->loc('The PBX group id this subscriber belongs to.');
    $c->loc('Fraud Monthly Limit');
    $c->loc('Port');
    $c->loc('Lines/Keys in this range can be used as shared lines. Value is accessible in the config template via phone.lineranges~[~].lines~[~].can_shared');
    $c->loc('Content Type');
    $c->loc('through');
    $c->loc('Callee pattern');
    $c->loc('Additional E.164 numbers (each containing a cc, ac and sn attribute) mapped to this subscriber for inbound calls.');
    $c->loc('PS');
    $c->loc('all calls');
    $c->loc('Street');
    $c->loc('Cash Balance');
    $c->loc('Direction');
    $c->loc('Model');
    $c->loc('Upload fees');
    $c->loc('inbound');
    $c->loc('Extension');
    $c->loc('Sunday');
    $c->loc('ANY');
    $c->loc('The reseller id to assign this domain to.');
    $c->loc('The length of the first interval in seconds (e.g. 60).');
    $c->loc('Weekday');
    $c->loc('Serial Ringing');
    $c->loc('Destination Set');
    $c->loc('A POSIX regular expression to match the called number (e.g. ^431.+$).');
    $c->loc('Domain');
    $c->loc('Replacement Pattern');
    $c->loc('Attach WAV');
    $c->loc('Billing Profile');
    $c->loc('The destination for this slot; can be a number, username or full SIP URI.');
    $c->loc('January');
    $c->loc('August');
    $c->loc('none');
    $c->loc('Edit destination sets');
    $c->loc('Send Reports');
    $c->loc('Category:');
    $c->loc('Seconds to wait for pick-up until engaging Call Forward (e.g. &ldquo;10&rdquo;)');
    $c->loc('fraud detection threshold per month, specifying cents');
    $c->loc('Use free time');
    $c->loc('Phone Number');
    $c->loc('Select');
    $c->loc('Submitid');
    $c->loc('Station Name');
    $c->loc('SIP Password');
    $c->loc('The IVR key to press for this destination');
    $c->loc('Cc');
    $c->loc('Front Image');
    $c->loc('Id');
    $c->loc('Ac');
    $c->loc('Create Reseller');
    $c->loc('UDP');
    $c->loc('Delete WAV');
    $c->loc('The given name of the contact.');
    $c->loc('The reseller id this contact belongs to.');
    $c->loc('Content');
    $c->loc('Device Model');
    $c->loc('Protocol');
    $c->loc('The postal code of the contact.');
    $c->loc('Contact');
    $c->loc('Slot');
    $c->loc('Callee prefix, eg: 43');
    $c->loc('TIFF');
    $c->loc('November');
    $c->loc('Contract');
    $c->loc('Lines/Keys in this range can be used as Busy Lamp Field. Value is accessible in the config template via phone.lineranges~[~].lines~[~].can_blf');
    $c->loc('Product');
    $c->loc('Create PBX Group');
    $c->loc('Create Billing Profile');
    $c->loc('Hostname');
    $c->loc('Download PEM');
    $c->loc('Add');
    $c->loc('Advanced');
    $c->loc('May');
    $c->loc('Supported File Types are TXT, PDF, PS, TIFF');
    $c->loc('Lines/Keys');
    $c->loc('The start time in format hh:mm:ss');
    $c->loc('Generate');
    $c->loc('End Date/Time');
    $c->loc('Priority');
    $c->loc('Wday');
    $c->loc('Optionally set the maximum number of subscribers for this contract. Leave empty for unlimited.');
    $c->loc('Time');
    $c->loc('Incoming Email as CC');
    $c->loc('Bootstrap Sync URI');
    $c->loc('The phone number of the contact.');
    $c->loc('on weekdays');
    $c->loc('Simple View');
    $c->loc('Deliver Outgoing Faxes');
    $c->loc('Vendor');
    $c->loc('Create Contract');
    $c->loc('Fraud daily lock');
    $c->loc('Fraud Monthly Lock');
    $c->loc('Daily Fraud Limit');
    $c->loc('External #');
    $c->loc('Month');
    $c->loc('MAC Address / Identifier');
    $c->loc('Prepaid');
    $c->loc('A full SIP URI like sip:user@ip:port');
    $c->loc('Active callforward');
    $c->loc('Advanced View');
    $c->loc('Saturday');
    $c->loc('Supports Shared Line');
    $c->loc('The included free minutes per billing interval (in seconds, e.g. 60000 for 1000 free minutes).');
    $c->loc('IP Address');
    $c->loc('Notify Emails');
    $c->loc('Description');
    $c->loc('The password to authenticate for SIP and XMPP services.');
    $c->loc('Handle');
    $c->loc('Delete Key');

    return;
}

1;

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

