#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# ntirc: an insanely flexible IRC client.          |
# foxy: an insanely flexible IRC bot.              |
# Copyright (c) 2011, the NoTrollPlzNet developers |
# Copyright (c) 2012-13, Mitchell Cooper           |
#---------------------------------------------------
package IRC::Parser;

use warnings;
use strict;
use utf8;
use 5.010;

use Scalar::Util qw(blessed looks_like_number);

##################
### OLD PARSER ###
##################

# DEPRECATED: parse a raw piece of IRC data.
# this has been replaced by handle_data() and parse_data_new()
# and remains here temporarily for compatibility only.
sub parse_data {
    my ($irc, $data) = @_;
    
    $data =~ s/\0|\r//g; # remove unwanted characters

    # parse one line at a time
    if ($data =~ m/\n/) {
        $irc->parse_data($_) foreach split "\n", $data;
        return
    }

    my @args = split /\s/, $data;
    return unless defined $args[0];

    if ($args[0] eq 'PING') {
        $irc->send("PONG $args[1]");
    }

    # if there is no parameter, there's nothing to parse.
    return unless defined $args[1];

    my $command = lc $args[1];

    # fire the raw_* event (several of which fire more events from there on)
    #$irc->fire_event(raw => $data, @args); # for anything
    $irc->fire_event("raw_$command", $data, @args);

}

##################
### NEW PARSER ###
##################

# handle a piece of incoming data.
sub handle_data {
    my ($irc, $data) = @_;
    
    # fire old parser if requested.
    $irc->parse_data($data) if $irc->{enable_raw_events};
    
    # strip unwanted characters
    $data =~ s/\0|\r//g;
    
    # parse each line, one at a time.
    if ($data =~ m/\n/) {
        $irc->handle_data($_) foreach split "\n", $data;
        return;
    }
    
    # parse the data.
    my ($tags, $source, $command, @args) = $irc->parse_data_new($data);
    $command = lc $command;
    
    # raw data.    
    $irc->fire_event(raw => $data, split(/\s/, $data));
    
    # it's a numeric.
    if (looks_like_number($command)) {
        shift @args; # remove the target, because it will always be the client.
        $irc->fire_event("num_$command" => $tags, $source, @args);
    }
    
    # it's a command.
    else {
        $irc->fire_event("scmd_$command" => $tags,          @args) if $source->{type} eq 'none';
        $irc->fire_event("cmd_$command"  => $tags, $source, @args) if $source->{type} ne 'none';
    }
}

# parse a piece of incoming data.
sub parse_data_new {
    my ($irc, $data) = @_;    
    my ($arg_i, $char_i, $got_colon, $last_char, $has_tags, $args) = (0, -1);
    
    # separate the arguments.
    
    foreach my $char (split //, $data) {
        $char_i++;
        
        # at sign:
        #
        # this is the start of message tags.
        # this is used to determine where the source is.
        # we need to know that so we know if the colon belongs to the source
        # or if it marks the start of a trailing parameter.
        if ($char eq '@' && !$char_i) {
            $has_tags = 1;
        }
        
        # whitespace:
        #
        # if the last character is not whitespace
        # and we have not received the colon.
        if ($char =~ m/\s/ && !$got_colon) { 
            next if defined $last_char && $last_char =~ m/\s/;
            $arg_i++;
            $last_char = $char;
            next;
        }
        
        # colon:
        #
        # if we haven't already received a colon
        # and this isn't the first arg (that would be a source)
        # and we're not in the middle of an argument.
        #
        # true if this is the first real argument (ignoring message tags)
        my $first = $has_tags ? $arg_i == 1 : $arg_i == 0;    
        if ($char eq ':' && !$got_colon && !$first and !defined $args->[$arg_i] || !length $args->[$arg_i]) {
            $got_colon = 1;
            $last_char = $char;
            next;
        }
        
        # any other character:
        
        defined $args->[$arg_i] or $args->[$arg_i] = '';
        $args->[$arg_i] .= $char;
        
        $last_char = $char;
    }
        
    # parse IRCv3.2 message tags.
    my $tags = _parse_tags($args);    

    # parse source.
    my $source = _parse_source($args);
    
    return ($tags, $source, @$args);
}

# create a tagref.
sub _parse_tags {
    my ($args, %tags) = shift;
    
    # no tags.
    return { IS_TAGS => 1 } unless $args->[0] =~ m/^@(.+)$/;
    
    # there are tags, so remove them from @args.
    my $tag_string = $1;
    shift @$args;
    
    # separate each tag and value.
    #
    # <key>   ::= [ <vendor> '/' ] <sequence of letters, digits, hyphens (`-`)>
    # <value> ::= <sequence of any characters except NUL, BELL, CR, LF, semicolon (`;`) and SPACE>
    # the specification does not mention the equal sign, so we will assume that the first
    #
    # equal sign indicates the start of the value, and all following are part of the value.
    #
    foreach my $tag_and_value (split /;/, $tag_string) {
        my ($tag, $value) = split /=/, $tag_and_value, 2;
        $tags{$tag} = defined $value ? $value : 1;
    }
    
    $tags{IS_TAGS} = 1;
    return \%tags;
}

