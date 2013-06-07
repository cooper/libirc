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
    $channel->irc->send_privmsg($channel, $msg);
}

sub send_notice {
    my ($channel, $msg) = @_;
    $channel->irc->send_notice($channel, $msg);
}

sub send_topic {
    my ($channel, $msg) = @_;
    $channel->irc->send("TOPIC $$channel :$msg");
}

sub send_kick {
    my ($channel, $user, $reason) = @_;
    $channel->irc->send("KICK $$channel ".$$user.(defined $reason ? " :$reason" : q..));
}

sub send_invite {
    my ($channel, $user) = @_;
    $channel->irc->send("INVITE $$user $$channel");
}

sub send_part {
    my ($channel, $reason) = @_;
    $channel->irc->send_part($channel, $reason);
}

1
