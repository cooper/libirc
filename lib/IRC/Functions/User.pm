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
    $user->fire_event(send_privmsg => $msg);
    $user->irc->send("PRIVMSG $$user :$msg");
}

sub send_notice {
    my ($user, $msg) = @_;
    $user->fire_event(send_notice => $msg);
    $user->irc->send("NOTICE $$user :$msg");
}

sub send_invite {
    my ($user, $channel) = @_;
    $user->fire_event(send_invite => $channel);
    $user->irc->send("INVITE $$user $$channel");
}

1
