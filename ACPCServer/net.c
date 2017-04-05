/*
Copyright (C) 2011 by the Computer Poker Research Group, University of Alberta
*/

#include <unistd.h>
#include <netdb.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include "net.h"


ReadBuf *createReadBuf( int fd )
{
  ReadBuf *readBuf = (ReadBuf*)malloc( sizeof( ReadBuf ) );
  if( readBuf == 0 ) {

    return readBuf;
  }

  readBuf->fd = fd;
  readBuf->bufStart = 0;
  readBuf->bufEnd = 0;

  return readBuf;
}

void destroyReadBuf( ReadBuf *readBuf )
{
  close( readBuf->fd );
  free( readBuf );
}

/* get a newline terminated line and place it as a string in 'line'
   terminates the string with a 0 character
   if timeoutMicros is non-negative, do not spend more than
   that number of microseconds waiting to read data
   return number of characters read (including newline, excluding 0)
   0 on end of file, or -1 on error or timeout */
ssize_t getLine( ReadBuf *readBuf,
		 size_t maxLen,
		 char *line,
		 int64_t timeoutMicros )
{
  int haveStartTime, c;
  ssize_t len;
  fd_set fds;
  struct timeval start, tv;

  /* reserve space for string terminator */
  --maxLen;
  if( maxLen < 0 ) {
    return -1;
  }

  /* read the line */
  haveStartTime = 0;
  len = 0;
  while( len < maxLen ) {

    if( readBuf->bufStart >= readBuf->bufEnd ) {
      /* buffer is empty */

      if( timeoutMicros >= 0 ) {
	/* figure out how much time is left for reading */
	uint64_t timeLeft;

	timeLeft = timeoutMicros;
	if( haveStartTime ) {

	  gettimeofday( &tv, NULL );
	  timeLeft -= (uint64_t)( tv.tv_sec - start.tv_sec ) * 1000000
	    + ( tv.tv_usec - start.tv_usec );
	  if( timeLeft < 0 ) {

	    timeLeft = 0;
	  }
	} else {

	  haveStartTime = 1;
	  gettimeofday( &start, NULL );
	}
	tv.tv_sec = timeLeft / 1000000;
	tv.tv_usec = timeLeft % 1000000;

	/* wait for file descriptor to be ready */
	FD_ZERO( &fds );
	FD_SET( readBuf->fd, &fds );
	if( select( readBuf->fd + 1, &fds, NULL, NULL, &tv ) < 1 ) {
	  /* no input ready within time, or an actual error */
	
	  return -1;
	}
      }

      /* try reading a buffer full of data */
      readBuf->bufStart = 0;
      readBuf->bufEnd = read( readBuf->fd, readBuf->buf, READBUF_LEN );
      if( readBuf->bufEnd == 0 ) {
	/* end of input */

	break;
      } else if( readBuf->bufEnd < 0 ) {
	/* error condition */

	readBuf->bufEnd = 0;
	return -1;
      }
    }

    /* keep adding to the string until we see a newline */
    c = readBuf->buf[ readBuf->bufStart ];
    ++readBuf->bufStart;
    line[ len ] = c;
    ++len;
    if( c == '\n' ) {

      break;
    }
  }

  /* terminate the string */
  line[ len ] = 0;
  return len;
}


int connectTo( char *hostname, uint16_t port )
{
  int sock;
  struct hostent *hostent;
  struct sockaddr_in addr;

  hostent = gethostbyname( hostname );
  if( hostent == NULL ) {

    fprintf( stderr, "ERROR: could not look up address for %s\n", hostname );
    return -1;
  }

  if( ( sock = socket( AF_INET, SOCK_STREAM, 0 ) ) < 0 ) {

    fprintf( stderr, "ERROR: could not open socket\n" );
    return -1;
  }

  addr.sin_family = AF_INET;
  addr.sin_port = htons( port );
  memcpy( &addr.sin_addr, hostent->h_addr_list[ 0 ], hostent->h_length );

  if( connect( sock, (struct sockaddr *)&addr, sizeof( addr ) ) < 0 ) {

    fprintf( stderr, "ERROR: could not connect to %s:%"PRIu16"\n",
	     hostname, port );
    return -1;
  }

  return sock;
}

int getListenSocket( uint16_t *desiredPort )
{
  int sock, t;
  struct sockaddr_in addr;

  if( ( sock = socket( AF_INET, SOCK_STREAM, 0 ) ) < 0 ) {

    return -1;
  }

  /* allow fast socket reuse - ignore failure */
  t = 1;
  setsockopt( sock, SOL_SOCKET, SO_REUSEADDR, &t, sizeof( int ) );

  /* bind the socket to the port */
  if( *desiredPort != 0 ) {

    addr.sin_family = AF_INET;
    addr.sin_port = htons( *desiredPort );
    addr.sin_addr.s_addr = htonl( INADDR_ANY );
    if( bind( sock, (struct sockaddr *)&addr, sizeof( addr ) ) < 0 ) {

      return -1;
    }
  } else {

    t = 0;
    while( 1 ) {
      addr.sin_family = AF_INET;
      *desiredPort = ( random() % 64512 ) + 1024;
      addr.sin_port = htons( *desiredPort );
      addr.sin_addr.s_addr = htonl( INADDR_ANY );
      if( bind( sock, (struct sockaddr *)&addr, sizeof( addr ) ) < 0 ) {

	if( t < NUM_PORT_CREATION_ATTEMPTS ) {

	  ++t;
	  continue;
	} else {

	  return -1;
	}
      }

      break;
    }
  }

  /* listen on the socket */
  if( listen( sock, 8 ) < 0 ) {

    return -1;
  }

  return sock;
}
