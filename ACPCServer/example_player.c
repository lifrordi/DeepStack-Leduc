/*
Copyright (C) 2011 by the Computer Poker Research Group, University of Alberta
*/

#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <getopt.h>
#include "game.h"
#include "rng.h"
#include "net.h"

int main( int argc, char **argv )
{
  int sock, len, r, a;
  int32_t min, max;
  uint16_t port;
  double p;
  Game *game;
  MatchState state;
  Action action;
  FILE *file, *toServer, *fromServer;
  struct timeval tv;
  double probs[ NUM_ACTION_TYPES ];
  double actionProbs[ NUM_ACTION_TYPES ];
  rng_state_t rng;
  char line[ MAX_LINE_LEN ];

  /* we make some assumptions about the actions - check them here */
  assert( NUM_ACTION_TYPES == 3 );

  if( argc < 4 ) {

    fprintf( stderr, "usage: player game server port\n" );
    exit( EXIT_FAILURE );
  }

  /* Define the probabilities of actions for the player */
  probs[ a_fold ] = 0.06;
  probs[ a_call ] = ( 1.0 - probs[ a_fold ] ) * 0.5;
  probs[ a_raise ] = ( 1.0 - probs[ a_fold ] ) * 0.5;

  /* Initialize the player's random number state using time */
  gettimeofday( &tv, NULL );
  init_genrand( &rng, tv.tv_usec );

  /* get the game */
  file = fopen( argv[ 1 ], "r" );
  if( file == NULL ) {

    fprintf( stderr, "ERROR: could not open game %s\n", argv[ 1 ] );
    exit( EXIT_FAILURE );
  }
  game = readGame( file );
  if( game == NULL ) {

    fprintf( stderr, "ERROR: could not read game %s\n", argv[ 1 ] );
    exit( EXIT_FAILURE );
  }
  fclose( file );

  /* connect to the dealer */
  if( sscanf( argv[ 3 ], "%"SCNu16, &port ) < 1 ) {

    fprintf( stderr, "ERROR: invalid port %s\n", argv[ 3 ] );
    exit( EXIT_FAILURE );
  }
  sock = connectTo( argv[ 2 ], port );
  if( sock < 0 ) {

    exit( EXIT_FAILURE );
  }
  toServer = fdopen( sock, "w" );
  fromServer = fdopen( sock, "r" );
  if( toServer == NULL || fromServer == NULL ) {

    fprintf( stderr, "ERROR: could not get socket streams\n" );
    exit( EXIT_FAILURE );
  }

  /* send version string to dealer */
  if( fprintf( toServer, "VERSION:%"PRIu32".%"PRIu32".%"PRIu32"\n",
	       VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION ) != 14 ) {

    fprintf( stderr, "ERROR: could not get send version to server\n" );
    exit( EXIT_FAILURE );
  }
  fflush( toServer );

  /* play the game! */
  while( fgets( line, MAX_LINE_LEN, fromServer ) ) {

    /* ignore comments */
    if( line[ 0 ] == '#' || line[ 0 ] == ';' ) {
      continue;
    }

    len = readMatchState( line, game, &state );
    if( len < 0 ) {

      fprintf( stderr, "ERROR: could not read state %s", line );
      exit( EXIT_FAILURE );
    }

    if( stateFinished( &state.state ) ) {
      /* ignore the game over message */

      continue;
    }

    if( currentPlayer( game, &state.state ) != state.viewingPlayer ) {
      /* we're not acting */

      continue;
    }

    /* add a colon (guaranteed to fit because we read a new-line in fgets) */
    line[ len ] = ':';
    ++len;

    /* build the set of valid actions */
    p = 0;
    for( a = 0; a < NUM_ACTION_TYPES; ++a ) {

      actionProbs[ a ] = 0.0;
    }

    /* consider fold */
    action.type = a_fold;
    action.size = 0;
    if( isValidAction( game, &state.state, 0, &action ) ) {

      actionProbs[ a_fold ] = probs[ a_fold ];
      p += probs[ a_fold ];
    }

    /* consider call */
    action.type = a_call;
    action.size = 0;
    actionProbs[ a_call ] = probs[ a_call ];
    p += probs[ a_call ];

    /* consider raise */
    if( raiseIsValid( game, &state.state, &min, &max ) ) {

      actionProbs[ a_raise ] = probs[ a_raise ];
      p += probs[ a_raise ];
    }

    /* normalise the probabilities  */
    assert( p > 0.0 );
    for( a = 0; a < NUM_ACTION_TYPES; ++a ) {

      actionProbs[ a ] /= p;
    }

    /* choose one of the valid actions at random */
    p = genrand_real2( &rng );
    for( a = 0; a < NUM_ACTION_TYPES - 1; ++a ) {

      if( p <= actionProbs[ a ] ) {

        break;
      }
      p -= actionProbs[ a ];
    }
    action.type = (enum ActionType)a;
    if( a == a_raise ) {

      action.size = min + genrand_int32( &rng ) % ( max - min + 1 );
    }

    /* do the action! */
    assert( isValidAction( game, &state.state, 0, &action ) );
    r = printAction( game, &action, MAX_LINE_LEN - len - 2,
		     &line[ len ] );
    if( r < 0 ) {

      fprintf( stderr, "ERROR: line too long after printing action\n" );
      exit( EXIT_FAILURE );
    }
    len += r;
    line[ len ] = '\r';
    ++len;
    line[ len ] = '\n';
    ++len;

    if( fwrite( line, 1, len, toServer ) != len ) {

      fprintf( stderr, "ERROR: could not get send response to server\n" );
      exit( EXIT_FAILURE );
    }
    fflush( toServer );
  }

  return EXIT_SUCCESS;
}
