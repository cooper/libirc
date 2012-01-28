#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# Copyright (c) 2011, the NoTrollPlzNet developers |
# IRC/Functions/IRC: send functions for IRC class  |
#---------------------------------------------------
package IRC::Functions::IRC;

use warnings;
use strict;

sub send_nick {
    my ($irc, $newnick) = @_;
    $irc->send("NICK $newnick");
}

1
