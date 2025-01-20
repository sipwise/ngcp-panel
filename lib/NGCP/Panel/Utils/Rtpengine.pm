package NGCP::Panel::Utils::Rtpengine;

use Sipwise::Base;
use NGCP::Panel::Utils::HTTPDispatcher;
use NGCP::Panel::Utils::Sounds;
use List::Util qw(any);

sub clear_audio_cache_files {
    my ($c, @sound_ids) = @_;

    return unless @sound_ids;

    my @all;

    if (@sound_ids < 1000) {
        my @ret = NGCP::Panel::Utils::HTTPDispatcher::dispatch($c, "rtpengine", 1, 1, "POST", "text/plain",
                "media evict cache @sound_ids");
        push(@all, @ret);
        @ret = NGCP::Panel::Utils::HTTPDispatcher::dispatch($c, "rtpengine", 1, 1, "POST", "text/plain",
                "media evict db @sound_ids");
        push(@all, @ret);
    } else {
        my @ret = NGCP::Panel::Utils::HTTPDispatcher::dispatch($c, "rtpengine", 1, 1, "POST", "text/plain",
                "media evict caches");
        push(@all, @ret);
        @ret = NGCP::Panel::Utils::HTTPDispatcher::dispatch($c, "rtpengine", 1, 1, "POST", "text/plain",
                "media evict dbs");
        push(@all, @ret);
    }

    if (any { $$_[1] != 1 } @all) {
        die "failed to clear rtpengine audio cache";
    }

    return;
}

sub clear_audio_cache_set {
    my ($c, $set_id) = @_;

    my $handles = NGCP::Panel::Utils::Sounds::get_file_handles(c => $c, set_id => $set_id);
    my @db_ids = map { $_->{file_id} // () } @{$handles};
    clear_audio_cache_files($c, @db_ids);

    return;
}

1;

# vim: set tabstop=4 expandtab:
