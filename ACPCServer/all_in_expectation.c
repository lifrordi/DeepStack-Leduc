/*
Copyright (C) 2014 by the Computer Poker Research Group, University of Alberta
*/

#include <stdlib.h>
#include <stdio.h>
#define __STDC_LIMIT_MACROS
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <getopt.h>
#include "game.h"
#include "net.h"


void getUsedCards( const Game *game,
		   const State *state,
		   const int lastRound,
		   uint8_t *used )
{
  int i, p;

  /* start with no cards used */
  memset( used, 0, sizeof( used[ 0 ] ) * game->numSuits * game->numRanks );

  /* collect the player cards */
  for( p = 0; p < game->numPlayers; ++p ) {

    for( i = 0; i < game->numHoleCards; ++i ) {

      used[ state->holeCards[ p ][ i ] ] = 1;
    }
  }

  /* collect the board cards up to lastRound */
  p = sumBoardCards( game, lastRound );
  for( i = 0; i < p; ++i ) {

    used[ state->boardCards[ i ] ] = 1;
  }
}

int main( int argc, char **argv )
{
  int stateEnd, r, i, p, deckSize, numBoards;
  FILE *file;
  Game *game;
  State state;
  uint8_t deck[ MAX_SUITS * MAX_RANKS ];
  uint8_t used[ MAX_SUITS * MAX_RANKS ];
  double value[ MAX_PLAYERS ];
  char line[ 4096 ];

  if( argc < 3 ) {

    fprintf( stderr, "USAGE: %s game_def log_file\n", argv[ 0 ] );
    exit( EXIT_FAILURE );
  }

  /* get the game definition */
  file = fopen( argv[ 1 ], "r" );
  if( file == NULL ) {

    fprintf( stderr, "ERROR: could not open game definition %s\n", argv[ 1 ] );
    exit( EXIT_FAILURE );
  }
  game = readGame( file );
  if( game == NULL ) {

    fprintf( stderr, "ERROR: could not read game %s\n", argv[ 1 ] );
    exit( EXIT_FAILURE );
  }
  fclose( file );

  /* get the log file */
  file = fopen( argv[ 2 ], "r" );
  if( file == NULL ) {

    fprintf( stderr, "ERROR: could not open log file %s\n", argv[ 2 ] );
    exit( EXIT_FAILURE );
  }

  /* read every line and process all hands */
  while( fgets( line, 4096, file ) ) {

    stateEnd = readState( line, game, &state );
    if( stateEnd < 0 ) {
      /* couldn't read a state from the line */

      continue;
    }

    if( numAllIn( game, &state ) == 0
	|| numFolded( game, &state ) + 1 >= game->numPlayers ) {
      /* no one all in, or game didn't end in a showdown */

      printf( "%s", line );
      continue;
    }

    /* find last round where someone made an action */
    for( r = state.round; r > 0; --r ) {

      if( state.numActions[ r ] ) {

	break;
      }
    }

    if( r + 1 == game->numRounds ) {
      /* there are no board cards left to roll out on the final round */

      printf( "%s", line );
      continue;
    }

    /* initialise values to 0 */
    memset( value, 0, sizeof( value ) );

    /* set up a deck containing all cards up to round r */
    getUsedCards( game, &state, r, used );
    deckSize = 0;
    for( i = 0; i < game->numSuits * game->numRanks; ++i ) {

      if( !used[ i ] ) {

	deck[ deckSize ] = i;
	++deckSize;
      }
    }

    /* switch to using used[] as the index into deck[]
       for the remaining cards used on the board
       sort hands in ascending order, start with highest indexed hand */
    const int bcStart = sumBoardCards( game, r );
    const int numCards = sumBoardCards( game, game->numRounds - 1 ) - bcStart;
    for( i = 0; i < numCards; ++i ) {

      used[ i ] = deckSize - numCards + i;
      state.boardCards[ bcStart + i ] = deck[ used[ i ] ];
    }

    /* try every possible board */
    numBoards = 0;
    while( 1 ) {

      /* get the values */
      for( p = 0; p < game->numPlayers; ++p ) {

	value[ p ] += valueOfState( game, &state, p );
      }

      /* move on to the next board */
      ++numBoards;

      /* find position of first card we can decrement */
      i = 0;
      while( used[ i ] == i && i < numCards ) {

	++ i;
      }
      if( i == numCards ) {
	/* can't decrement any cards, so we're done */

	break;
      }

      /* decrement the card */
      --used[ i ];
      state.boardCards[ bcStart + i ] = deck[ used[ i ] ];

      /* fill in all earlier cards with highest possible index */
      while( i > 0 ) {

	/* move to previous card, set index to one lower then current card */
	--i;
	used[ i ] = used[ i + 1 ] - 1;
	state.boardCards[ bcStart + i ] = deck[ used[ i ] ];
      }
    }

    /* do the printout - start with the state */
    if( line[ stateEnd ] != 0 ) {

      if( line[ stateEnd ] != ':' && line[ stateEnd ] != '\n' ) {

	fprintf( stderr, "ERROR: expected input of STATE:VALUES:PLAYERS\n" );
	exit( EXIT_FAILURE );
      }
      line[ stateEnd ] = 0;
      ++stateEnd;
    }
    printf( "%s:", line );

    /* print out the averaged values */
    for( p = 0; p < game->numPlayers; ++p ) {

      printf( p ? "|%lf" : "%lf", value[ p ] / (double)numBoards );
    }

    /* find the player names in the state line */
    for( i = stateEnd; line[ i ] && line[ i ] != ':'; ++i );
    if( line[ i ] == ':' ) {

      printf( "%s", &line[ i ] );
    } else {

      printf( "\n" );
    }
  }

  fclose( file );
  exit( EXIT_SUCCESS );
}
