# Explorer

Developer's Automapping tool for Mudlet

## Description

This package is intended for use by developers who are looking to automatically
explore their game world. It is not intended for use by players, as it will
automatically move your character around the game world, and as well, it
may contravene the rules of your game.

## Configuration

In Mudlet, type `explore` to see the help information for this package.

* `explore start` - Start exploring
* `explore stop` - Stop exploring
* `explore set` - See your current preference settings
* `explore set <preference> <value>` - Set a preference to a value

  Available preferences:
  * `shuffle` - Set the maximum number of steps to take before selecting a
     random exit stub to explore (default: 0). If set to 0, Explorer will not
     shuffle.
  * `zoom` - Set the zoom level of the map during exploration (default:
    10)

## Events

### Listening

This package listens to the following events in order to function. You will
need to ensure that these events are passed along with the required arguments
(if any).

#### `onMoveMap`

Trigger this event when the player has moved to a new room. Explorer sets a
timer to check if the player has moved to a new room. When this event is
triggered, it confirms that the player has moved to a new room and will then
proceed to explore a new room.

##### Arguments

* `current room id` - The id of the room the player has arrived in.

#### `sysSpeedwalkFinished`

Trigger this event when the speedwalk system has finished. The package listens
for this event to understand that speedwalking has completed and that it can
now schedule other activities.

##### Arguments

None

### Raising

The following events are raised by this package:

#### `onExplorationStarted`

This event is raised when exploration has begun.

##### Arguments

None

#### `onExplorationStopped`

This event is raised when exploration has stopped.

##### Arguments

* `canceled` - Boolean indicating if the exploration was canceled.
* `silent` - Boolean indicating that no messages should be printed.

#### `onDetermineNextRoom`

This event is raised when the next room to explore is being determined.

##### Arguments

* `room_id` - The id of the room the player is currently in.
* `area_id` - The id of the area the player is currently in.

#### `onNextRoomDetermined`

This event is raised when the next room to explore has been determined.

##### Arguments

* `room_id` - The id of the next room to explore.
* `area_id` - The id of the area the next room to explore is in.

#### `onExploreDirection`

This event is raised when the explorer is about to explore a new direction. It
follows after `onNextRoomDetermined`, if the next room to explore is in the
same area and is adjacent to the current room.

##### Arguments

* `room_id` - The id of the room the explorer is currently in.
* `direction` - The direction the explorer is about to explore.
* `stub` - The exit stub of the room the explorer is about to explore.

#### `onDirectionExplored`

This event is raised when the player has moved into a new room following a
direction exploration.

##### Arguments

* `room_id` - The id of the room the explorer has arrived in.
* `direction` - The direction that was explored.

#### `onStubIgnored`

This event is raised when an exit stub is ignored.

##### Arguments

* `room_id` - The id of the room the stub is in.
* `stub` - The stub that was ignored.
* `direction` - The direction of the stub that was ignored.

## Dependencies

The following packages are required and will be automatically installed if they
are missing:

* [Helper](https://github.com/gesslar/Helper)

### Support

While there is no official support and this is a hobby project, you are welcome
to report issues on the [GitHub repo](https://github.com/gesslar/Explorer).

## Credits

[Compass icons created by Dimitry Miroliubov - Flaticon](https://www.flaticon.com/free-icons/compass)
