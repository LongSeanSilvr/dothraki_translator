#!/usr/bin/perl

BEGIN {
use File::Basename;
my $dirname = dirname(__FILE__);
chdir $dirname;
}
use warnings;
use SynTransfer;
use Getopt::Std;
use strict;
use IO::Socket;
use threads;
$|++;

#=======================
# SynTransfer Initiation
#=======================
our(%Opt);
getopts('c:kdqKDQ', \%Opt);

unless($Opt{'c'}) { $Opt{'c'} = "ST_Config.txt"; }
if(-e $Opt{'c'}) { require($Opt{'c'}); }
else { print STDERR "Cannot find configuration file: $Opt{'c'}\n"; exit; }
unless($Opt{'k'} || $Opt{'K'}) { $Opt{'k'} = 0; }
if($Opt{'d'} || $Opt{'D'}) { $SynTransfer::ST_DEBUG = 1; }
if($Opt{'q'} || $Opt{'Q'}) { $SynTransfer::ST_QUIET = 1; }

if(($^O =~ /WIN/i) && ($^O !~ /DARWIN/i)) {
    require Win32::Console;
    Win32::Console::OutputCP($ST_CodePage);
    system("TITLE Syntactic Transfer"); }

unless($PCPATR_EXE && (-e $PCPATR_EXE)) {
    print STDERR "Cannot find PC-PATR.\n";
    sleep(4);
    exit; }

&InitializeAll;
my($LeftOver);


#=======================
# Start Server
#=======================
print $$;

my $server = new IO::Socket::INET(
    Timeout   => 7200,
    Proto     => "tcp",
    LocalHost => "localhost",
    LocalPort => "7000",
    Reuse     => 1,
    Listen    => 2
);
my $num_of_client = -1;

while (1) {
    my $client;

    do {
        $client = $server->accept;
    } until ( defined($client) );

    my $peerhost = $client->peerhost();
    print "accepted a client $client, $peerhost, id = ", ++$num_of_client, "\n";

     #spawn  a thread here for each client
   my $thr = threads->new( \&processit,$client,$peerhost )->detach(); 

}

sub processit {
     my ($lclient,$lpeer) = @_; #local client
   
     if($lclient->connected){
          while(<$lclient>){
            my $Xlated = ST_Translate($_);
            print $lclient "$Xlated"}
        
    }
  
  #close filehandle before detached thread dies out
  close( $lclient);
}
__END__