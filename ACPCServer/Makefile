CC = gcc
CFLAGS = -O3 -Wall

PROGRAMS = all_in_expectation bm_run_matches dealer example_player

all: $(PROGRAMS)

clean:
	rm -f $(PROGRAMS)


all_in_expectation: all_in_expectation.c game.c game.h rng.c rng.h net.c net.h
	$(CC) $(CFLAGS) -o $@ all_in_expectation.c game.c rng.c net.c

bm_server: bm_server.c game.c game.h rng.c rng.h net.c net.h
	$(CC) $(CFLAGS) -o $@ bm_server.c game.c rng.c net.c

bm_widget: bm_widget.c net.c net.h
	$(CC) $(CFLAGS) -o $@ bm_widget.c net.c

bm_run_matches: bm_run_matches.c net.c net.h
	$(CC) $(CFLAGS) -o $@ bm_run_matches.c net.c

dealer: game.c game.h evalHandTables rng.c rng.h dealer.c net.c net.h
	$(CC) $(CFLAGS) -o $@ game.c rng.c dealer.c net.c

example_player: game.c game.h evalHandTables rng.c rng.h example_player.c net.c net.h
	$(CC) $(CFLAGS) -o $@ game.c rng.c example_player.c net.c
