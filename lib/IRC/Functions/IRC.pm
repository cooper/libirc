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

# Chnage nickname
sub send_nick {
    my ($irc, $newnick) = @_;
    $irc->send("NICK $newnick");
}

# Join a channel
sub send_join {
    my ($irc, $channel_name, $key) = @_;
    $irc->send("JOIN $channel_name".(defined $key ? q( ).$key : q()));
}

# Part a channel
sub send_part {
    my ($irc, $channel, $reason) = @_;
    $channel = blessed $channel ? $channel : $irc->new_channel_from_name($channel);
    $irc->send("PART $$channel".(defined $reason ? " :$reason" : q..));
}

# Send away
sub send_away {
    my ($irc, $reason) = @_;
    $irc->send("AWAY ".(defined $reason ? " :$reason" : q..));
}

# traditional WHO.
sub send_who {
    my ($irc, $query) = @_;
    $irc->send("WHO $query");
}

# WHO with WHOX flags.
sub send_whox {
    my ($irc, $query, $flags) = @_;
    ($irc->{_whox_id} ||= 0)++;
    
    # we cannot have more than three digits.
    $irc->{_whox_id} = 0 if $irc->{_whox_id} == 1000;
    my $id = sprintf '%03d', $irc->{_whox_id};
    
    # store the flags for this ID.
    $irc->{_whox_flags}{$id} = [ split //, $flags ];
    
    $irc->send("WHO $query \%$flags,$id");
}

# Oper up
sub send_oper {
    my ($irc, $user, $password) = @_;
    $irc->send("OPER $user $password");
}

# Send a message
sub send_privmsg {
    my ($irc, $target, $message) = @_;
    $target = $$target if blessed $target; # We only care for $target as a string
    $irc->send("PRIVMSG $target :$message");
}

# Send a notice
sub send_notice {
    my ($irc, $target, $message) = @_;
    $target = $$target if blessed $target; # We only care for $target as a string
    $irc->send("NOTICE $target :$message");
}

# Send an invite
sub send_invite {
    my ($irc, $user, $channel) = @_;
    # We want these as strings only
    $user = $$user if blessed $user;
    $channel = $$channel if blessed $channel;
    $irc->send("INVITE $user $channel");
}

# Kick a user
sub send_kick {
    my ($irc, $channel, $user, $reason) = @_;
    # We want these as strings only
    $user = $$user if blessed $user;
    $channel = $$channel if blessed $channel;         
    $channel->irc->send("KICK $channel ".$user.(defined $reason ? " :$reason" : q..));
}

# Set / Get topic
sub send_topic {
    my ($irc, $channel, $topic) = @_;
    $channel = $$channel if blessed $channel; # We only care for $channel as a string.
    $irc->send("TOPIC $channel".(defined $topic ? " :$topic" : q..));
}

# Set / Get modes
sub send_mode {
    my ($irc, $target, $modes) = @_;
    $target = $$target if blessed $target;
    $irc->send("MODE $target".(defined $modes ? q( ).$modes : q()));
}

1
