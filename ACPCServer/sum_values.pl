#!/usr/bin/perl

#Copyright (C) 2014 by the Computer Poker Research Group, University of Alberta

while( $_ = <> ) {

    chomp $_;
    @_ = split /:/, $_;
    if( $_[ 0 ] ne "STATE" || @_ != 6 ) {

	next;
    }

    @values = split /\|/, $_[ 4 ];
    @players = split /\|/, $_[ 5 ];
    $#values == $#players or die "badly formed line: $_";

    for( $i = 0; $i < @players; ++$i ) {

	$totals{ $players[ $i ] } += $values[ $i ];
    }
}

print "SCORE:";
@players = keys( %totals );
for( $i = 0; $i < @players; ++$i ) {

    if( $i ) {

	print "|";
    }
    print $totals{ $players[ $i ] };
}
for( $i = 0; $i < @players; ++$i ) {

    if( $i ) {

	print "|";
    }
    print $players[ $i ];
}
print "\n";
