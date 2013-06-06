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
use 5.010;

my %handlers = (
    cmd_004         => \&handle_myinfo,
    cmd_005         => \&handle_isupport,
    cmd_332         => \&handle_got_topic,
    cmd_333         => \&handle_got_topic_time,
    cmd_353         => \&handle_namesreply,
    cmd_376         => \&handle_endofmotd,
    cmd_422         => \&handle_endofmotd,
    cmd_433         => \&handle_nick_taken,
    raw_903         => \&handle_sasldone,
    raw_904         => \&handle_sasldone,
    raw_906         => \&handle_sasldone,
    cmd_privmsg     => \&handle_privmsg,
    cmd_nick        => \&handle_nick,
    cmd_join        => \&handle_join,
    cmd_part        => \&handle_part,
    raw_quit        => \&handle_quit,
    cmd_cap         => \&handle_cap,
    cap_ls          => \&handle_cap_ls,
    cap_ack         => \&handle_cap_ack,
    cap_ack_sasl    => \&handle_cap_ack_sasl,
    cmd_account     => \&handle_account,
    cmd_away        => \&handle_away,
    cmd_352         => \&handle_whoreply,
    cmd_354         => \&handle_whoxreply,
    cmd_315         => \&handle_whoend
);

# applies each handler to an IRC instance
sub apply_handlers {
    my $irc = shift;
    
    $irc->register_event(
        $_               => $handlers{$_},
        name             => "libirc.$_",
        priority         => 100,    # DISCUSS
        with_evented_obj => 1
    ) foreach keys %handlers;
    
    return 1;
}

# handle RPL_ISUPPORT (005)
sub handle_isupport {
    my ($irc, @stuff) = IRC::args(@_, 'irc .source .target @stuff');

    my $val;
    foreach my $support (@stuff[0..$#stuff - 1]) {
        $val = 1;

        # get BLAH=blah types
        if ($support =~ m/(.+?)=(.+)/) {
            $support = $1;
            $val     = $2;
        }

        # fire an event saying that we got the support string
        # for example, to update the network name when NETWORK is received.
        $irc->fire_event('isupport_got_'.lc($support), $val);
        $irc->{ircd}{support}{lc $support} = $val;

      given (uc $support) {

        # store the network name
        when ('NETWORK') {
            $irc->{network} = $val;
        }

        when ('PREFIX') {
            # prefixes are stored in $irc->{ircd}{prefix}{<status level>}
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
            if ($prefixes =~ m/(.*)\@(.*)/) {
                my $current = length $1; # the number of prefixes before @ is the top level
                my @before  = $1 ? split //, $1 : ();
                my @after   = $2 ? split //, $2 : ();

                # before the @
                foreach my $symbol (@before) {
                    $final{$current} = $symbol;
                    $current--
                }

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
                $irc->{ircd}{prefix}{$level} = [ $final{$level}, $modes[$i] ];
                $i++
            }

            # fire the event that says we handled prefixes
            $irc->fire_event('isupport_got_prefixes');
            
        }

        # CHANMODES tells us what modes are which.
        # we need this so we know which modes to expect to have parameters.
        # modes are stored in $irc->{chmode}{<letter>} = { type => <type> }
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
                $irc->{chmode}{$mode}{type} = $type
            }

        }

        # ugly

    } } # too much nesting

    return 1
}

sub handle_endofmotd {
    my $irc = shift;
    if ($irc->{autojoin} && ref $irc->{autojoin} eq 'ARRAY') {
        foreach my $chan_name (@{$irc->{autojoin}}) {
            $irc->send_join($chan_name);
        }
        return 1
    }
    $irc->fire_event('end_of_motd');
    return
}

sub handle_privmsg { # :source PRIVMSG target message
    my ($irc, $source, $target, $msg) = IRC::args(@_, 'irc +source +target *msg') or return;

    # fire events
    EventedObject::fire_events_together(
        [ $irc,    privmsg     => $source, $target, $msg ], # generic privmsg for any source or target
        [ $target, got_privmsg => $source, $msg          ], # incoming from source
        [ $source, privmsg     => $target, $msg          ]  # outgoing from source
    );

}

# handle a nick change
# :user NICK new_nick
sub handle_nick {
    my ($user, $nick) = IRC::args(@_, '+user *nick') or return;
    $user->set_nick($nick);
}

