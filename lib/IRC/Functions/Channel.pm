#----------------------------------------------------------
# libirc: an insanely flexible perl IRC library.          |
# Copyright (c) 2011, the NoTrollPlzNet developers        |
# IRC/Functions/Channel: send functions for channel class |
#----------------------------------------------------------
package IRC::Functions::Channel;

use warnings;
use strict;

sub send_privmsg {
    my ($channel, $msg) = @_;
    $channel->fire_event(send_privmsg => $msg);
    $channel->{irc}->send("PRIVMSG $$channel{name} :$msg");
}

sub send_topic {
    my ($channel, $msg) = @_;
    $channel->fire_event(send_topic => $msg);
    $channel->{irc}->send("TOPIC $$channel{name} :$msg");
}

sub send_kick {
    my ($channel, $user, $reason) = @_;
    $channel->fire_event(send_kick => $user, $reason);
    $channel->{irc}->send("KICK $$channel{name} ".$user->{nick}.(defined $reason ? " :$reason" : q..));
}

1
