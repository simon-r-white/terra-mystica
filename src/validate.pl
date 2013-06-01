#!/usr/bin/perl -w

use CGI qw(:cgi);
use Crypt::CBC;
use Crypt::Eksblowfish::Bcrypt qw(de_base64);
use DBI;

use secret;

print "Content-type: text/html\r\n";
print "Cache-Control: no-cache\r\n";
print "\r\n";

my @error = ();

my $q = CGI->new;
my $token = $q->param('token');

sub add_user {
    my ($user, $email, $hashed_password) = @_;

    my $dbh = DBI->connect("dbi:Pg:dbname=terra-mystica", '', '',
                           { AutoCommit => 1, RaiseError => 1});

    $dbh->do('begin');
    $dbh->do('insert into player (username, password) values (?, ?)', {},
             $user, $hashed_password);
    $dbh->do('insert into email (address, player, validated) values (lower(?), ?, ?)',
             {}, $email, $user, 1);
    $dbh->do('commit');

    $dbh->disconnect();
}

sub check_token {
    my ($secret, $iv) = get_secret;

    my $cipher = Crypt::CBC->new(-key => $secret,
                                 -blocksize => 8,
                                 -header => 'randomiv',
                                 -cipher => 'Blowfish');
    my $data = $cipher->decrypt(de_base64 $token);
    add_user split /\t/, $data;
}

eval {
    check_token;
    print "<h3>Account created</h3>";
}; if ($@) {
    print STDERR "token: $token\n";
    print STDERR $@;
    print "<h3>Validation failed</h3>";
}
