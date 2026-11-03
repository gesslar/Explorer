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
* `explore stop` - Stop exploring. This also ends a speedwalk that Explorer
  started, so your character stops where it is
* `explore set` - See your current preference settings
* `explore set <preference> <value>` - Set a preference to a value
* `explore ignore` - See the exit stubs being ignored
* `explore ignore <direction> [room]` - Ignore an exit stub. The room defaults to
  the one you are in
* `explore unignore <direction> [room]` - Stop ignoring an exit stub
* `explore debug` - Turn debug messages on or off

### Preferences

* `zoom` - Set the zoom level of the map during exploration (default: 10)
* `speed` - Set how many seconds to wait before each move (default: 0)
* `timeout` - Set how many seconds to wait for a move or door to respond before
  giving up on it (default: 5). During a speedwalk, this is added to
  generic_mapper's longest wait between steps. Carto's walks use its own
  `walk timeout` instead.
* `stats` - Show exploration statistics on the map during exploration
  (default: true)

### Ignoring exit stubs

If a move doesn't work, exploration stops and tells you the direction and room.
To carry on without that exit, ignore it and start again. Give the room if the
move left you somewhere else, such as through a one-way exit.

Ignored exit stubs are saved with your preferences and kept between runs. This
includes stubs Explorer ignores on its own because a door would not open.

## Events

### Listening

This package listens to the following events in order to function. You will
need to ensure that these events are passed along with the required arguments
(if any).

#### `onMoveMap`

Trigger this event when the player has moved to a new room. Explorer sets a
timer to check if the player has moved to a new room. When this event is
triggered, it confirms that the player has moved to a new room and will then
proceed to explore a new room. An update for the room the player is leaving
doesn't count as arriving, unless the exit's stub is gone because it led back to
the same room.

##### Arguments

* `current room id` - The id of the room the player has arrived in.

#### `sysSpeedwalkFinished`

Trigger this event when the speedwalk system has finished. The package listens
for this event to understand that speedwalking has completed and that it can
now schedule other activities. It can be raised when the last command is sent,
in which case Explorer waits for `onMoveMap` from the destination room. If no
room change arrives in time during the walk, exploration stops.

With Carto, this means the walk is over, so exploration stops if the player isn't
in the destination room.

##### Arguments

None

#### `sysSpeedwalkStarted`

Trigger this event when a speedwalk has started. Explorer prints a message about
the walk if it is exploring.

##### Arguments

None

#### `sysSpeedwalkPaused`

Trigger this event when a speedwalk has been paused. If Explorer started the
walk, it ends the walk and exploration stops, as the character is free to go
elsewhere while it is paused.

##### Arguments

None

#### `sysSpeedwalkStopped`

Trigger this event when a speedwalk has been stopped. If Explorer started the
walk, exploration stops.

##### Arguments

None

#### `onSpeedwalkReset`

Trigger this event when a speedwalk has been interrupted. Exploration stops if
`exception` is true.

##### Arguments

* `exception` - Boolean indicating if the walk failed.
* `reason` - The reason the walk ended.

#### `onSpeedwalkFailed`

Trigger this event when a speedwalk couldn't start, before `gotoRoom` returns.
Exploration stops if it is about the walk Explorer asked for. Otherwise, such as
somebody else trying to walk during Explorer's walk, it is ignored.

##### Arguments

* `reason` - The reason the walk couldn't start.

#### `onDoorChange`

Trigger this event when a door has changed. If Explorer is waiting on that door
and it is now open, it goes through right away. Without this event, Explorer
waits for the `timeout` preference at each closed door on an exit stub.

##### Arguments

* `room_id` - The id of the room the door is in.
* `command` - The door's direction, as used by `setDoor`.
* `status` - The door's new status.
* `old_status` - The door's previous status.

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

This event is raised when the next room to explore has been determined. It isn't
raised when the next exit has a door, as that has to be opened first.

##### Arguments

* `room_id` - The id of the next room to explore. This is the current room if it
  has an exit stub to explore.
* `area_id` - The id of the area that room is in.

#### `onExploreDirection`

This event is raised when the explorer is about to move through an exit stub in
the current room. If the exit has a door, it is raised once the door is open.

##### Arguments

* `room_id` - The id of the room the explorer is currently in.
* `direction` - The direction the explorer is about to explore.
* `stub` - The exit stub of the room the explorer is about to explore.

#### `onDirectionExplored`

This event is raised when the player has moved into a new room following a
direction exploration, once the move has been confirmed.

##### Arguments

* `room_id` - The id of the room the explorer has arrived in.
* `start_room_id` - The id of the room the explorer left.
* `direction` - The direction that was explored.

#### `onStubIgnored`

This event is raised when an exit stub is ignored.

##### Arguments

* `room_id` - The id of the room the stub is in.
* `stub` - The stub that was ignored.
* `direction` - The direction of the stub that was ignored.

## Dependencies

You need a mapper script enabled, one that sets `mudlet.mapper_script`, or
exploration won't start. If you use [Carto](https://github.com/gesslar/Carto), you
need version 1.5.0 or later, or a walk that fails can leave exploration waiting
until you use `explore stop`.

The following packages are required and will be automatically installed if they
are missing:

* [Helper](https://github.com/gesslar/Helper)

## Development

* `npm run build` - Build the package with
  [muddy](https://www.npmjs.com/package/@gesslar/muddy)
* `npm run watch` - Rebuild the package when files change
* `npm test` - Run the specs in `src/resources/test/` inside a headless Mudlet.
  This needs Docker, and uses the
  [mudlet-busted](https://hub.docker.com/r/gesslardev/mudlet-busted) image
* `npm run test:tree` - Run the specs with nested describe/it output
* `npm run docker:update` - Pull the latest mudlet-busted image
* `npm run update-glu` - Update the bundled copy of
  [Glu](https://github.com/gesslar/Glu)

Pull requests to `main` run the specs through the Quality workflow. Merging one
publishes a release once Quality has passed.

## Support

While there is no official support and this is a hobby project, you are welcome
to report issues on the [GitHub repo](https://github.com/gesslar/Explorer).

## License

`explorer` is released under the [0BSD](LICENSE.txt).

## Credits

[Compass icons created by Dimitry Miroliubov - Flaticon](https://www.flaticon.com/free-icons/compass)
