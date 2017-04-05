/*
Copyright (C) 2011 by the Computer Poker Research Group, University of Alberta
*/

#include <stdlib.h>
#include <stdio.h>
#define __STDC_LIMIT_MACROS
#include <stdint.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <getopt.h>
#include "game.h"
#include "net.h"


/* the ports for players to connect to will be printed on standard out
   (in player order)

   if log file is enabled, matchName.log will contain finished states
   and values, followed by the final total values for each player

   if transaction file is enabled, matchName.tlog will contain a list
   of actions taken and timestamps that is sufficient to recreate an
   interrupted match

   if the quiet option is not enabled, standard error will print out
   the messages sent to and receieved from the players

   the final total values for each player will be printed to both
   standard out and standard error

   exit value is EXIT_SUCCESS if the match was a success,
   or EXIT_FAILURE on any failure */


#define DEFAULT_MAX_INVALID_ACTIONS UINT32_MAX
#define DEFAULT_MAX_RESPONSE_MICROS 600000000
#define DEFAULT_MAX_USED_HAND_MICROS 600000000
#define DEFAULT_MAX_USED_PER_HAND_MICROS 7000000


typedef struct {
  uint32_t maxInvalidActions;
  uint64_t maxResponseMicros;
  uint64_t maxUsedHandMicros;
  uint64_t maxUsedMatchMicros;

  uint32_t numInvalidActions[ MAX_PLAYERS ];
  uint64_t usedHandMicros[ MAX_PLAYERS ];
  uint64_t usedMatchMicros[ MAX_PLAYERS ];
} ErrorInfo;


static void printUsage( FILE *file, int verbose )
{
  fprintf( file, "usage: dealer matchName gameDefFile #Hands rngSeed p1name p2name ... [options]\n" );
  fprintf( file, "  -f use fixed dealer button at table\n" );
  fprintf( file, "  -l/L disable/enable log file - enabled by default\n" );
  fprintf( file, "  -p player1_port,player2_port,... [default is random]\n" );
  fprintf( file, "  -q only print errors, warnings, and final value to stderr\n" );
  fprintf( file, "  -t/T disable/enable transaction file - disabled by default\n" );
  fprintf( file, "  -a append to log/transaction files - disabled by default\n" );
  fprintf( file, "  --t_response [milliseconds] maximum time per response\n" );
  fprintf( file, "  --t_hand [milliseconds] maximum player time per hand\n" );
  fprintf( file, "  --t_per_hand [milliseconds] maximum average player time for match\n" );
  fprintf( file, "  --start_timeout [milliseconds] maximum time to wait for players to connect\n" );
  fprintf( file, "    <0 [default] is no timeout\n" );
}

/* returns >= 0 on success, -1 on error */
static int scanPortString( const char *string,
			   uint16_t listenPort[ MAX_PLAYERS ] )
{
  int c, r, p;

  c = 0;
  for( p = 0; p < MAX_PLAYERS; ++p ) {

    if( string[ c ] == 0 ) {
      /* finished parsing the string */

      break;
    }

    if( p ) {
      /* look for separator */

      if( string[ c ] != ',' ) {
	/* numbers should be comma separated */

	return -1;
      }
      ++c;
    }

    if( sscanf( &string[ c ], "%"SCNu16"%n", &listenPort[ p ], &r ) < 1 ) {
      /* couldn't get a number */

      return -1;
    }
    c += r;
  }

  return 0;
}

static void initErrorInfo( const uint32_t maxInvalidActions,
			   const uint64_t maxResponseMicros,
			   const uint64_t maxUsedHandMicros,
			   const uint64_t maxUsedMatchMicros,
			   ErrorInfo *info )
{
  int s;

  info->maxInvalidActions = maxInvalidActions;
  info->maxResponseMicros = maxResponseMicros;
  info->maxUsedHandMicros = maxUsedHandMicros;
  info->maxUsedMatchMicros = maxUsedMatchMicros;

  for( s = 0; s < MAX_PLAYERS; ++s ) {
    info->numInvalidActions[ s ] = 0;
    info->usedHandMicros[ s ] = 0;
    info->usedMatchMicros[ s ] = 0;
  }
}
		    

/* update the number of invalid actions for seat
   returns >= 0 if match should continue, -1 for failure */
static int checkErrorInvalidAction( const uint8_t seat, ErrorInfo *info )
{
  ++( info->numInvalidActions[ seat ] );

  if( info->numInvalidActions[ seat ] > info->maxInvalidActions ) {
    return -1;
  }

  return 0;
}

/* update the time used by seat
   returns >= 0 if match should continue, -1 for failure */
