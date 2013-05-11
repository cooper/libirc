#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# ntirc: an insanely flexible IRC client.          |
# foxy: an insanely flexible IRC bot.              |
# Copyright (c) 2011, the NoTrollPlzNet developers |
# Copyright (c) 2012, Mitchell Cooper              |
# Handlers.pm: internal IRC command handlers       |
#---------------------------------------------------
package IRC::Handlers;

use warnings;
use strict;
use feature qw(switch);

my %handlers = (
    raw_005     => \&handle_isupport,
    raw_332     => \&handle_got_topic,
    raw_333     => \&handle_got_topic_time,
    raw_353     => \&handle_namesreply,
    raw_376     => \&handle_endofmotd,
    raw_422     => \&handle_endofmotd, # no motd file
    raw_433     => \&handle_nick_taken,
    raw_privmsg => \&handle_privmsg,
    raw_nick    => \&handle_nick,
    raw_join    => \&handle_join,
    raw_part    => \&handle_part,
    raw_quit    => \&handle_quit,
    raw_cap     => \&handle_cap
);

# applies each handler to an IRC instance
sub apply_handlers {
    my $irc = shift;
    $irc->register_event(
        $_ => $handlers{$_},
        name => "libirc.$_",
        priority => 100,    # DISCUSS
        with_evented_obj => 1
    ) foreach keys %handlers;
    
    return 1;
}

