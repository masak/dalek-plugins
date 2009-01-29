package modules::local::rakudolog;
use strict;
use warnings;
use LWP::UserAgent;
use XML::Atom::Client;
use HTML::Entities;
use WWW::Shorten::Metamark;
use WWW::Shorten 'Metamark';

# Parse ATOM generated by github.com.

my $url  = 'http://github.com/feeds/rakudo/commits/rakudo/master';
my $lastrev;
my $copy_of_self;

sub init {
    my $self = shift;
    $copy_of_self = $self;
    my $rev = main::get_item($self, "rakudo_lastrev");
    undef $rev unless length $rev;
    $lastrev = $rev if defined $rev;
    main::lprint("rakudolog: init: initialized lastrev to $lastrev") if defined $lastrev;
    main::create_timer("rakudolog_fetch_feed_timer", $self, "fetch_feed", 30);
}

sub implements {
    return qw();
}

sub shutdown {
    my $self = shift;
    main::delete_timer("rakudolog_fetch_feed_timer");
    main::store_item($self, "rakudo_lastrev", $lastrev) if defined $lastrev;
}

my $lwp = LWP::UserAgent->new();
$lwp->timeout(10);
$lwp->env_proxy();

sub fetch_feed {
    my $atom = XML::Atom::Client->new();
    my $feed = $atom->getFeed($url);
    process_feed($feed);
}

sub process_feed {
    my $feed = shift;
    my @items = $feed->entries;
    @items = sort { $a->updated cmp $b->updated } @items; # ascending order
    my $newest = $items[-1];
    my $latest = $items[0]->updated;

    # skip the first run, to prevent new installs from flooding the channel
    if(defined($lastrev)) {
        # output new entries to channel
        foreach my $item (@items) {
            my $updated = $item->updated;
            output_item($item) if $updated gt $lastrev;
        }
    }
    $lastrev = $latest;
    main::store_item($copy_of_self, "rakudo_lastrev", $lastrev);
}

sub longest_common_prefix {
    my $prefix = shift;
    for (@_) {
        chop $prefix while (! /^\Q$prefix\E/);
    }
    return $prefix;
}


sub output_item {
    my $item = shift;
    my $prefix  = 'unknown';
    my $creator = $item->author;
    if(defined($creator)) {
        $creator = $creator->name;
    } else {
        $creator = 'unknown';
    }
    my $link    = $item->link->href;
    my $desc    = $item->content;
    if(defined($desc)) {
        $desc = $desc->body;
    } else {
        $desc = '(no commit message)';
    }

    $creator = "($creator)" if($creator =~ /\s/);

    my ($rev)   = $link =~ m|/commit/([a-z0-9]{40})|;
    my ($log, $files);
    $desc =~ s/^.*<pre>//;
    $desc =~ s/<\/pre>.*$//;
    my @lines = split("\n", $desc);
    my @files;
    while($lines[0] =~ /^m (.+)/) {
        push(@files, $1);
        shift(@lines);
    }
    return main::lprint("rakudolog: error parsing filenames from description")
        unless $lines[0] eq '';
    shift(@lines);
    pop(@lines) if $lines[-1] =~ /^git-svn-id: http:/;
    pop(@lines) while scalar(@lines) && $lines[-1] eq '';
    $log = join("\n", @lines);

    $prefix =  longest_common_prefix(@files);
    $prefix =~ s|^/||;      # cut off the leading slash
    if(scalar @files > 1) {
        $prefix .= " (" . scalar(@files) . " files)";
    }

    $log =~ s|<br */>||g;
    decode_entities($log);
    my @log_lines = split(/[\r\n]+/, $log);

    $rev = substr($rev, 0, 7);
    put("rakudo: $rev | $creator++ | $prefix:");
    foreach my $line (@log_lines) {
	put("rakudo: $line");
    }
    put("rakudo: review: $link");
    main::lprint("rakudolog: output_item: output rev $rev");
}

sub put {
    my $line = shift;
    main::send_privmsg("magnet", "#parrot", $line);
}

1;
