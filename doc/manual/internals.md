# Internals

## Lookahead

A @{lookahead|Lookahead} implements the CFR algorithm on a small lookahead tree using
tensors. The CFR algorithm essentially repeatedly walks down and up an
extensive-form game tree. In our representation, we work with a public tree
and perform all the operations with vectors (ranges) of cards in public nodes.
The key of this class is the way a tree is represented in the tensors.  First,
each layer of a tree is stored in a separate tensor. Second, the tensor for
each layer has a large number of dimensions structured in a way to make the top
and down phases efficient and simple to implement via tensor operations.

The first three dimensions of these tensors encode the coordinates of the node
in the tree:

```
action_id x parent_action_id x grandparent_id
```

* `action_id`: the index of the action that led to this node from its parent
(in `[1..actions count]`)
* `parent_action_id`: the index of the action that led to this node's parent
from its grandparent (in `[1..actions count]`)
* `grandparent_id`: the index of the node's grandparent in the list of
nonterminal nodes of the corresponding layer (in `[1..num_nonterminal_nodes]`)

While this looks confusing at first, we will see that it makes all of the
operations we need for CFR very easy to do. First, have a look at the following
picture to see the coordinates for a small tree: 

[<img src="lookahead_tree.png" alt="lookahead tree" style="width: 500px;"/>](lookahead_tree.png)

Once you understand the coordinates, you will see how easy is to do the
necessary CFR operations.

Here's a few examples of how to do easy (and fast) operations with this
representation:

select all fold nodes (fold is the first action): 
```lua
nodes[1]
```

select all call nodes (call is the second action): 
```lua
nodes[2]
```

select all nodes where an all-in bet was called (call is the second action and
all-in is the last action of the parent): 
```lua
nodes[2][-1]
```

As mentioned, these are the first three coordinates of all the tensors used in
the lookaehad. Other dimensions (based on the data we store) typically are
`players` (since we store often data for both players) and `cards` (since we
need to store data for all cards). Finally, note that because of this
representation, some nodes are just "padding" (because the tensor indices do
not correspond to a real node of the tree). We thus define a tensor data
structure that can mask out these non-existent nodes.
