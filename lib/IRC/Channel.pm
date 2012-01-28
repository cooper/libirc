#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# Copyright (c) 2011, the NoTrollPlzNet developers |
# Channel.pm: the channel object class.            |
#---------------------------------------------------
package IRC::Channel;

use warnings;
use strict;
use base qw(IRC::EventedObject IRC::Functions::Channel);

# CLASS METHODS

sub new {
    my ($class, $irc, $name) = @_;

    # create a channel object
    bless my $channel = {
        name   => $name,
        users  => [],
        modes  => {},
        events => {},
        status => {}
    };

    $channel->{irc} = $irc; # creates a looping reference XXX
    $irc->{channels}->{lc $name} = $channel;

    # fire new channel event
    $irc->fire_event(new_channel => $channel);

    return $channel
}

# lookup by channel name
sub from_name {
    my ($irc, $name) = (shift, lc shift);
    $name =~ s/^://;
    return $irc->{channels}->{$name}
}

# lookup by channel name
# or create a new channel if it doesn't exist
sub new_from_name {
    my ($package, $irc, $name) = (shift, shift, lc shift);
    $name =~ s/^://;
    exists $irc->{channels}->{$name} ? $irc->{channels}->{$name} : $package->new($irc, $name)
}

# INSTANCE METHODS

# user is in channel?
sub has_user {
    my ($channel, $user) = @_;
    return 1 if grep { $_ == $user } @{$channel->{users}};
    return
}

# add a user to a channel
sub add_user {
    my ($channel, $user) = @_;
    return if $channel->has_user($user);
    push @{$channel->{users}}, $user;
    $channel->fire_event(user_joined => $user);
}

# remove user from channel
sub remove_user {
    my ($channel, $user) = @_;
    return unless $channel->has_user($user);
    $channel->fire_event(user_remove => $user); # remove, not part, because it might be a quit or something
    @{$channel->{users}} = grep { $_ != $user } @{$channel->{users}}
}

# change the channel topic
sub set_topic {
    my ($channel, $topic, $setter, $time) = @_;

    # fire a "changed" event
    # but not if this is the first time the topic has been set
    $channel->fire_event(topic_changed => $topic, $setter, $time) if exists $channel->{topic};

    $channel->{topic} = {
        topic  => $topic,
        setter => $setter,
        time   => $time
    }
}

# set a user's channel status
sub set_status {
    my ($channel, $user, $level) = @_;

    # add the user to the status array
    push @{$channel->{status}->{$level}}, $user;

    # fire event
    $channel->fire_event(set_user_status => $user, $level);
}

# get status(es) of a user
sub user_status {
    my ($channel, $user) = @_;
    my @status;
    foreach my $level (keys %{$channel->{status}}) {
        foreach my $this_user (@{$channel->{status}->{$level}}) {
            push @status, $level if $user == $this_user
        }
    }
    return @status
}

# user is status or higher?
sub user_is_status {
    my ($channel, $user, $need) = @_;
    foreach my $level (keys %{$channel->{status}}) {
        foreach my $this_user (@{$channel->{status}->{$level}}) {
            next unless $level >= $need;
            return 1 if $user == $this_user;
        }
    }
    return
}

1
