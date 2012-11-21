#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# ntirc: an insanely flexible IRC client.          |
# foxy: an insanely flexible IRC bot.              |
# Copyright (c) 2012, the NoTrollPlzNet developers |
# Copyright (c) 2012, Mitchell Cooper              |
#---------------------------------------------------
package IRC;

use warnings;
use strict;
use base qw(EventedObject IRC::Functions::IRC);

use IRC::User;
use IRC::Channel;
use IRC::Handlers;
use IRC::Utils;
use IRC::Functions::IRC;
use IRC::Functions::User;
use IRC::Functions::Channel;

our $VERSION = '0.2';

# create a new IRC instance
sub new {
    my ($class, %opts) = @_;

    bless my $irc = {}, $class;
    $irc->configure($opts{nick});

    return $irc
}

sub configure {
    my ($self, $nick) = @_;

    # XXX users will probably make a reference chain
    # $irc->{users}->[0]->{irc}->{users} and so on
    $self->{me}       = IRC::User->new($self, $nick);
}

# parse a raw piece of IRC data
sub parse_data {
    my ($irc, $data) = @_;

    $data =~ s/(\0|\r)//g; # remove unwanted characters

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
    $irc->fire_event("raw_$command", $data, @args);
    $irc->fire_event('raw', $data, @args); # for anything

}

# shortcut to the 'send' event
sub send {
    shift->fire_event(send => @_);
}

# return a channel from its name
sub channel_from_name {
    my ($irc, $name) = @_;
    IRC::Channel::from_name($irc, $name);
}

# create a new channel by its name
# or return the channel if it exists
sub new_channel_from_name {
    my ($irc, $name) = @_;
    IRC::Channel->new_from_name($irc, $name);
}

# create a new user by his nick
# or return the user if it exists
sub new_user_from_nick {
    my ($irc, $nick) = @_;
    IRC::User->new_from_nick($irc, $nick);
}

# return a user by his nick
sub user_from_nick {
    my ($irc, $nick) = @_;
    IRC::User::from_nick($irc, $nick);
}

# create a new user by his :nick!ident@host string
# or return the user if it exists
sub new_user_from_string {
    my ($irc, $nick) = @_;
    IRC::User->new_from_string($irc, $nick);
}

# return a user by his :nick!ident@host string
sub user_from_string {
    my ($irc, $nick) = @_;
    IRC::User::from_string($irc, $nick);
}

1
