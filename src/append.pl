#!/usr/bin/perl -w

use strict;

use CGI qw(:cgi);
use Crypt::CBC;
use Fatal qw(chdir open);
use File::Basename qw(dirname);
use File::Slurp;
use File::Temp qw(tempfile);
use JSON;

chdir dirname $0;

use exec_timer;
use tracker;
use lockfile;

my $q = CGI->new;

my $id = $q->param('game');
$id =~ s{.*/}{};
$id =~ s{[^A-Za-z0-9_]}{}g;

my $faction_name = $q->param('preview-faction');
my $faction_key = $q->param('faction-key');
my $new_content = "";

my $preview = $q->param('preview');
my $append = join "\n", (map { "$faction_name: $_" } grep { /\S/ } split /\n/, $preview);

my $dir = "../../data/write/";
my $lockfile = lockfile::get "$dir/lock";
chdir $dir;

sub save {
    my ($fh, $filename) = tempfile("tmpfileXXXXXXX",
                                   DIR=>".");
    print $fh $new_content;
    close $fh;
    chmod 0444, $filename;
    rename $filename, "$id";

    system "git commit -m 'change $id' $id > /dev/null";
}

sub verify_key {
    my $secret = read_file("../secret");
    my $iv = read_file("../iv");

    my $cipher = Crypt::CBC->new(-key => $secret,
                                 -blocksize => 8,
                                 -iv => $iv,
                                 -add_header => 0,
                                 -cipher => 'Blowfish');
    my $data = $cipher->decrypt(pack "h*", $faction_key);
    my $game_secret = unpack("h*", $data ^ $faction_name);
    $id .= "_$game_secret";
    die "Invalid faction key\n" if $id =~ /[^a-zA-z0-9_]/ or !(-f $id);

    $new_content = read_file("$id");
    chomp $new_content;
    $new_content .= "\n";

    chomp $append;
    $append .= "\n";

    $new_content .= $append;
}

print "Content-type: text/json\r\n";
print "Cache-Control: no-cache\r\n";
print "\r\n";

lockfile::lock $lockfile;

eval {
    verify_key;
}; if ($@) {
    print encode_json {
        error => [ $@ ],
    };
    exit;
};

my $res = terra_mystica::evaluate_game { rows => [ split /\n/, $new_content ] };

if (!@{$res->{error}}) {
    eval {
        save;
    }; if ($@) {
        print STDERR "error: $@\n";
        $res->{error} = [ $@ ]
    }
};

lockfile::unlock $lockfile;

my @email = ();

if ($terra_mystica::email) {
    push @email, $terra_mystica::email;
}

for my $faction (values %terra_mystica::factions) {
    if ($faction->{name} ne $faction_name and $faction->{email}) {
        push @email, $faction->{email}
    }
}

my $out = encode_json {
    error => $res->{error},
    email => (join ",", @email),
    action_required => $res->{action_required},
    round => $terra_mystica::round,
    turn => $terra_mystica::turn,
};
print $out;
