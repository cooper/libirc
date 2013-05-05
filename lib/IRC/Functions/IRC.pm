#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# ntirc: an insanely flexible IRC client.          |
# foxy: an insanely flexible IRC bot.              |
# Copyright (c) 2011, the NoTrollPlzNet developers |
# Copyright (c) 2012, Mitchell Cooper              |
# IRC/Functions/IRC: send functions for IRC class  |
#---------------------------------------------------
package IRC::Functions::IRC;

use warnings;
use strict;

sub send_nick {
    my ($irc, $newnick) = @_;
    $irc->send("NICK $newnick");
}

sub send_join {
    my ($irc, $channel_name, $key) = @_;
    $irc->send("JOIN $channel_name".(defined $key ? q( ).$key : q()));
}

1