# user joins a channel
sub handle_join {
    my ($irc, $user, $channel, $account, $realname) =
    IRC::args(@_, 'irc +user +channel *acct *real') or return;
    
    # add user to channel.
    $channel->add_user($user);
    
    # extended join.
    if ($irc->cap_enabled('extended-join')) {
        $user->set_account($account eq '*' ? undef : $account) if ($user->{account} || '*') ne $account;
        $user->set_real($realname);
    }
    
    # fire events.
    EventedObject::fire_events_together(
        [ $user,    joined_channel => $channel ],
        [ $channel, user_joined    => $user    ]
    );
    
}

# user parts a channel
sub handle_part {
    my ($irc, $user, $channel, $reason) =
    IRC::args(@_, 'irc +user +channel *reason') or return;

    # remove the user.
    $channel->remove_user($user);

    # first events.
    EventedObject::fire_events_together(
        [ $channel, user_parted    => $user, $reason    ],
        [ $user,    parted_channel => $channel, $reason ]
    );

}

# RPL_TOPIC
sub handle_got_topic {
    my ($channel, $topic) = IRC::args(@_, '.source .target channel *topic');
    
    # store the topic temporarily until we get RPL_TOPICWHOTIME.
    $channel->{temp_topic} = $topic;
}

# RPL_TOPICWHOTIME
sub handle_got_topic_time {
    my ($channel, $setter, $settime) = IRC::args(@_, '.source .target channel *setter *settime');

    # set the topic.
    $channel->set_topic(delete $channel->{temp_topic}, $setter, $settime);

}

# RPL_NAMREPLY
sub handle_namesreply {
    my ($irc, $channel, @names) = IRC::args(@_, 'irc .source .type .target channel @names');
    
    # get a hash of prefixes.
    my %prefixes;
    foreach my $level (keys %{ $irc->{ircd}{prefix} }) {
        $prefixes{ $irc->{ircd}{prefix}{$level}[0] } = $level
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
        $user->set_nick($nick); # XXX: why?

        # add the user to the channel
        $channel->add_user($user);

        # apply the levels
        foreach my $level (@levels) {
            $channel->add_status($user, $level);
        }

    }
}

sub handle_nick_taken {
    my ($irc, $nick) = IRC::args(@_, 'irc . . *');
    print "nick tkaen: $nick\n";
    $irc->fire_event(nick_taken => $nick);
}

sub handle_quit {
    my ($irc, $event, $data, @args) = @_;
    my $user   = $irc->new_user_from_string($args[0]);
    my $reason = defined $args[2] ? IRC::Utils::col((split /\s+/, $data, 3)[2]) : undef;

    $user->fire_event(quit => $reason);
    $irc->pool->remove_user($user);
}

# Handle CAP
sub handle_cap {
    my ($irc, $subcommand, @params) = IRC::args(@_, 'irc .server .target *sub @caps');
    $subcommand = lc $subcommand;
    $irc->fire_event("cap_$subcommand" => @params);
}

# handle CAP LS.
sub handle_cap_ls {
    my ($irc, @params) = @_;
    $irc->{ircd}{cap}{lc $_} = 1 foreach @params;
    $irc->_send_cap_requests;
}

# handle CAP ACK.
sub handle_cap_ack {
    my ($irc, @params) = @_;
    my %event_fired;
    foreach my $cap (@params) {

        # there is a modifier.
        if ($cap =~ m/^(-|~|=)(.+)$/) {
        
            # disable this cap.
            delete $irc->{active_cap}{$2} if $1 eq '-';
            
            # acknowledge our support.
            $irc->send("CAP ACK $2") if $1 eq '~' && $2 ~~ @{ $irc->{supported_cap} };
            
            # sticky.
            $irc->{sticky_cap}{$2} = 1 if $1 eq '=';
            
        }
        
        # no modifier; enable it.
        else {
            $event_fired{$cap}         =
            $irc->{active_cap}{$cap} = 1;
            $irc->fire_event("cap_ack_$cap");
        }
        
    }

    # fire cap_no_ack_* for any requests not available.
    foreach my $cap (@{ delete $irc->{pending_cap} || [] }) {
        next if $event_fired{$cap};
        
        # release this one because it's not available.
        $irc->release_login if $irc->{waiting_cap}{lc $cap};
        
        $irc->fire_event(cap_no_ack => $cap);
        $irc->fire_event("cap_no_ack_$cap");
    }

    # check if we're ready to send CAP END.
    $irc->_check_login;

}

# Handle ACCOUNT
sub handle_account {
    my ($user, $account) = IRC::args(@_, '+user *account') or return;
    $user->set_account($account eq '*' ? undef : $account);
}

