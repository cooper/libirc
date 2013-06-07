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

    # NUMERICS

    num_004 => \&handle_myinfo,         # RPL_MYINFO:           server version and info
    num_005 => \&handle_isupport,       # RPL_ISUPPORT:         server support information
    num_315 => \&handle_whoend,         # RPL_ENDOFWHO:         End of WHO query
    num_332 => \&handle_got_topic,      # RPL_TOPIC:            channel topic
    num_333 => \&handle_got_topic_time, # RPL_TOPICWHOTIME:     topic setter and time
    num_352 => \&handle_whoreply,       # RPL_WHOREPLY:         WHO response
    num_353 => \&handle_namesreply,     # RPL_NAMREPLY:         channel names response
    num_354 => \&handle_whoxreply,      # RPL_WHOSPCRPL:        WHOX response
    num_376 => \&handle_endofmotd,      # RPL_ENDOFMOTD:        end of MOTD command
    num_422 => \&handle_endofmotd,      # ERR_NOMOTD:           MOTD file not found
    num_433 => \&handle_nick_taken,     # ERR_NICKNAMEINUSE:    nickname in use
    num_900 => \&handle_loggedin,       # RPL_LOGGEDIN:         client logged in
    num_901 => \&handle_loggedout,      # RPL_LOGGEDOUT:        client logged out
    num_903 => \&handle_sasldone,       # RPL_SASLSUCCESS:      SASL successful
    num_904 => \&handle_sasldone,       # ERR_SASLFAIL:         SASL failure
    num_905 => \&handle_sasldone,       # ERR_SASLTOOLONG:      SASL failure
    num_906 => \&handle_sasldone,       # ERR_SASLABORTED:      SASL aborted by client
  # num_907                             # ERR_SASLALREADY:      AUTHENTICATE used twice
  # num_908                             # RPL_SASLMECHS
  
    # SPECIAL COMMANDS
    
    scmd_ping       => \&handle_ping,           # PING command
  
    # COMMANDS
    
    cmd_privmsg     => \&handle_privmsg,        # PRIVMSG command
    cmd_nick        => \&handle_nick,           # NICK command
    cmd_join        => \&handle_join,           # JOIN command
    cmd_part        => \&handle_part,           # PART command
    cmd_quit        => \&handle_quit,           # QUIT command
    cmd_cap         => \&handle_cap,            # CAP login command
    cmd_account     => \&handle_account,        # IRCv3 ACCOUNT command
    cmd_away        => \&handle_away,           # IRCv3 AWAY command
    
    
    # OTHER EVENTS
    
    isupport_prefix     => \&isupport_prefix,       # got PREFIX in RPL_ISUPPORT
    isupport_chanmodes  => \&isupport_chanmodes,    # got CHANMODES in RPL_ISUPPORT
    cap_ls              => \&cap_ls,                # server listed its capabilities
    cap_ack             => \&cap_ack,               # server acknowledged some capabilities
    cap_ack_sasl        => \&cap_ack_sasl           # server acknowledged SASL
    
);

# applies each handler to an IRC instance.
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

# PING from server.
sub handle_ping {
    my ($irc, $response) = IRC::args(@_, 'irc *response');
    $irc->send("PONG :$response");
}

# handle RPL_ISUPPORT (005)
sub handle_isupport {
    my ($irc, @stuff) = IRC::args(@_, 'irc @stuff');
    pop @stuff; # the last arg is :are supported by this server.
    foreach my $support (@stuff) { 
        my $val = 1;

        # get KEY=value types
        if ($support =~ m/(.+?)=(.+)/) {
            $support = $1;
            $val     = $2;
        }

        # set this support value.
        $irc->server->set_support($support, $val);
        
        # fire an event saying that we got this support value.
        $irc->fire_event('isupport_'.lc($support), $val);
        
    }

    return 1;
}

# End of MOTD or MOTD file not found
sub handle_endofmotd {
    my $irc = shift;
    if ($irc->{autojoin} && ref $irc->{autojoin} eq 'ARRAY' && !$irc->{_joined_auto}) {
        foreach my $chan_name (@{$irc->{autojoin}}) {
            $irc->send_join($chan_name);
        }
        $irc->{_joined_auto} = 1;
        return 1;
    }
    $irc->fire_event('end_of_motd');
    return;
}

# PRIVMSG command
sub handle_privmsg {
    my ($irc, $source, $target, $msg) = IRC::args(@_, 'irc +source +target *msg') or return;

    # fire events.
    EventedObject::fire_events_together(
        [ $irc,    privmsg     => $source, $target, $msg ], # generic privmsg for any source or target
        [ $target, got_privmsg => $source, $msg          ], # incoming from source
        [ $source, privmsg     => $target, $msg          ]  # outgoing from source
    );

}

# handle a nick change
# :user NICK new_nick
sub handle_nick {
    my ($user, $nick) = IRC::args(@_, '+source *nick') or return;
    return unless $user->isa('IRC::User');
    $user->set_nick($nick);
}

# user joins a channel
sub handle_join {
    my ($irc, $user, $channel, $account, $realname) =
    IRC::args(@_, 'irc +source +channel *acct *real') or return;
    return unless $user->isa('IRC::User');
    
    # add user to channel.
    $channel->add_user($user);
    
    # extended join.
    if ($irc->server->cap_enabled('extended-join')) {
        $user->set_account($account eq '*' ? undef : $account) if ($user->{account} || '*') ne $account;
        $user->set_real($realname);
    }
    
    # fire events.
    EventedObject::fire_events_together(
        [ $user,    joined_channel => $channel ],
        [ $channel, user_joined    => $user    ]
    );
    
    # if the user is me, send WHO.
    if ($user == $irc->{me}) {
    
        # send WHOX.
        if ($irc->server->support('whox')) {
            $irc->send_whox($channel->{name}, 'cdfhilnrstua');
        }
        
        # send WHO.
        else {
            $irc->send_who($channel->{name});
        }
        
    }
    
}