# handle RPL_ISUPPORT (005)
sub handle_isupport {
    my ($irc, $event, $data, @args) = @_;

    my @stuff = @args[3..$#args];
    my $val;

    foreach my $support (@stuff) {

        return if $support =~ m/^:/; # starts with : indicates the :are supported by..
        $val = 1;

        # get BLAH=blah types
        if ($support =~ m/(.+?)=(.+)/) {
            $support = $1;
            $val     = $2;
        }

        # fire an event saying that we got the support string
        # for example, to update the network name when NETWORK is received.
        $irc->fire_event('isupport_got_'.lc($support), $val);
        $irc->{ircd}->{support}->{lc $support} = $val;

      given (uc $support) {

        # store the network name
        when ('NETWORK') {
            $irc->{network} = $val;
        }

        when ('PREFIX') {
            # prefixes are stored in $irc->{prefix}->{<status level>}
            # and their value is an array reference of [symbol, mode letter]

            # it's hard to support so many different prefixes
            # because we want pixmaps to match up on different networks.
            # the main idea is that if we can find an @, use it as 0
            # and work our way up and down from there. if we can't find
            # an @, start at the top and work our way down. this still
            # has a problem, though. networks that don't have halfop
            # will have a different pixmap for voice than networks who do.
            # so in order to avoid that we will look specially for + as well.

            # tl;dr: use 0 at @ if @ exists; otherwise start at the top and work down
            # (negative levels are likely if @ exists)

            $val =~ m/\((.+?)\)(.+)/;
            my ($modes, $prefixes, %final) = ($1, $2);

            # does it have an @?
            if ($prefixes =~ m/(.+)\@(.+)/) {
                my $current = length $1; # the number of prefixes before @ is the top level
                my @before  = split //, $1;
                my @after   = split //, $2;

                # before the @
                foreach my $symbol (@before) {
                    $final{$current} = $symbol;
                    $current--
                }

                die 'wtf..'.$current if $current != 0;
                $final{$current} = '@';
                $current--; # for the @

                # after the @
                foreach my $symbol (@after) {
                    $final{$current} = $symbol;
                    $current--
                }
            }

            # no @, so just start from the top
            else {
                my $current = length $prefixes;
                foreach my $symbol (split //, $prefixes) {
                    $final{$current} = $symbol;
                    $current--
                }
            }

            # store
            my ($i, @modes) = (0, split(//, $modes));
            foreach my $level (reverse sort { $a <=> $b } keys %final) {
                $irc->{prefix}->{$level} = [$final{$level}, $modes[$i]];
                $i++
            }

            # fire the event that says we handled prefixes
            $irc->fire_event('isupport_got_prefixes');
            
        }

        # CHANMODES tells us what modes are which.
        # we need this so we know which modes to expect to have parameters.
        # modes are stored in $irc->{chmode}->{<letter>} = { type => <type> }
        when ('CHANMODES') {

            # CHANMODES=eIb,k,fl,ACDEFGJKLMNOPQSTcgimnpstz
            # CHANMODES=
            # (0) list modes,
            # (1) modes that take parameters ALWAYS,
            # (2) modes that take parameters only when setting,
            # (3) modes that don't take parameters

            my $type = 0;
            foreach my $mode (split //, $val) {

                # next type
                if ($mode eq ',') {
                    $type++;
                    next
                }

                # store it
                $irc->{chmode}->{$mode}->{type} = $type
            }

        }

        # ugly

    } } # too much nesting

    return 1
}

sub handle_endofmotd {
    my $irc = shift;
    if ($irc->{autojoin} && ref $irc->{autojoin} eq 'ARRAY') {
        foreach my $channel (@{$irc->{autojoin}}) {
            $irc->send("JOIN $channel");
        }
        return 1
    }
    $irc->fire_event('end_of_motd');
    return
}

sub handle_privmsg {
    my ($irc, $event, $data, @args) = @_;
    my $user    = $irc->new_user_from_string($args[0]);
    my $target  = $args[2];

    # find the target
    $target = $irc->channel_from_name($target) ||
              $irc->user_from_nick($target)    ||
              do { if ($target =~ m/^[\Q$$irc{ircd}{support}{chantypes}\E]/) {
                       $irc->new_channel_from_name($target);
                   }
                   else {
                       $irc->new_user_from_nick($target);
                   }
              };

    # grab message
    my $msg = IRC::Utils::col((split /\s+/, $data, 4)[3]);

    # fire events
    $irc->fire_event(privmsg    => $user, $target, $msg);
    $target->fire_event(privmsg => $user, $msg);

}

# handle a nick change
sub handle_nick {
    my ($irc, $event, $data, @args) = @_;
    my $user = $irc->new_user_from_string($args[0]);
    my $old  = $user->{nick};
    $user->set_nick(IRC::Utils::col($args[2]));

    # tell pplz
    $irc->fire_event(user_changed_nick => $user, $old, IRC::Utils::col($args[2]));
}

# user joins a channel
sub handle_join {
    my ($irc, $event, $data, @args) = @_;
    my $user    = $irc->new_user_from_string($args[0]);
    my $channel = $irc->new_channel_from_name($args[2]);
    $channel->add_user($user);
    # If extended-join is enabled, try to get account name
    if ($irc->cap_enabled('extended-join')) 
    {
        $user->set_account($args[3]) if $args[3] ne '*'; # Set account name (* = not logged in)
    }
    $user->fire_event(joined_channel => $channel);
    $irc->fire_event(user_joined_channel => $user, $channel);
}

# user parts a channel
sub handle_part {
    my ($irc, $event, $data, @args) = @_;
    my $user    = $irc->new_user_from_string($args[0]);
    my $channel = $irc->new_channel_from_name($args[2]);
    $channel->remove_user($user);
    $channel->fire_event(user_parted => $user);
    $user->fire_event(parted_channel => $channel);
    $irc->fire_event(user_parted_channel => $user, $channel);
}

# RPL_TOPIC
sub handle_got_topic {
    my ($irc, $event, $data, @args) = @_;

    # get the channel
    my $channel = $irc->new_channel_from_name($args[3]);

    # store the topic temporarily until we get RPL_TOPICWHOTIME
    $channel->{temp_topic} = IRC::Utils::col((split /\s+/, $data, 5)[4]);
}

# RPL_TOPICWHOTIME
sub handle_got_topic_time {
    my ($irc, $event, $data, @args) = @_;

    # get the channel
    my $channel = $irc->new_channel_from_name($args[3]);
    my ($setter, $settime) = ($args[4], $args[5]);

    # set the topic
    $channel->set_topic(delete $channel->{temp_topic}, $setter, $settime);

    # fire event
    $irc->fire_event(channel_got_topic => $channel->{topic}->{topic}, $setter, $settime);
}

# RPL_NAMREPLY
sub handle_namesreply {
    my ($irc, $event, $data, @args) = @_;
    my $channel = $irc->new_channel_from_name($args[4]);

    # names with their prefixes in front
    my @names = split /\s+/, IRC::Utils::col(join ' ', @args[5..$#args]);

    # get a hash of prefixes
    my %prefixes;
    foreach my $level (keys %{$irc->{prefix}}) {
        $prefixes{$irc->{prefix}->{$level}->[0]} = $level
    }

    NICK: foreach my $nick (@names) {

        # status levels to apply
        my @levels;

        LETTER: foreach my $letter (split //, $nick) {

            # is it a prefix?
            if (exists $prefixes{$letter}) {
                $nick =~ s/.//;

                # add to the levels to apply
                push @levels, $prefixes{$letter}
            }

            # not a prefix
            else {
                last LETTER
            }

        }

        my $user = $irc->new_user_from_nick($nick);
        $user->set_nick($nick);

        # add the user to the channel
        $channel->add_user($user);

        # apply the levels
        foreach my $level (@levels) {
            $channel->set_status($user, $level);
            $irc->fire_event(channel_set_user_status => $user, $level);
        }

    }
}

sub handle_nick_taken {
    my ($irc, $event, $data, @args) = @_;
    my $nick = $args[3];
    $irc->fire_event(nick_taken => $nick);
}

sub handle_quit {
    my ($irc, $event, $data, @args) = @_;
    my $user   = $irc->new_user_from_string($args[0]);
    my $reason = defined $args[2] ? IRC::Utils::col((split /\s+/, $data, 3)[2]) : undef;

    # remove user from all channels
    foreach my $channel ($user->channels) {
        $channel->remove_user($user);
        $channel->fire_event(user_quit => $user, $reason);
    }

    # remove user from IRC object
    delete $user->{irc};
    delete $irc->{users}->{lc $user->{nick}};

    $user->fire_event(quit => $reason);
    $irc->fire_event(user_quit => $user, $reason);
}

# Handle CAP
sub handle_cap {
    my ($irc, $event, $data, @args) = @_;
    my $subcommand = $args[3];
    my $params = IRC::Utils::col(join ' ', @args[4..$#args]);
    given (uc $subcommand)
    {
        when ('LS')
        {
            $irc->{ircd}->{capab}->{$_} = 1 foreach (split(' ', $params));
        }
        when ('ACK')
        {
            foreach (split(' ', $params))
            {
                if ($_ =~ m/^(-|~|=)(.*)$/)
                {
                    delete $irc->{active_capab}->{$2} if $1 eq '-';
                    $irc->send("CAP ACK $2") if $1 eq '~'; # XXX rework this logic
                }
                else
                {
                    $irc->{active_capab}->{$_} = 1;
                    $irc->fire_event(cap_ack => $_);
                }
            }
        }
    }
}

1