# handle AWAY
sub handle_away {
    my ($user, $reason) = IRC::args(@_, '+user *reason') or return;
    $user->set_away($reason);
}

# handle SASL acknowledgement.
sub handle_cap_ack_sasl {
    my $irc = shift;
    $irc->send('AUTHENTICATE PLAIN');
    
    my $str = MIME::Base64::encode_base64(join("\0",
        $irc->{sasl_user},
        $irc->{sasl_user},
        $irc->{sasl_pass}
    ), '');
    
    if (!length $str) {
        $irc->send('AUTHENTICATE +');
        return;
    }
    
    else {

        while (length $str >= 400) {
            my $substr = substr $str, 0, 400, '';
            $irc->send("AUTHENTICATE $substr");
        }
        
        if (length $str) {
            $irc->send("AUTHENTICATE $str");
        }
        
        else {
            $irc->send('AUTHENTICATE +');
        }
        
    }
    
}

# Handle SASL completion
sub handle_sasldone {
    my $irc = shift;
    $irc->release_login;
}

# handle WHO reply
sub handle_whoreply {
    my ($irc, $channel, @params) = IRC::args(@_, 'irc .source .target channel rest');
    
    # the hops is in the real name for some reason.
    if ($params[$#params] =~ m/^[0-9]/) {
        $params[$#params] = (split ' ', $params[$#params], 2)[1];
    }
    
    # fake a -1 WHOX.
    $irc->{_whox_flags}{-1} = [qw(u h s n f r)];
    _handle_who_long($irc, -1, @params);
    
}

# handle WHOX reply.
#
# References:
#   http://pastebin.com/Qychi7yE
#   http://faerion.sourceforge.net/doc/irc/whox.var
#   http://hg.quakenet.org/snircd/file/37c9c7460603/doc/readme.who
#
sub handle_whoxreply {
    my ($irc, $id, $channel, @params) = IRC::args(@_, 'irc .source .target *id channel rest');
    _handle_who_long($irc, $id, @params);
}

sub _handle_who_long {
    my ($irc, $id, @params) = @_;
    
    # fetch flags stored for this query.
    $irc->{_whox_current_id} = $id;
    my $flags     = $irc->{_whox_flags}{$id} or return;
    my @flags     = @$flags;
    my @all_flags = qw(t c u i h s n f d l a r); # in the order they are sent
    
    my ($user, %info);
    
    # find the value of each flag.
    foreach (@all_flags) {
        my $flag = $_;
        
        # we don't have this flag or it has already been handled.
        next unless $flag ~~ @flags;
        next if $flag =~ m/[ct]/;
        
        # we do have this flag, so it's the next value of @params.
        $info{$flag} = shift @params;

    }
    
    # find the user.
    return unless defined $info{n};
    $user = $irc->new_user_from_nick($info{n}) or return;
    
    # user flags.
    if (defined $info{f}) {
        my @uflags = split //, $info{f};
        
        # user is no longer away.
        if (!('H' ~~ @uflags) && defined $user->{away}) {
            $user->set_away(undef);
        }
        
        # user is now away.
        if ('G' ~~ @uflags && !defined $user->{away}) {
            $user->set_away('YES');
        }
        
    }
    
    # hostname, username, realname, accountname.
    $user->set_host($info{h})    if defined $info{h};
    $user->set_user($info{u})    if defined $info{u};
    $user->set_real($info{r})    if defined $info{r};
    $user->set_account($info{a}) if defined $info{a};
    
    # TODO: for servers, retain for each user connected.
    # store the server by its identifier.
    # when the user object is destroyed, release the server.
    if (defined $info{s} && !$user->{server}) {
        my $server = $irc->new_server_from_name($info{s});
        $user->pool->retain($server, "user:$user:on_server");
        $user->{server} = $server->id;
    }
    
    # IP address.
    if (defined $info{i} && $info{i} ne '255.255.255.255') {
        $user->{ip} = $info{i}; # TODO: create set_ip.
    }
    
}

# handle end of WHO list.
sub handle_whoend {
    my $irc = shift;
    
    # if it was a WHOX, delete the flags.
    if (defined $irc->{_whox_current_id}) {
        delete $irc->{_whox_flags}{ delete $irc->{_whox_current_id}} ;
    }
}

# RPL_MYINFO.
sub handle_myinfo {
    my ($irc, $event, $source) = @_;
    $irc->pool->set_server_name($irc->server, $irc->server->{name}, $source->{name});
    $irc->server->{name} = $source->{name};
}

1