static int checkErrorTimes( const uint8_t seat,
			    const struct timeval *sendTime,
			    const struct timeval *recvTime,
			    ErrorInfo *info )
{
  uint64_t responseMicros;

  /* calls to gettimeofday can return earlier times on later calls :/ */
  if( recvTime->tv_sec < sendTime->tv_sec
      || ( recvTime->tv_sec == sendTime->tv_sec
	   && recvTime->tv_usec < sendTime->tv_usec ) ) {
    return 0;
  }

  /* figure out how many microseconds the response took */
  responseMicros = ( recvTime->tv_sec - sendTime->tv_sec ) * 1000000
    + recvTime->tv_usec - sendTime->tv_usec;

  /* update usage counts */
  info->usedHandMicros[ seat ] += responseMicros;
  info->usedMatchMicros[ seat ] += responseMicros;

  /* check time used for the response */
  if( responseMicros > info->maxResponseMicros ) {
    return -1;
  }

  /* check time used in the current hand */
  if( info->usedHandMicros[ seat ] > info->maxUsedHandMicros ) {
    return -1;
  }

  /* check time used in the entire match */
  if( info->usedMatchMicros[ seat ] > info->maxUsedMatchMicros ) {
    return -1;
  }

  return 0;
}

/* note that there is a new hand
   returns >= 0 if match should continue, -1 for failure */
static int checkErrorNewHand( const Game *game, ErrorInfo *info )
{
  uint8_t p;

  for( p = 0; p < game->numPlayers; ++p ) {
    info->usedHandMicros[ p ] = 0;
  }

  return 0;
}


static uint8_t seatToPlayer( const Game *game, const uint8_t player0Seat,
			     const uint8_t seat )
{
  return ( seat + game->numPlayers - player0Seat ) % game->numPlayers;
}

static uint8_t playerToSeat( const Game *game, const uint8_t player0Seat,
			     const uint8_t player )
{
  return ( player + player0Seat ) % game->numPlayers;
}

/* returns >= 0 if match should continue, -1 for failure */
static int sendPlayerMessage( const Game *game, const MatchState *state,
			      const int quiet, const uint8_t seat,
			      const int seatFD, struct timeval *sendTime )
{
  int c;
  char line[ MAX_LINE_LEN ];

  /* prepare the message */
  c = printMatchState( game, state, MAX_LINE_LEN, line );
  if( c < 0 || c > MAX_LINE_LEN - 3 ) {
    /* message is too long */

    fprintf( stderr, "ERROR: state message too long\n" );
    return -1;
  }
  line[ c ] = '\r';
  line[ c + 1 ] = '\n';
  line[ c + 2 ] = 0;
  c += 2;

  /* send it to the player and flush */
  if( write( seatFD, line, c ) != c ) {
    /* couldn't send the line */

    fprintf( stderr, "ERROR: could not send state to seat %"PRIu8"\n",
	     seat + 1 );
    return -1;
  }

  /* note when we sent the message */
  gettimeofday( sendTime, NULL );

  /* log the message */
  if( !quiet ) {
    fprintf( stderr, "TO %d at %zu.%.06zu %s", seat + 1,
	     sendTime->tv_sec, sendTime->tv_usec, line );
  }

  return 0;
}

/* returns >= 0 if action/size has been set to a valid action
   returns -1 for failure (disconnect, timeout, too many bad actions, etc) */
static int readPlayerResponse( const Game *game,
			       const MatchState *state,
			       const int quiet,
			       const uint8_t seat,
			       const struct timeval *sendTime,
			       ErrorInfo *errorInfo,
			       ReadBuf *readBuf,
			       Action *action,
			       struct timeval *recvTime )
{
  int c, r;
  MatchState tempState;
  char line[ MAX_LINE_LEN ];