# user parts a channel
sub handle_part {
    my ($irc, $user, $channel, $reason) =
    IRC::args(@_, 'irc +source +channel *reason') or return;
    return unless $user->isa('IRC::User');

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
    my ($channel, $topic) = IRC::args(@_, 'channel *topic');
    
    # store the topic temporarily until we get RPL_TOPICWHOTIME.
    $channel->{temp_topic} = $topic;
}

# RPL_TOPICWHOTIME
sub handle_got_topic_time {
    my ($channel, $setter, $settime) = IRC::args(@_, 'channel *setter *settime');

    # set the topic.
    $channel->set_topic(delete $channel->{temp_topic}, $setter, $settime);

}

# RPL_NAMREPLY
sub handle_namesreply {
    my ($irc, $channel, @names) = IRC::args(@_, 'irc .type channel @names');

    NICK: foreach my $nick (@names) {

        # status levels to apply
        my @levels;

        LETTER: foreach my $letter (split //, $nick) {
            
            # is it a prefix?
            if (defined(my $level = $irc->server->prefix_to_level($letter))) {
                $nick =~ s/.{1}//;

                # add to the levels to apply.
                push @levels, $level;
                
            }

            # not a prefix.
            else {
                last LETTER;
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
    my ($irc, $nick) = IRC::args(@_, 'irc *nick');
    $irc->fire_event(nick_taken => $nick);
}

# handle QUIT.
sub handle_quit {
    my ($irc, $user, $reason) = IRC::args(@_, 'irc +source *reason') or return;
    return unless $user->isa('IRC::User');
    
    $user->fire_event(quit => $reason);
    $irc->pool->remove_user($user);
}

# Handle CAP
sub handle_cap {
    my ($irc, $subcommand, @params) = IRC::args(@_, 'irc .target *subcmd @caps');
    
    $subcommand = lc $subcommand;
    $irc->fire_event("cap_$subcommand" => @params);
}

# handle CAP LS.
sub cap_ls {
    my ($irc, @params) = @_;
    $irc->server->set_cap_available($_) foreach @params;
    $irc->_send_cap_requests;
}

# handle CAP ACK.
sub cap_ack {
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
        $irc->continue_login if $irc->{waiting_cap}{lc $cap};
        
        $irc->fire_event(cap_no_ack => $cap);
        $irc->fire_event("cap_no_ack_$cap");
    }

    # check if we're ready to send CAP END.
    $irc->_check_login;

}

# Handle ACCOUNT
sub handle_account {
    my ($user, $account) = IRC::args(@_, '+source *account') or return;
    return unless $user->isa('IRC::User');
    $user->set_account($account eq '*' ? undef : $account);
}

# handle AWAY
sub handle_away {
    my ($user, $reason) = IRC::args(@_, '+source *reason') or return;
    return unless $user->isa('IRC::User');
    $user->set_away($reason);
}

# handle SASL acknowledgement.
sub cap_ack_sasl {
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
    $irc->continue_login;
}

# handle WHO reply.
sub handle_whoreply {
    my ($irc, $channel, @params) = IRC::args(@_, 'irc channel rest');
    
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
    my ($irc, $id, $channel, @params) = IRC::args(@_, 'irc *id channel rest');
    _handle_who_long($irc, $id, @params);
}

# the real WHO and WHOX handler.
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
    $user->set_account($info{a}) if defined $info{a} && $info{a} ne '0';
    
    # server.
    if (defined $info{s} && !$user->server) {
        my $server = $irc->new_server_from_name($info{s});
        $server->add_user($user);
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

# the client logged in.
sub handle_loggedin {
    my ($irc, $account) = IRC::args(@_, 'irc *account');
    $irc->{me}->set_account($account);
}

# the client logged out.
sub handle_loggedout {
    my $irc = shift;
    $irc->{me}->set_account(undef);
}

# PREFIX in RPL_ISUPPORT
sub isupport_prefix {
    my ($irc, $val) = @_;
    
    # prefixes are stored in $irc->{ircd}{prefix}{<status level>}
    # and their value is an array reference of [symbol, mode letter]
    # update[6 June 2013]: IRC::Server is responsible for managing prefixes.
    #
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
    # the number of prefixes before @ is the top level.
    if ($prefixes =~ m/(.*)\@(.*)/) {
        my $current = length $1;
        my @before  = $1 ? split //, $1 : ();
        my @after   = $2 ? split //, $2 : ();

        # before the @
        foreach my $symbol (@before) {
            $final{$current} = $symbol;
            $current--;
        }

        $final{$current} = '@';
        $current--; # for the @

        # after the @
        foreach my $symbol (@after) {
            $final{$current} = $symbol;
            $current--;
        }
        
    }

    # no @, so just start from the top.
    else {
        my $current = length $prefixes;
        foreach my $symbol (split //, $prefixes) {
            $final{$current} = $symbol;
            $current--;
        }
    }

    # store.
    my ($i, @modes) = (0, split(//, $modes));
    foreach my $level (reverse sort { $a <=> $b } keys %final) {
        $irc->server->set_prefix($level, $final{$level}, $modes[$i]);
        $i++;
    }

}

# CHANMODES in RPL_ISUPPORT
sub isupport_chanmodes {
    my ($irc, $val) = @_;
    
    # CHANMODES tells us what modes are which.
    # we need this so we know which modes to expect to have parameters.
    # modes are stored in $irc->{chmode}{<letter>} = { type => <type> }

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
        $irc->{chmode}{$mode}{type} = $type; # TODO.
    }
}

1

