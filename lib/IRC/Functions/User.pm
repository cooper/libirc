#----------------------------------------------------
# libirc: an insanely flexible perl IRC library.    |
# ntirc: an insanely flexible IRC client.           |
# foxy: an insanely flexible IRC bot.               |
# Copyright (c) 2011, the NoTrollPlzNet developers  |
# Copyright (c) 2012, Mitchell Cooper               |
# IRC/Functions/User: send functions for user class |
#----------------------------------------------------
package IRC::Functions::User;

use warnings;
use strict;

sub send_privmsg {
    my ($user, $msg) = @_;
    $user->irc->send_privmsg($user, $msg);
}

sub send_notice {
    my ($user, $msg) = @_;
    $user->irc->send_notice($user, $msg);
}

sub send_invite {
    my ($user, $channel) = @_;
    $user->irc->send_invite($user, $channel);
}

1