  while( 1 ) {

    /* read a line of input from player */
    struct timeval start;
    gettimeofday( &start, NULL );
    if( getLine( readBuf, MAX_LINE_LEN, line,
		 errorInfo->maxResponseMicros ) <= 0 ) {
      /* couldn't get any input from player */

      struct timeval after;
      gettimeofday( &after, NULL );
      uint64_t micros_spent =
	(uint64_t)( after.tv_sec - start.tv_sec ) * 1000000
	+ ( after.tv_usec - start.tv_usec );
      fprintf( stderr, "ERROR: could not get action from seat %"PRIu8"\n",
	       seat + 1 );
      // Print out how much time has passed so we can see if this was a
      // timeout as opposed to some other sort of failure (e.g., socket
      // closing).
      fprintf( stderr, "%.1f seconds spent waiting; timeout %.1f\n",
	       micros_spent / 1000000.0,
	       errorInfo->maxResponseMicros / 1000000.0);
      return -1;
    }

    /* note when the message arrived */
    gettimeofday( recvTime, NULL );

    /* log the response */
    if( !quiet ) {
      fprintf( stderr, "FROM %d at %zu.%06zu %s", seat + 1,
	       recvTime->tv_sec, recvTime->tv_usec, line );
    }

    /* ignore comments */
    if( line[ 0 ] == '#' || line[ 0 ] == ';' ) {
      continue;
    }

    /* check for any timeout issues */
    if( checkErrorTimes( seat, sendTime, recvTime, errorInfo ) < 0 ) {

      fprintf( stderr, "ERROR: seat %"PRIu8" ran out of time\n", seat + 1 );
      return -1;
    }

    /* parse out the state */
    c = readMatchState( line, game, &tempState );
    if( c < 0 ) {
      /* couldn't get an intelligible state */

      fprintf( stderr, "WARNING: bad state format in response\n" );
      continue;
    }

    /* ignore responses that don't match the current state */
    if( !matchStatesEqual( game, state, &tempState ) ) {

      fprintf( stderr, "WARNING: ignoring un-requested response\n" );
      continue;
    }

    /* get the action */
    if( line[ c++ ] != ':'
	|| ( r = readAction( &line[ c ], game, action ) ) < 0 ) {

      if( checkErrorInvalidAction( seat, errorInfo ) < 0 ) {

	fprintf( stderr, "ERROR: bad action format in response\n" );
      }

      fprintf( stderr,
	       "WARNING: bad action format in response, changed to call\n" );
      action->type = a_call;
      action->size = 0;
      goto doneRead;
    }
    c += r;

    /* make sure the action is valid */
    if( !isValidAction( game, &state->state, 1, action ) ) {

      if( checkErrorInvalidAction( seat, errorInfo ) < 0 ) {

	fprintf( stderr, "ERROR: invalid action\n" );
	return -1;
      }

      fprintf( stderr, "WARNING: invalid action, changed to call\n" );
      action->type = a_call;
      action->size = 0;
    }

    goto doneRead;
  }

 doneRead:
  return 0;
}

/* returns >= 0 if match should continue, -1 for failure */
static int setUpNewHand( const Game *game, const uint8_t fixedSeats,
			 uint32_t *handId, uint8_t *player0Seat,
			 rng_state_t *rng, ErrorInfo *errorInfo, State *state )
{
  ++( *handId );

  /* rotate the players around the table */
  if( !fixedSeats ) {

    *player0Seat = ( *player0Seat + 1 ) % game->numPlayers;
  }

  if( checkErrorNewHand( game, errorInfo ) < 0 ) {

    fprintf( stderr, "ERROR: unexpected game\n" );
    return -1;
  }
  initState( game, *handId, state );
  dealCards( game, rng, state );

  return 0;
}

/* returns >= 0 if match should continue, -1 for failure */
static int processTransactionFile( const Game *game, const int fixedSeats,
				   uint32_t *handId, uint8_t *player0Seat,
				   rng_state_t *rng, ErrorInfo *errorInfo,
				   double totalValue[ MAX_PLAYERS ],
				   MatchState *state, FILE *file )
{
  int c, r;
  uint32_t h;
  uint8_t s;
  Action action;
  struct timeval sendTime, recvTime;
  char line[ MAX_LINE_LEN ];

  while( fgets( line, MAX_LINE_LEN, file ) ) {

    /* get the log entry */

    /* ACTION */
    c = readAction( line, game, &action );
    if( c < 0 ) {

      fprintf( stderr, "ERROR: could not parse transaction action %s", line );
      return -1;
    }

    /* ACTION HANDID SEND RECV */
    if( sscanf( &line[ c ], " %"SCNu32" %zu.%06zu %zu.%06zu%n", &h,
		&sendTime.tv_sec, &sendTime.tv_usec,
		&recvTime.tv_sec, &recvTime.tv_usec, &r ) < 4 ) {

      fprintf( stderr, "ERROR: could not parse transaction stamp %s", line );
      return -1;
    }
    c += r;

    /* check that we're processing the expected handId */
    if( h != *handId ) {

      fprintf( stderr, "ERROR: handId mismatch in transaction log: %s", line );
      return -1;
    }

    /* make sure the action is valid */
    if( !isValidAction( game, &state->state, 0, &action ) ) {

      fprintf( stderr, "ERROR: invalid action in transaction log: %s", line );
      return -1;
    }

    /* check for any timeout issues */
    s = playerToSeat( game, *player0Seat,
		      currentPlayer( game, &state->state ) );
    if( checkErrorTimes( s, &sendTime, &recvTime, errorInfo ) < 0 ) {

      fprintf( stderr,
	       "ERROR: seat %"PRIu8" ran out of time in transaction file\n",
	       s + 1 );
      return -1;
    }

    doAction( game, &action, &state->state );

    if( stateFinished( &state->state ) ) {
      /* hand is finished */

      /* update the total value for each player */
      for( s = 0; s < game->numPlayers; ++s ) {

	totalValue[ s ]
	  += valueOfState( game, &state->state,
			   seatToPlayer( game, *player0Seat, s ) );
      }

      /* move on to next hand */
      if( setUpNewHand( game, fixedSeats, handId, player0Seat,
			rng, errorInfo, &state->state ) < 0 ) {

	return -1;
      }
    }
  }

  return 0;
}

