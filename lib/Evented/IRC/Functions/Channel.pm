#----------------------------------------------------------
# libirc: an insanely flexible perl IRC library.          |
# ntirc: an insanely flexible IRC client.                 |
# foxy: an insanely flexible IRC bot.                     |
# Copyright (c) 2011, the NoTrollPlzNet developers        |
# Copyright (c) 2012, Mitchell Cooper                     |
# IRC/Functions/Channel: send functions for channel class |
#----------------------------------------------------------
package Evented::IRC::Functions::Channel;

use warnings;
use strict;

sub send_privmsg {
    my ($channel, $msg) = @_;
    $channel->irc->send_privmsg($channel, $msg);
}

sub send_notice {
    my ($channel, $msg) = @_;
    $channel->irc->send_notice($channel, $msg);
}

sub send_topic {
    my ($channel, $msg) = @_;
    $channel->irc->send_topic($channel, $msg);
}

sub send_kick {
    my ($channel, $user, $reason) = @_;
    $channel->irc->send_kick($channel, $user, $reason);
}

sub send_invite {
    my ($channel, $user) = @_;
    $channel->irc->send_invite($user, $channel);
}

sub send_part {
    my ($channel, $reason) = @_;
    $channel->irc->send_part($channel, $reason);
}

sub send_mode {
    my ($channel, $modes) = @_;
    $channel->irc->send_mode($channel, $modes);
}

1
