# Golem Auto Helper

This helps with early-game tasks by doing the following actions:

  * Remove excess coal from Burner Mining Drills (allows a pair of drills to produce coal)
  * Adds coal to Burner Mining Drills
  * Adds coal to Stone and Steel Furnaces
  * Adds ores/input to Stone and Steel Furnaces
  * Removes output from Furnaces
  * Tops off (adds) coal to Boilers, vehicles, etc (anything that burns coal)
  * Adds missing ingredients to assemblers
  * Character logistics using inventory filter slots
  * Moves items to/from storage chests (new entity)
  * Provides a tower that does the same as the player

The player/tower must be able to reach the entity for items to be moved.
That uses the 'reach_distance' field from the character.
The items are removed from and added to the inventory of a player.

## Transfer Tower

The Transfer Tower acts like the player.
It has a larger radius (unless you changed the player reach).
It is crafter from copper and iron and has inventory slots.
(TODO) It uses uses electricity to transfer items.

A Transfer Tower is also treated like a storage chest.

They do not coordinate, so a request under one tower cannot be satisfied by another tower.
(REVISIT: may be able to set a filter in the Transfer Tower to request items from other
transfer towers. But that tends to create a loop.)

## Chests

There are three types of chests:
  - storage
  - provider
  - requester

These are smaller chests similar to their logistics counterparts.
They can be crafted from an iron chest and some circuits, so they are cheaper that the real logistic chests.

(TODO: base off real logistic chests?)


### Provider Chest (based on "logistic-chest-passive-provider")

This is a chest that requests that all inventory be removed once every 10 seconds.
It is useful at the end of a mining belt.
Items are moved by the player or tower.


### Storage Chest (based on "logistic-chest-storage")

This is the general "storage" chest.
Excess inventory from the player is dumped into Storage Chests.
Request inventory is taken from Storage Chests.

Insufficient Storage chests may cause a tower to cease functioning.

Player inventory and a Tower are treated like a storage chest.

When inserting items, a storage chest is selected based on a score.
The score is the number of items that can be inserted plus a bonus.
  - bonus +1 if the chest is empty
  - bonus +2 if the chest already contains that item

This tends to keep one item per storage chest, if there are sufficient chests.


### Request Chest (based on "logistic-chest-requester")

A Request Chest uses a filter to indicate that a slot should be filled with an item.
This produces a request to transfer items to that container.

Since the tower/player automatically fills assembler ingredients, there isn't much of
a use for this. Perhaps it could be used to bridge two towers by putting a
requester at the edge of one tower and use a belt/inserter to move inventory to a
Storage chest in the zone of another tower.


## Entity Item Transfers

Only coal is used as a fuel. Not wood or solid-fuel.

Each entity that can be services is tracked.
One entity per tick is examined for possible service needs.

If an entity needs to be serviced, then it sets NV field "request", "provide", and "priority".

For generic refuel, if more than 1/2 a coal stack can be added, then a "request" entry is added.
If the fuel item count < 3 the the priority is 3. Otherwise it is 2.
The request is to top off the fuel.
The same fuel type is requested if there is fuel present. (put in wood and it will keep filling with wood)
If the fuel inventory slots are empty, then coal is requested.

Furnaces use the generic refuel routine.
They also use the generic recipe routine if the input item count < 10.
They add a remove-all request if the output count is > 10.


If a mining drill is NOT on coal ore, then it uses the generic refuel.
If a mining drill is on coal, then the coal level is limited.
If below 5, then enough is added to reach 6.
If above 1/2 stack, then enough is removed to each 6.

For the boiler and other fueled entities, the generic refuel routine is used.

For the assembler, a service is scheduled if status==item_ingredient_shortage.
On service, inventory is added to the assembler to produce 2 recipes.


## Configuration

Per-Player:
  * Maximum number of stacks of coal in the player inventory (defaults to 5 non-filtered stacks)
  * Maximum number of stacks of furnace product (iron plate, copper plate, steel, or brick) (defaults to 5 non-filtered stacks)
  * Whether refueling is active