/* returns >= 0 if match should continue, -1 on failure */
static int logTransaction( const Game *game, const State *state,
			   const Action *action,
			   const struct timeval *sendTime,
			   const struct timeval *recvTime,
			   FILE *file )
{
  int c, r;
  char line[ MAX_LINE_LEN ];

  c = printAction( game, action, MAX_LINE_LEN, line );
  if( c < 0 ) {

    fprintf( stderr, "ERROR: transaction message too long\n" );
    return -1;
  }

  r = snprintf( &line[ c ], MAX_LINE_LEN - c,
		" %"PRIu32" %zu.%06zu %zu.%06zu\n",
		state->handId, sendTime->tv_sec, sendTime->tv_usec,
		recvTime->tv_sec, recvTime->tv_usec );
  if( r < 0 ) {

    fprintf( stderr, "ERROR: transaction message too long\n" );
    return -1;
  }
  c += r;

  if( fwrite( line, 1, c, file ) != c ) {

    fprintf( stderr, "ERROR: could not write to transaction file\n" );
    return -1;
  }
  fflush( file );

  return c;
}

/* returns >= 0 if match should continue, -1 on failure */
static int checkVersion( const uint8_t seat,
			 ReadBuf *readBuf )
{
  uint32_t major, minor, rev;
  char line[ MAX_LINE_LEN ];


  if( getLine( readBuf, MAX_LINE_LEN, line, -1 ) <= 0 ) {

    fprintf( stderr,
	     "ERROR: could not read version string from seat %"PRIu8"\n",
	     seat + 1 );
    return -1;
  }

  if( sscanf( line, "VERSION:%"SCNu32".%"SCNu32".%"SCNu32,
	      &major, &minor, &rev ) < 3 ) {

    fprintf( stderr,
	     "ERROR: invalid version string %s", line );
    return -1;
  }

  if( major != VERSION_MAJOR || minor > VERSION_MINOR ) {

    fprintf( stderr, "ERROR: this server is currently using version %"SCNu32".%"SCNu32".%"SCNu32"\n", VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION );
  }

  return 0;
}

/* returns >= 0 if match should continue, -1 on failure */
static int addToLogFile( const Game *game, const State *state,
			 const double value[ MAX_PLAYERS ],
			 const uint8_t player0Seat,
			 char *seatName[ MAX_PLAYERS ], FILE *logFile )
{
  int c, r;
  uint8_t p;
  char line[ MAX_LINE_LEN ];

  /* prepare the message */
  c = printState( game, state, MAX_LINE_LEN, line );
  if( c < 0 ) {
    /* message is too long */

    fprintf( stderr, "ERROR: log state message too long\n" );
    return -1;
  }

  /* add the values */
  for( p = 0; p < game->numPlayers; ++p ) {

    r = snprintf( &line[ c ], MAX_LINE_LEN - c,
		  p ? "|%.6f" : ":%.6f", value[ p ] );
    if( r < 0 ) {

      fprintf( stderr, "ERROR: log message too long\n" );
      return -1;
    }
    c += r;

    /* remove trailing zeros after decimal-point */
    while( line[ c - 1 ] == '0' ) { --c; }
    if( line[ c - 1 ] == '.' ) { --c; }
    line[ c ] = 0;
  }

  /* add the player names */
  for( p = 0; p < game->numPlayers; ++p ) {

    r = snprintf( &line[ c ], MAX_LINE_LEN - c,
		  p ? "|%s" : ":%s",
		  seatName[ playerToSeat( game, player0Seat, p ) ] );
    if( r < 0 ) {

      fprintf( stderr, "ERROR: log message too long\n" );
      return -1;
    }
    c += r;
  }

  /* print the line to log and flush */
  if( fprintf( logFile, "%s\n", line ) < 0 ) {

    fprintf( stderr, "ERROR: logging failed for game %s\n", line );
    return -1;
  }
  fflush( logFile );

  return 0;
}

/* returns >= 0 if match should continue, -1 on failure */
static int printInitialMessage( const char *matchName, const char *gameName,
				const uint32_t numHands, const uint32_t seed,
				const ErrorInfo *info, FILE *logFile )
{
  int c;
  char line[ MAX_LINE_LEN ];

  c = snprintf( line, MAX_LINE_LEN, "# name/game/hands/seed %s %s %"PRIu32" %"PRIu32"\n#--t_response %"PRIu64"\n#--t_hand %"PRIu64"\n#--t_per_hand %"PRIu64"\n",
		matchName, gameName, numHands, seed,
		info->maxResponseMicros / 1000,
		info->maxUsedHandMicros / 1000,
		info->maxUsedMatchMicros / numHands / 1000 );
  if( c < 0 ) {
    /* message is too long */

    fprintf( stderr, "ERROR: initial game comment too long\n" );
    return -1;
  }

  fprintf( stderr, "%s", line );
  if( logFile ) {

    fprintf( logFile, "%s", line );
  }

  return 0;
}

