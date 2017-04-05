#include <stdlib.h>
#include <stdio.h>
#define __STDC_FORMAT_MACROS
#include <inttypes.h>
#include <assert.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/wait.h>
#include <errno.h>
#include "net.h"

#define ARG_SERVERNAME 1
#define ARG_SERVERPORT 2
#define ARG_BOT_COMMAND 7
#define ARG_MIN_ARGS 6

static void printUsage( FILE *file )
{
  fprintf( file, "Sample usages:\n" );
  fprintf( file, "  bm_run_matches <bm_hostname> <bm_port> <username> <pw> "
	   "games\n" );
  fprintf( file, "    See a list of possible opponents\n" );
  fprintf( file, "  bm_run_matches <bm_hostname> <bm_port> <username> <pw> "
	   "run 2pl <local script> <# runs> <tag> <seed> <player1> "
	   "<player2>\n" );
  fprintf( file, "    Run two-player limit matches\n" );
  fprintf( file, "  bm_run_matches <bm_hostname> <bm_port> <username> <pw> "
	   "run 2pn <local script> <# runs> <tag> <seed> <player1> "
	   "<player2>\n" );
  fprintf( file, "    Run two-player no-limit matches\n" );
  fprintf( file, "  bm_run_matches <bm_hostname> <bm_port> <username> <pw> "
	   "run 3pl <local script> <# runs> <tag> <seed> <player1> <player2> "
	   "<player3>\n" );
  fprintf( file, "    Run three-player limit matches\n" );
  fprintf( file, "  bm_run_matches <bm_hostname> <bm_port> <username> <pw> "
	   "rerun 2pl <local script> <match index> <tag> <seed> <player1> "
	   "<player2> (<player3>)\n" );
  fprintf( file, "    Rerun a match that failed\n" );
  fprintf( file, "\n" );
  fprintf( file, "<username> is your benchmark server username assigned to "
	   "you by the competition chair\n" );
  fprintf( file, "<pw> is your benchmark server password assigned to you by "
	   "the competition chair\n" );
  fprintf( file, "<local script> is the script that runs your agent locally.  "
	   "It must take a hostname/IP and a port\n" );
  fprintf( file, "<num runs> is the number of matches you want to run\n" );
  fprintf( file, "<tag> is a name for this set of matches which will appear "
	   "in the names of the log files\n" );
  fprintf( file, "<seed> is a seed used to generate the random seeds that "
	   "determine the cards in each match\n" );
  fprintf( file, "<player-n> is either the name of an opponent or \"local\" "
	   "for your local agent\n" );
  fprintf( file, "\n" );
  fprintf( file, "To run N duplicate heads-up matches, do one run of N "
	   "matches with a given seed, then run a second set of N matches "
	   "with the same seed but the order of the players reversed\n" );
  fprintf( file, "\n" );
  fprintf( file, "If one match in a set fails, you can use the \"rerun\" "
	   "command to rerun the specified match with the specified seed.  "
	   "For example, if you tried to run twenty matches with seed 0 and "
	   "the last match failed, you could use the \"rerun\" command with "
	   "seed 0 and match index 19.\n" );
}

