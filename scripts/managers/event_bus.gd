extends Node
## Global signal hub (autoload "EventBus").
##
## Systems announce things here instead of holding references to each other.
## Gameplay code emits; UI and other systems listen. Keep this file signals-only.

## The game was paused or resumed.
@warning_ignore("unused_signal")
signal game_paused(is_paused: bool)

## The object the player would interact with changed. An empty prompt means nothing is in range.
@warning_ignore("unused_signal")
signal interaction_target_changed(prompt: String)

## Something was interacted with. Fired after the object has handled the interaction.
@warning_ignore("unused_signal")
signal interacted(target: Node, interactor: Node)

## Ask the HUD to show a short message to the player.
@warning_ignore("unused_signal")
signal notification_requested(title: String, message: String)

## The player crossed into another 125 m world chunk, for example "C6".
@warning_ignore("unused_signal")
signal player_chunk_changed(chunk: String)

## What the selected tool would hit changed, for example "Chop Oak tree". Empty = nothing.
@warning_ignore("unused_signal")
signal tool_target_changed(prompt: String)

## The player entered another region, for example "forest" / "Westwood Forest".
@warning_ignore("unused_signal")
signal region_changed(region_id: String, region_name: String)
