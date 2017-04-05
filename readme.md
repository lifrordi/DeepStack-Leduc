# DeepStack for Leduc Hold'em

[DeepStack](https://www.deepstack.ai) is an artificial intelligence agent
designed by a joint team from the University of Alberta, Charles University,
and Czech Technical University. In [a study](https://www.deepstack.ai/s/DeepStack.pdf)
completed in December 2016, DeepStack became the first program to beat human
professionals in the game of heads-up (two player) no-limit Texas hold'em, a
commonly played poker game.

This project reimplements DeepStack as a player for heads-up no-limit
[Leduc holdem](#leduc-hold'em), a much simpler game than Texas hold'em. 

DeepStack is built around two components:
* An offline component that solves random **poker situations** (public game
states along with probability vectors over private hands for both players) and
uses them to train a neural network. After training, this neural network can
accurately predict the value to each player of holding each possible hand at a
given poker situation.
* An online component which uses the **continuous re-solving** algorithm to
dynamically choose an action for DeepStack to play at each public state 
encountered during gameplay. This algorithm solves a depth-limited lookahead
using the neural net to estimate values at terminal states.

The strategy played by DeepStack approximates a **Nash Equilibrium**, with an
approximation error that depends on the error of the neural net and the
solution error of the solver used in continuous re-solving.

## Prerequisites

Running any of the DeepStack code requires [Lua](https://www.lua.org/) and [torch](http://torch.ch/).
Torch is only officially supported for *NIX based systems (i.e. Linux and Mac 
OS X), and as such, **we don't  officially support installation of DeepStack
on Windows systems**. [This page](https://github.com/torch/torch7/wiki/Windows)
contains suggestions for using torch on a Windows machine; if you decide to try
this, we cannot offer any help.

Connecting DeepStack to a server requires the [luasocket](http://w3.impa.br/~diego/software/luasocket/)
package. This can be installed with [luarocks](https://luarocks.org/) (which is
installed as part of the standard torch distribution) using the command 
`luarocks install luasocket`. Visualising the trees produced by DeepStack
requires the [graphviz](http://graphviz.org/) package, which can be installed
with `luarocks install graphviz`. Running the code on the GPU requires
[cutorch](https://github.com/torch/cutorch). Currently only version 1.0 is supported which can be installed with
`luarocks install cutorch 1.0-0`.

The DeepStack player uses the protocol of the Annual Computer Poker Competition
(a description of the protocol can be found [here](http://www.computerpokercompetition.org/downloads/documents/protocols/protocol.pdf))
to receive poker states and send poker actions as messages over a network
socket connection. If you wish to play against DeepStack, you will need a
server for DeepStack to connect to that acts as the dealer for the game; code
for a server that fills this role is available through the ACPC
[here](http://www.computerpokercompetition.org/downloads/code/competition_server/project_acpc_server_v1.0.41.tar.bz2).
For convenience, we include a copy of the ACPC dealer in the `ACPCDealer/`
directory, along with a game definition file (`ACPCDealer/leduc.game`) so that
the dealer can play Leduc hold'em.

If you would like to personally play against DeepStack, you will need a way of
interacting with the server yourself; one such option is the ACPC GUI available
from Dustin Morrill [here](https://github.com/dmorrill10/acpc_poker_gui_client/tree/v1.2).

## Leduc Hold'em

Leduc Hold'em is a toy poker game sometimes used in academic research (first
introduced in [Bayes' Bluff: Opponent Modeling in Poker](http://poker.cs.ualberta.ca/publications/UAI05.pdf)). 
It is played with a deck of six cards, comprising two suits of three ranks each
(often the king, queen, and jack - in our implementation, the ace, king, and
queen). The game begins with each player being dealt one card privately,
followed by a betting round. Then, another card is dealt faceup as a community
(or board) card, and there is another betting round. Finally, the players
reveal their private cards. If one player's private card is the same rank as
the board card, he or she wins the game; otherwise, the player whose private
card has the higher rank wins.

The game that we implement is No-Limit Leduc Hold'em, meaning that whenever a
player makes a bet, he or she may wager any amount of chips up to a maximum of
that player's remaining stack. There is also no limit on the number of bets and
raises that can be made in each betting round.

## Documentation

Documentation for the DeepStack Leduc codebase can be found [here](doc/index.html).
In particular, there is [a tutorial](doc/manual/tutorial.md) which
introduces the codebase and walks you through several examples, including
running DeepStack.

The documentation for code files was automatically generated with [LDoc](https://github.com/stevedonovan/LDoc),
which can be installed with `luarocks install ldoc`. To re-generate the docs,
run `ldoc .` in the `doc/` directory. If you wish to also generate
documentation for local functions, run `ldoc . -all` instead.