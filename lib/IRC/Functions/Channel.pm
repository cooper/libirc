#----------------------------------------------------------
# libirc: an insanely flexible perl IRC library.          |
# ntirc: an insanely flexible IRC client.                 |
# foxy: an insanely flexible IRC bot.                     |
# Copyright (c) 2011, the NoTrollPlzNet developers        |
# Copyright (c) 2012, Mitchell Cooper                     |
# IRC/Functions/Channel: send functions for channel class |
#----------------------------------------------------------
package IRC::Functions::Channel;

use warnings;
use strict;

sub send_privmsg {
    my ($channel, $msg) = @_;
    $channel->fire_event(send_privmsg => $msg);
    $channel->{irc}->send("PRIVMSG $$channel :$msg");
}

sub send_notice {
    my ($channel, $msg) = @_;
    $channel->fire_event(send_notice => $msg);
    $channel->{irc}->send("NOTICE $$channel :$msg");
}

sub send_topic {
    my ($channel, $msg) = @_;
    $channel->fire_event(send_topic => $msg);
    $channel->{irc}->send("TOPIC $$channel :$msg");
}

sub send_kick {
    my ($channel, $user, $reason) = @_;
    $channel->fire_event(send_kick => $user, $reason);
    $channel->{irc}->send("KICK $$channel ".$$user.(defined $reason ? " :$reason" : q..));
}

sub send_invite {
    my ($channel, $user) = @_;
    $channel->fire_event(send_invite => $user);
    $channel->{irc}->send("INVITE $$user $$channel");
}

sub send_part {
    my ($channel, $reason) = @_;
    $channel->fire_event(send_part => $reason);
    $channel->{irc}->send("PART ".$$channel.(defined $reason ? " :$reason" : q..));
}

1