int main( int argc, char **argv )
{
  int sock, i;
  pid_t childPID;
  uint16_t port;
  ReadBuf *fromServer;
  fd_set readfds;
  char line[ READBUF_LEN ];

  if( argc < ARG_MIN_ARGS ) {

    printUsage( stderr );
    exit( EXIT_FAILURE );
  }

  /* connect to the server */
  if( sscanf( argv[ ARG_SERVERPORT ], "%"SCNu16, &port ) < 1 ) {

    fprintf( stderr, "ERROR: invalid port %s\n", argv[ ARG_SERVERPORT ] );
    exit( EXIT_FAILURE );
  }
  sock = connectTo( argv[ ARG_SERVERNAME ], port );
  if( sock < 0 ) {

    exit( EXIT_FAILURE );
  }

  // EJ additions 9/3/2012
  // Turn on keep-alive for socket connection with more frequent checking
  // than the Linux default.  What I've observed is that if a socket
  // connection is idle for long enough it gets dropped.  This only
  // happens for some users.
  int on = 1;
  if (setsockopt(sock, SOL_SOCKET, SO_KEEPALIVE, &on, sizeof(on)) == -1) {
    fprintf( stderr, "ERROR: setsockopt failed; errno %i\n", errno );
    exit( EXIT_FAILURE );
  }
#ifdef __linux__
  // Not sure what this should be
  int num_before_failure = 2;
  if (setsockopt(sock, SOL_TCP, TCP_KEEPCNT, &num_before_failure,
		 sizeof(num_before_failure)) == -1) {
    fprintf( stderr, "ERROR: setsockopt failed; errno %i\n", errno );
    exit( EXIT_FAILURE );
  }
  // First check after 60 seconds
  int initial_secs = 60;
  if (setsockopt(sock, SOL_TCP, TCP_KEEPIDLE, &initial_secs,
		 sizeof(initial_secs)) == -1) {
    fprintf( stderr, "ERROR: setsockopt failed; errno %i\n", errno );
    exit( EXIT_FAILURE );
  }
  // Thereafter, also check every 60 seconds
  int interval_secs = 60;
  if (setsockopt(sock, SOL_TCP, TCP_KEEPINTVL, &interval_secs,
		 sizeof(interval_secs)) == -1) {
    fprintf( stderr, "ERROR: setsockopt failed; errno %i\n", errno );
    exit( EXIT_FAILURE );
  }
#endif

  /* set up read buffers */
  fromServer = createReadBuf( sock );

  /* write to server */
  line[0] = 0;
  for( i = 3; i < argc; ++i ) {
    strcat( line, argv[i] );
    if ( i < argc - 1 ) {
      strcat( line, " " );
    }
  }
  strcat( line, "\n" );
  int len = strlen(line);
  if( write( sock, line, len ) < 0 ) {
    
    fprintf( stderr, "ERROR: failed while sending to server\n" );
    exit( EXIT_FAILURE );
  }

  /* main loop */
  while( 1 ) {

    /* clean up any children */
    while( waitpid( -1, NULL, WNOHANG ) > 0 );

    /* wait for input */
    FD_ZERO( &readfds );
    FD_SET( sock, &readfds );
    i = select( sock + 1, &readfds, NULL, NULL, NULL );
    if( i < 0 ) {

      fprintf( stderr, "ERROR: select failed\n" );
      exit( EXIT_FAILURE );
    }
    if( i == 0 ) {
      /* nothing ready - shouldn't happen without timeout */

      continue;
    }

    /* handle server messages */
    if( FD_ISSET( sock, &readfds ) ) {

      /* get the input */
      while( ( i = getLine( fromServer, READBUF_LEN, line, 0 ) ) >= 0 ) {

	if( i == 0 ) {

	  /* This could be an error or could just signify successful
	     completion of all matches */
	  fprintf( stderr, "Server closed connection\n" );
	  exit( EXIT_SUCCESS );
	}

	/* check for server commands */
	if( strncasecmp( line, "run ", 4 ) == 0 ) {

	  /* split the rest of the line into name ' ' port */
	  for( i = 4; line[ i ]; ++i ) {

	    if( line[ i ] == ' ' ) {
	      /* found the separator */

	      line[ i ] = 0;
	      break;
	    }
	  }

	  printf( "starting match %s:%s", &line[ 4 ], &line[ i + 1 ] );
	  fflush( stdout );

	  /* run `command machine port` */
	  childPID = fork();
	  if( childPID < 0 ) {

	    fprintf( stderr, "ERROR: fork() failed\n" );
	    exit( EXIT_FAILURE );
	  }
	  if( childPID == 0 ) {
	    /* child runs the command */

	    execl( argv[ ARG_BOT_COMMAND ],
		   argv[ ARG_BOT_COMMAND ],
		   &line[ 4 ],
		   &line[ i + 1 ],
		   NULL );
	    fprintf( stderr,
		     "ERROR: could not run %s\n",
		     argv[ ARG_BOT_COMMAND ] );
	    exit( EXIT_FAILURE );
	  }
	} else {
	  /* just a message, print it out */

	  if( fwrite( line, 1, i, stdout ) < 0 ) {

	    fprintf( stderr, "ERROR: failed while printing server message\n" );
	    exit( EXIT_FAILURE );
	  }
	  fflush( stdout );

	  if( ! strcmp( line, "Matches finished\n") ) {
	    exit( EXIT_SUCCESS );
	  }
	}
      }
    }
  }

  return EXIT_SUCCESS;
}