/* returns >= 0 if match should continue, -1 on failure */
static int printFinalMessage( const Game *game, char *seatName[ MAX_PLAYERS ],
			      const double totalValue[ MAX_PLAYERS ],
			      FILE *logFile )
{
  int c, r;
  uint8_t s;
  char line[ MAX_LINE_LEN ];

  c = snprintf( line, MAX_LINE_LEN, "SCORE" );
  if( c < 0 ) {
    /* message is too long */

    fprintf( stderr, "ERROR: value state message too long\n" );
    return -1;
  }

  for( s = 0; s < game->numPlayers; ++s ) {

    r = snprintf( &line[ c ], MAX_LINE_LEN - c,
		  s ? "|%.6f" : ":%.6f", totalValue[ s ] );
    if( r < 0 ) {

      fprintf( stderr, "ERROR: value message too long\n" );
      return -1;
    }
    c += r;

    /* remove trailing zeros after decimal-point */
    while( line[ c - 1 ] == '0' ) { --c; }
    if( line[ c - 1 ] == '.' ) { --c; }
    line[ c ] = 0;
  }

  /* add the player names */
  for( s = 0; s < game->numPlayers; ++s ) {

    r = snprintf( &line[ c ], MAX_LINE_LEN - c,
		  s ? "|%s" : ":%s", seatName[ s ] );
    if( r < 0 ) {

      fprintf( stderr, "ERROR: log message too long\n" );
      return -1;
    }
    c += r;
  }

  fprintf( stdout, "%s\n", line );
  fprintf( stderr, "%s\n", line );

  if( logFile ) {

    fprintf( logFile, "%s\n", line );
  }

  return 0;
}

/* run a match of numHands hands of the supplied game

   cards are dealt using rng, error conditions like timeouts
   are controlled and stored in errorInfo

   actions are read/sent to seat p on seatFD[ p ]

   if quiet is not zero, only print out errors, warnings, and final value   
   
   if logFile is not NULL, print out a single line for each completed
   match with the final state and all player values.  The values are
   printed in player, not seat order.

   if transactionFile is not NULL, a transaction log of actions made
   is written to the file, and if there is any input left to read on
   the stream when gameLoop is called, it will be processed to
   initialise the state

   returns >=0 if the match finished correctly, -1 on error */