# create a sourceref.
sub _parse_source {
    my ($args, $source) = shift;
    
    # if it doesn't start with a colon, no source.
    if ($args->[0] !~ m/^:/) {
        $source = { type => 'none' };
    }
    
    # it's a user.
    elsif ($args->[0] =~ m/^:(.+)!(.+)@(.+)/) {
        shift @$args;
        $source = {
            type => 'user',
            nick => $1,
            user => $2,
            host => $3
        };
    }
    
    # it must be a server.
    elsif ($args->[0] =~ m/^:(.+)/) {
        shift @$args;
        $source = {
            type => 'server',
            name => $1
        };
    }
    
    $source->{IS_SOURCE} = 1;
    return $source;
}

###########################
### NEW ARGUMENT PARSER ###
###########################

# handling arguments.
sub args {
    my @types = split /\s/, pop;
    my ($irc, $event, $tags, $source, $i, $u, @args, @return, @modifiers) = __PACKAGE__;
    
    # filter out IRC objects and event fire objects.
    ARG: foreach my $arg (@_) {
        if (blessed $arg) {
        
            # IRC object.
            $irc = $arg if $arg->isa('IRC');
            
            # event object.
            if ($arg->isa('EventedObject::EventFire')) {
                $irc   = $arg->object if !$irc;
                $event = $arg;
            }

            next ARG;
            
        } # hashref.
        elsif (ref $arg && ref $arg eq 'HASH') {
            $source = $arg if $arg->{IS_SOURCE};
            $tags   = $arg if $arg->{IS_TAGS};
            next ARG;
        }
        
        # any other argument.
        push @args, $arg;
        
    }
    
    # type aliases.
    state $aliases = {
        target => 'channel|user',
        event  => 'fire'
    };
    
    # filter modifiers.
    $u = 0;
    foreach my $ustr (@types) {
        $ustr =~ m/^([\.\+@\*]*)(.*)$/;
        $modifiers[$u] = $1 ? [split //, $1] : [];
        $types[$u]     = exists $aliases->{$2} ? $aliases->{$2} : $2;
        $types[$u]     = defined $types[$u] ? $types[$u] : 'none';
        $u++;
    }
    
    ($i, $u) = (-1, -1);
    
    my $return;                # irc   ustr
    USTR: foreach (@types)     { $i++; $u++;    # type string w/o modifiers (i.e. 'user,channel')
    
        my $arg  = $args[$i];
        my @mods = @{$modifiers[$u]};
        
    TYPE: foreach (split /\|/) {                # individual type string (i.e. 'user')
        my $type = $_;
        
        # we already found a return value for this ustr.
        last TYPE if defined $return;
        
        # dummy modifier; skip.
        when ($_ eq 'dummy' || '.' ~~ @mods) {
            # do nothing.
            next USTR;
        }
        
        # IRC object.
        when ('irc') {
            $return = $irc;
            $i--; # these are not actually IRC arguments.
        }
        
        # event fire object.
        when ('fire') {
            $return = $event;
            $i--; # these are not actually IRC arguments.
        }
        
        # message tags.
        when ('tags') {
            $return = $tags;
            $i--; # these are not actually IRC arguments.
        }
        
        # server or user.
        when ('source') {
        
            # if we have a source object, this is incredibly easy.
            if ($source) {
                $return = $irc->_get_source($source);
                $i--; # not a real IRC argument.
            }
        
            # source hash passed.
            elsif (ref $arg && ref $arg eq 'HASH') {
                $return = $irc->_get_source($arg) if $arg->{IS_SOURCE};
            }
        
            # check for a user string.
            elsif ($arg =~ m/^:*(.+)!(.+)\@(.+)/) {
                my ($nick, $ident, $host) = ($1, $2, $3);
                $return = $irc->_get_source({
                    type => 'user',
                    nick => $nick,
                    user => $ident,
                    host => $host
                });
            }
            
            # check for a server string.
            elsif ($arg =~ m/^:(.+)$/) {
                $return = $irc->_get_source({
                    type => 'server',
                    name => $1
                });
            }
            
        }
        
        # user source, id, or nickname.
        when ('user') {
        
            # is it a source object?
            if (ref $arg && ref $arg eq 'HASH') {
                my $source = $irc->_get_source($arg);
                $return = $source, next TYPE if $source;
            }
            
            # nickname or ID.
            $return = $irc->pool->get_user($arg);
            
        }
        
        # channel id or name.
        when ('channel') {
            $return = $irc->new_channel_from_name($arg);
        }
        
        # any string.
        when ($_ eq 'any' || '*' ~~ @mods) {
            $return = $arg;
        }
        
        # space-separated list.
        # this assumes all remaining arguments are part of the list.
        when ($_ eq 'list' || '@' ~~ @mods) {
            push @return, map { split /\s/ } @args[$i..$#args];
            next USTR;
        }
        
        # the rest of the arguments.
        # this is similar to list, but it does not split the arguments by space.
        when ('rest') {
            push @return, @args[$i..$#args];
            next USTR;
        }
        
    }
    
        # if the + modifier is present, this value MUST be defined.
        if ('+' ~~ @mods && !defined $return) {
            return;
        }
        
        push @return, $return; $return = undef
    
    }
    
    return @return;
}

# fetch a source from a source ref.
sub _get_source {
    my ($irc, $source) = @_;
    return if not $source && ref $source eq 'HASH';
    if ($source->{type} eq 'user') {
        my $user = $irc->new_user_from_nick($source->{nick});
        return unless $user;
        
        # update host.
        $user->set_host($source->{host})
            if !defined $user->{host} || $source->{host} ne $user->{host};
            
        # update user.
        $user->set_user($source->{user})
            if !defined $user->{user} || $source->{user} ne $user->{user};    
            
        return $user;    
    }
    return 'fakeserver'; # TODO: servers.
    return;
}

1
