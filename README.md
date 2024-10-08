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

This package listens to the following events in order to function. You will
need to ensure that these events are passed along with the required arguments
(if any).

### `onMoveMap`

Trigger this event when the player has moved to a new room. Explorer sets a
timer to check if the player has moved to a new room. When this event is
triggered, it confirms that the player has moved to a new room and will then
proceed to explore a new room.

#### Arguments

* `current room id` - The id of the room the player has arrived in.

### `sysSpeedwalkFinished`

Trigger this event when the speedwalk system has finished. The package listens
for this event to understand that speedwalking has completed and that it can
now schedule other activities.

#### Arguments

None

## Support

While there is no official support and this is a hobby project, you are welcome
to report issues on the [GitHub repo](https://github.com/gesslar/Explorer).

## Dependencies

The following packages are required and will be automatically installed if they
are missing:

* [Helper](https://github.com/gesslar/Helper)

## Credits

[Compass icons created by Dimitry Miroliubov - Flaticon](https://www.flaticon.com/free-icons/compass)
