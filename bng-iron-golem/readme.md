# Golem Auto Helper

This helps with early-game tasks by doing the following actions as the player

  * Remove excess coal from Burner Mining Drills (allows a pair of drills to produce coal)
  * Adds coal to Burner Mining Drills
  * Adds coal to Stone and Steel Furnaces
  * Adds ores to Stone and Steel Furnaces
  * Removes full output stacks from Furnaces
  * Tops off (adds) coal to Boilers, vehicles, etc (anything that burns coal)
  * Adds missing inputs to assemblers
  * Basic logistics

The player (or golem) must be able to reach the entity for items to be exchanged.
The items are removed from and added to the inventory of a player of golem.

## Golem

A Golem is crafted from iron. It a humanoid figure that functions as a stand-in for the player.

Actions that would transfer items to/from a player will go to a golem if the player isn't nearby or
doesn't have the inventory space.

It has an iron-chest sized inventory.

It pulls jobs from the job queue and walks to the entity and services the entity.

It will push inventory to a player if the item count is below the player's configured level.


## Golem Provider Chest

This is a chest that transfers all inventory to a nearby player or golem.
Or rather, the player or golem will pull inventory from the chest, if possible.


## Golem Storage Chest

Excess inventory from the player or golem is dumped into Golem Storage Chests.
A player or golem will grab needed items from Golem Storage Chest.
Filters may be placed on slots to restrict what can go into the chest.

In sufficient Storage chests may cause a golem to cease functioning.


## Golem Request Chest

A Golem Request Chest uses a filter to indicate that a slot should be filled with an item.
A Golem will attempt to transfer items from inventory or storage to that container.


## Golem Poles

A Golem Pole is a non-colliding indicator of where golems should operate.
If there is a pole nearby, the golem will move towards the pole.
If there are multiple poles, it will navigate between them all.

If there are no poles, then the golem will not wander, but stand in place after completing a job.


## Entity Item Transfers

Each entity that can be services is tracked.
One entity per tick is examined for possible service needs.

If an entity needs to be serviced, then it is added to a "job" queue.
The job queue is consumed (and inventory moved) once per second by each actor (player or golem).

For furnaces, the status value is used to determine if the entity needs service.

  * working : the entity does not need service
  * no_fuel : coal is added (half-stack)
  * no_ingredients : ore is added matching entity.previous_recipe
  * full_output : output is moved to the player inventory, if the result won't exceed the stack limit

For the mining drill, the coal level is maintained as follows:

  * if less than 5, then a service is scheduled to add 10
  * if full, then a service is scheduled to remove all but 10

For the boiler and other fueled entities, the coal level is maintained as follows:

  * if a slot has less than 1/2 stack of fuel, then add more of the same fuel type
  * if a slot is empty then add 1 stack of coal

For the assembler, a service is scheduled if status==item_ingredient_shortage.
On service, inventory is added to the assembler to produce 2 recipes.


## Configuration

  * Maximum number of stacks of coal in the player inventory (defaults to 5)
  * Maximum number of stacks of furnace product (iron plate, copper plate, steel, or brick) (defaults to 5 each)