static int gameLoop( const Game *game, char *seatName[ MAX_PLAYERS ],
		     const uint32_t numHands, const int quiet,
		     const int fixedSeats, rng_state_t *rng,
		     ErrorInfo *errorInfo, const int seatFD[ MAX_PLAYERS ],
		     ReadBuf *readBuf[ MAX_PLAYERS ],
		     FILE *logFile, FILE *transactionFile )
{
  uint32_t handId;
  uint8_t seat, p, player0Seat, currentP, currentSeat;
  struct timeval t, sendTime, recvTime;
  Action action;
  MatchState state;
  double value[ MAX_PLAYERS ], totalValue[ MAX_PLAYERS ];

  /* check version string for each player */
  for( seat = 0; seat < game->numPlayers; ++seat ) {

    if( checkVersion( seat, readBuf[ seat ] ) < 0 ) {
      /* error messages already handled in function */

      return -1;
    }
  }

  gettimeofday( &sendTime, NULL );
  if( !quiet ) {
    fprintf( stderr, "STARTED at %zu.%06zu\n",
	     sendTime.tv_sec, sendTime.tv_usec );
  }

  /* start at the first hand */
  handId = 0;
  if( checkErrorNewHand( game, errorInfo ) < 0 ) {

    fprintf( stderr, "ERROR: unexpected game\n" );
    return -1;
  }
  initState( game, handId, &state.state );
  dealCards( game, rng, &state.state );
  for( seat = 0; seat < game->numPlayers; ++seat ) {
    totalValue[ seat ] = 0.0;
  }

  /* seat 0 is player 0 in first game */
  player0Seat = 0;

  /* process the transaction file */
  if( transactionFile != NULL ) {

    if( processTransactionFile( game, fixedSeats, &handId, &player0Seat,
				rng, errorInfo, totalValue,
				&state, transactionFile ) < 0 ) {
      /* error messages already handled in function */

      return -1;
    }
  }

  if( handId >= numHands ) {
    goto finishedGameLoop;
  }

  /* play all the (remaining) hands */
  while( 1 ) {

    /* play the hand */
    while( !stateFinished( &state.state ) ) {

      /* find the current player */
      currentP = currentPlayer( game, &state.state );

      /* send state to each player */
      for( seat = 0; seat < game->numPlayers; ++seat ) {

	state.viewingPlayer = seatToPlayer( game, player0Seat, seat );
	if( sendPlayerMessage( game, &state, quiet, seat,
			       seatFD[ seat ], &t ) < 0 ) {
	  /* error messages already handled in function */

	  return -1;
	}

	/* remember the seat and send time if player is acting */
	if( state.viewingPlayer == currentP ) {

	  sendTime = t;
	}
      }

      /* get action from current player */
      state.viewingPlayer = currentP;
      currentSeat = playerToSeat( game, player0Seat, currentP );
      if( readPlayerResponse( game, &state, quiet, currentSeat, &sendTime,
			      errorInfo, readBuf[ currentSeat ],
			      &action, &recvTime ) < 0 ) {
	/* error messages already handled in function */

	return -1;
      }

      /* log the transaction */
      if( transactionFile != NULL ) {

	if( logTransaction( game, &state.state, &action,
			    &sendTime, &recvTime, transactionFile ) < 0 ) {
	  /* error messages already handled in function */

	  return -1;
	}
      }

      /* do the action */
      doAction( game, &action, &state.state );
    }

    /* get values */
    for( p = 0; p < game->numPlayers; ++p ) {

      value[ p ] = valueOfState( game, &state.state, p );
      totalValue[ playerToSeat( game, player0Seat, p ) ] += value[ p ];
    }

    /* add the game to the log */
    if( logFile != NULL ) {

      if( addToLogFile( game, &state.state, value, player0Seat,
			seatName, logFile ) < 0 ) {
	/* error messages already handled in function */

	return -1;
      }
    }

    /* send final state to each player */
    for( seat = 0; seat < game->numPlayers; ++seat ) {

      state.viewingPlayer = seatToPlayer( game, player0Seat, seat );
      if( sendPlayerMessage( game, &state, quiet, seat,
			     seatFD[ seat ], &t ) < 0 ) {
	/* error messages already handled in function */

	return -1;
      }
    }

    if ( !quiet ) {
      if ( handId % 100 == 0) {
	for( seat = 0; seat < game->numPlayers; ++seat ) {
	  fprintf(stderr, "Seconds cumulatively spent in match for seat %i: "
		  "%i\n", seat,
		  (int)(errorInfo->usedMatchMicros[ seat ] / 1000000));
	}
      }
    }

    /* start a new hand */
    if( setUpNewHand( game, fixedSeats, &handId, &player0Seat,
		      rng, errorInfo, &state.state ) < 0 ) {
      /* error messages already handled in function */

      return -1;
    }
    if( handId >= numHands ) {
      break;
    }
  }

 finishedGameLoop:
  /* print out the final values */
  if( !quiet ) {
    gettimeofday( &t, NULL );
    fprintf( stderr, "FINISHED at %zu.%06zu\n",
	     sendTime.tv_sec, sendTime.tv_usec );
  }
  if( printFinalMessage( game, seatName, totalValue, logFile ) < 0 ) {
    /* error messages already handled in function */

    return -1;
  }

  return 0;
}

