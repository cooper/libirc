#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# ntirc: an insanely flexible IRC client.          |
# foxy: an insanely flexible IRC bot.              |
# Copyright (c) 2011, the NoTrollPlzNet developers |
# Copyright (c) 2012-13, Mitchell Cooper           |
# Channel.pm: the channel object class.            |
#---------------------------------------------------
package IRC::Channel;

use warnings;
use strict;
use parent qw(EventedObject IRC::Functions::Channel);
use utf8;
use 5.010;
use overload
    '""'     => sub { shift->{id} },                    # string context  = ID
    '0+'     => sub { shift },                          # numeric context = memory address 
    'bool'   => sub { 1 },                              # boolean context = true
    '${}'    => sub { \shift->{name} },                 # scalar deref    = name
    '@{}'    => sub { [ values %{shift->{users}} ] },   # array deref     = users
    '~~'     => \&_match,                               # smart match
    fallback => 1;

use Scalar::Util 'weaken';

# CLASS METHODS

sub new {
    my ($class, %opts) = @_;
    
    # create a channel object
    bless my $channel = {
        users => {},
        %opts
    };

    # assign a temporary identifier.
    $channel->{id} = '[Channel '.($channel + 0).q(]);

    return $channel;
}

# INSTANCE METHODS

# user is in channel?
sub has_user {
    my ($channel, $user) = @_;
    return exists $channel->{users}{$user};
}

# add a user to a channel
sub add_user {
    my ($channel, $user) = @_;
    return if $channel->has_user($user);
    
    # add user to channel.
    weaken($channel->{users}{$user}    = $user);
    weaken($user->{channels}{$channel} = $channel);
   
    # hold on to the user.
    $channel->pool->retain($user, "channel:$channel");
    
    # if the user is me, hold on to the channel.
    if ($user == $channel->irc->{me}) {
        $channel->pool->retain($channel, 'me:in_channel');
    }
    
    $channel->fire_event(user_add => $user);
    
}

# remove user from channel
sub remove_user {
    my ($channel, $user) = @_;
    return unless $channel->has_user($user);
    
    EventedObject::fire_events_together(
        [ $channel, user_remove     =>  $user    ],
        [ $user,    remove_channel  =>  $channel ]
    );
    
    delete $channel->{users}{$user};
    delete $user->{channels}{$channel};
    
    # let go of the user.
    $channel->pool->release($user, "channel:$channel"); 
    
    # if the user is me, let go of the channel.
    if ($user == $channel->irc->{me}) {
        $channel->pool->release($channel, 'me:in_channel');
    }
    
    return 1;
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
    };
}

# set a user's channel status
sub add_status {
    my ($channel, $user, $level) = @_;
    return if $channel->user_is_status($user, $level);

    # weakly add the user to the status array.
    my $level_users = $channel->{status}{$level};
    push @$level_users, $user;
    weaken($level_users->[$#$level_users]);

    # add the level to the user's status array.
    my $levels = ($user->{channel_status}{$channel} ||= []);
    push @$levels, $level;
    
    $channel->fire_event(set_user_status => $user, $level);
}

# get status(es) of a user
sub user_status {
    my ($channel, $user) = @_;
    my @a = @{ $user->{channel_status}{$channel} || [] };
    return wantarray ? @a : $a[0];
}

# user is status or higher?
sub user_is_status {
    my ($channel, $user, $check) = @_;
    foreach my $level ($channel->user_status($user)) {
        return 1 if $level >= $check;
    }
    return;
}

# returns an array of users in the channel.
sub users {
    return values %{ shift->{users} };
}

sub id   { shift->{id}      }
sub pool { shift->{pool}    }
sub irc  { shift->pool->irc }

# smart matching
sub _match {
    my ($channel, $other) = @_;
    
    # anything that is not blessed is a no no.
    return unless blessed $other;
    
    # for channels, I'm not sure what to do yet.
    if ($other->isa('IRC::Channel')) {
        return $channel->irc == $other->irc;
    }
    
    # if it's a user, check if the user is in the channel.
    if ($other->isa('IRC::User')) {
        return $channel->has_user($other);
    }
    
    # for IRC objects, check if the channel belongs to that server.
    if ($other->isa('IRC')) {
        return $other == $channel->irc;
    }
    
    return;
}

sub DESTROY {
    my $channel = shift;

    # remove each user.
    $channel->remove_user($_) foreach $channel->users;

    # if the channel belongs to a pool, remove it.
    $channel->pool->remove_channel($channel) if $channel->pool;
    
}


1