int main( int argc, char **argv )
{
  int i, listenSocket[ MAX_PLAYERS ], v, longOpt;
  int fixedSeats, quiet, append;
  int seatFD[ MAX_PLAYERS ];
  FILE *file, *logFile, *transactionFile;
  ReadBuf *readBuf[ MAX_PLAYERS ];
  Game *game;
  rng_state_t rng;
  ErrorInfo errorInfo;
  struct sockaddr_in addr;
  socklen_t addrLen;
  char *seatName[ MAX_PLAYERS ];

  int useLogFile, useTransactionFile;
  uint64_t maxResponseMicros, maxUsedHandMicros, maxUsedPerHandMicros;
  int64_t startTimeoutMicros;
  uint32_t numHands, seed, maxInvalidActions;
  uint16_t listenPort[ MAX_PLAYERS ];

  struct timeval startTime, tv;

  char name[ MAX_LINE_LEN ];
  static struct option longOptions[] = {
    { "t_response", 1, 0, 0 },
    { "t_hand", 1, 0, 0 },
    { "t_per_hand", 1, 0, 0 },
    { "start_timeout", 1, 0, 0 },
    { 0, 0, 0, 0 }
  };

  /* set defaults */

  /* game error conditions */
  maxInvalidActions = DEFAULT_MAX_INVALID_ACTIONS;
  maxResponseMicros = DEFAULT_MAX_RESPONSE_MICROS;
  maxUsedHandMicros = DEFAULT_MAX_USED_HAND_MICROS;
  maxUsedPerHandMicros = DEFAULT_MAX_USED_PER_HAND_MICROS;

  /* use random ports */
  for( i = 0; i < MAX_PLAYERS; ++i ) {

    listenPort[ i ] = 0;
  }

  /* use log file, don't use transaction file */
  useLogFile = 1;
  useTransactionFile = 0;

  /* print all messages */
  quiet = 0;

  /* by default, overwrite preexisting log/transaction files */
  append = 0;

  /* players rotate around the table */
  fixedSeats = 0;

  /* no timeout on startup */
  startTimeoutMicros = -1;

  /* parse options */
  while( 1 ) {

    i = getopt_long( argc, argv, "flLp:qtTa", longOptions, &longOpt );
    if( i < 0 ) {

      break;
    }

    switch( i ) {
    case 0:
      /* long option longOpt */

      switch( longOpt ) {
      case 0:
	/* t_response */

	if( sscanf( optarg, "%"SCNu64, &maxResponseMicros ) < 1 ) {

	  fprintf( stderr, "ERROR: could not get response timeout from %s\n",
		   optarg );
	  exit( EXIT_FAILURE );
	}

	/* convert from milliseconds to microseconds */
	maxResponseMicros *= 1000;
	break;

      case 1:
	/* t_hand */

	if( sscanf( optarg, "%"SCNu64, &maxUsedHandMicros ) < 1 ) {

	  fprintf( stderr,
		   "ERROR: could not get player hand timeout from %s\n",
		   optarg );
	  exit( EXIT_FAILURE );
	}

	/* convert from milliseconds to microseconds */
	maxUsedHandMicros *= 1000;
	break;

      case 2:
	/* t_per_hand */

	if( sscanf( optarg, "%"SCNu64, &maxUsedPerHandMicros ) < 1 ) {

	  fprintf( stderr, "ERROR: could not get average player hand timeout from %s\n", optarg );
	  exit( EXIT_FAILURE );
	}

	/* convert from milliseconds to microseconds */
	maxUsedPerHandMicros *= 1000;
	break;

      case 3:
	/* start_timeout */

	if( sscanf( optarg, "%"SCNd64, &startTimeoutMicros ) < 1 ) {

	  fprintf( stderr, "ERROR: could not get start timeout %s\n", optarg );
	  exit( EXIT_FAILURE );
	}

	/* convert from milliseconds to microseconds */
	if( startTimeoutMicros > 0 ) {

	  startTimeoutMicros *= 1000;
	}
	break;

      }
      break;

    case 'f':
      /* fix the player seats */;

      fixedSeats = 1;
      break;

    case 'l':
      /* no transactionFile */;

      useLogFile = 0;
      break;

    case 'L':
      /* use transactionFile */;

      useLogFile = 1;
      break;

    case 'p':
      /* port specification */

      if( scanPortString( optarg, listenPort ) < 0 ) {

	fprintf( stderr, "ERROR: bad port string %s\n", optarg );
	exit( EXIT_FAILURE );
      }

      break;

    case 'q':

      quiet = 1;
      break;

    case 't':
      /* no transactionFile */

      useTransactionFile = 0;
      break;

    case 'T':
      /* use transactionFile */

      useTransactionFile = 1;
      break;

    case 'a':

      append = 1;
      break;

    default:

      fprintf( stderr, "ERROR: unknown option %c\n", i );
      exit( EXIT_FAILURE );
    }
  }

  if( optind + 4 > argc ) {

    printUsage( stdout, 0 );
    exit( EXIT_FAILURE );
  }

  /* get the game definition */
  file = fopen( argv[ optind + 1 ], "r" );
  if( file == NULL ) {

    fprintf( stderr, "ERROR: could not open game definition %s\n",
	     argv[ optind + 1 ] );
    exit( EXIT_FAILURE );
  }
  game = readGame( file );
  if( game == NULL ) {

    fprintf( stderr, "ERROR: could not read game %s\n", argv[ optind + 1 ] );
    exit( EXIT_FAILURE );
  }
  fclose( file );

  /* save the seat names */
  if( optind + 4 + game->numPlayers > argc ) {

    printUsage( stdout, 0 );
    exit( EXIT_FAILURE );
  }
  for( i = 0; i < game->numPlayers; ++i ) {

    seatName[ i ] = argv[ optind + 4 + i ];
  }

  /* get number of hands */
  if( sscanf( argv[ optind + 2 ], "%"SCNu32, &numHands ) < 1
      || numHands == 0 ) {

    fprintf( stderr, "ERROR: invalid number of hands %s\n",
	     argv[ optind + 2 ] );
    exit( EXIT_FAILURE );
  }

  /* get random number seed */
  if( sscanf( argv[ optind + 3 ], "%"SCNu32, &seed ) < 1 ) {

    fprintf( stderr, "ERROR: invalid random number seed %s\n",
	     argv[ optind + 3 ] );
    exit( EXIT_FAILURE );
  }
  init_genrand( &rng, seed );
  srandom( seed ); /* used for random port selection */

  if( useLogFile ) {
    /* create/open the log */
    if( snprintf( name, MAX_LINE_LEN, "%s.log", argv[ optind ] ) < 0 ) {

      fprintf( stderr, "ERROR: match file name too long %s\n", argv[ optind ] );
      exit( EXIT_FAILURE );
    }
    if (append) {
      logFile = fopen( name, "a+" );
    } else {
      logFile = fopen( name, "w" );
    }
    if( logFile == NULL ) {

      fprintf( stderr, "ERROR: could not open log file %s\n", name );
      exit( EXIT_FAILURE );
    }
  } else {
    /* no log file */

    logFile = NULL;
  }

  if( useTransactionFile ) {
    /* create/open the transaction log */

    if( snprintf( name, MAX_LINE_LEN, "%s.tlog", argv[ optind ] ) < 0 ) {

      fprintf( stderr, "ERROR: match file name too long %s\n", argv[ optind ] );
      exit( EXIT_FAILURE );
    }
    if (append) {
      transactionFile = fopen( name, "a+" );
    } else {
      transactionFile = fopen( name, "w" );
    }
    if( transactionFile == NULL ) {

      fprintf( stderr, "ERROR: could not open transaction file %s\n", name );
      exit( EXIT_FAILURE );
    }
  } else { 
    /* no transaction file */

    transactionFile = NULL;
  }

  /* set up the error info */
  initErrorInfo( maxInvalidActions, maxResponseMicros, maxUsedHandMicros,
		 maxUsedPerHandMicros * numHands, &errorInfo );

  /* open sockets for players to connect to */
  for( i = 0; i < game->numPlayers; ++i ) {

    listenSocket[ i ] = getListenSocket( &listenPort[ i ] );
    if( listenSocket[ i ] < 0 ) {

      fprintf( stderr, "ERROR: could not create listen socket for player %d\n",
	       i + 1 );
      exit( EXIT_FAILURE );
    }
  }

  /* print out the final port assignments */
  for( i = 0; i < game->numPlayers; ++i ) {

    printf( i ? " %"PRIu16 : "%"PRIu16, listenPort[ i ] );
  }
  printf( "\n" );
  fflush( stdout );

  /* print out usage information */
  printInitialMessage( argv[ optind ], argv[ optind + 1 ],
		       numHands, seed, &errorInfo, logFile );

  /* wait for each player to connect */
  gettimeofday( &startTime, NULL );
  for( i = 0; i < game->numPlayers; ++i ) {

    if( startTimeoutMicros >= 0 ) {
      uint64_t startTimeLeft;
      fd_set fds;

      gettimeofday( &tv, NULL );
      startTimeLeft = startTimeoutMicros
	- (uint64_t)( tv.tv_sec - startTime.tv_sec ) * 1000000
	- ( tv.tv_usec - startTime.tv_usec );
      if( startTimeLeft < 0 ) {

	startTimeLeft = 0;
      }
      tv.tv_sec = startTimeLeft / 1000000;
      tv.tv_usec = startTimeLeft % 1000000;

      FD_ZERO( &fds );
      FD_SET( listenSocket[ i ], &fds );
      if( select( listenSocket[ i ] + 1, &fds, NULL, NULL, &tv ) < 1 ) {
	/* no input ready within time, or an actual error */

	fprintf( stderr, "ERROR: timed out waiting for seat %d to connect\n",
		 i + 1 );
	exit( EXIT_FAILURE );
      }
    }

    addrLen = sizeof( addr );
    seatFD[ i ] = accept( listenSocket[ i ],
			  (struct sockaddr *)&addr, &addrLen );
    if( seatFD[ i ] < 0 ) {

      fprintf( stderr, "ERROR: seat %d could not connect\n", i + 1 );
      exit( EXIT_FAILURE );
    }
    close( listenSocket[ i ] );

    v = 1;
    setsockopt( seatFD[ i ], IPPROTO_TCP, TCP_NODELAY,
		(char *)&v, sizeof(int) );

    readBuf[ i ] = createReadBuf( seatFD[ i ] );
  }

  /* play the match */
  if( gameLoop( game, seatName, numHands, quiet, fixedSeats, &rng, &errorInfo,
		seatFD, readBuf, logFile, transactionFile ) < 0 ) {
    /* should have already printed an error message */

    exit( EXIT_FAILURE );
  }

  fflush( stderr );
  fflush( stdout );
  if( transactionFile != NULL ) {
    fclose( transactionFile );
  }
  if( logFile != NULL ) {
    fclose( logFile );
  }
  free( game );

  return EXIT_SUCCESS;
}
