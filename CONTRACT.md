# P1 / P2 contract

What the Mountain (P2) code expects from the hiker and game code (P1). Agree on this before Saturday.

## Hikers
- Every hiker is a `CharacterBody3D` in the group `"hikers"`, named after its owner's peer ID (`hiker.name.to_int()`).
- Hikers sit on physics layer 2. Terrain sits on layer 1. The Mountain's click ray only hits layer 1.
- `@rpc("any_peer", "call_local") func take_damage(amount: int)`. The Mountain calls `hiker.take_damage.rpc(amount)` from the host only.
- `var friction_multiplier := 1.0`. Mud sets it to `0.05` on enter and `1.0` on exit.
  Movement runs on the hiker's owner, so mud changes it on the peer where `hiker.is_multiplayer_authority()` is true
  (obstacles are replicated to every peer, so each peer's copy of the mud handles its own hiker).
- P1 provides debug dummy hikers (F9 on the host) by Saturday night.

## GameManager (autoload, P1)
Signals: `hiker_died(id)`, `hiker_revived(id)`, `hiker_eliminated(id)`, `hiker_extracted(id)`, `game_over(winner)` with `winner` = `"hikers"` or `"mountain"`.

## Mountain (P2)
- `res://scenes/mountain.tscn` holds the camera, controller and HUD. `main.tscn` instances it on the host only (`multiplayer.is_server()`).
- Obstacles spawn under `main.tscn`'s `Obstacles` node (MultiplayerSpawner added Saturday). Only the host spawns them.

## Rules settled for open questions
- Revived hikers come back with 50 HP.
- The Mountain wins once the hikers can no longer get 2 out (covers 1 escaped + 3 eliminated).
- Round timer: 5 minutes. If it runs out, the Mountain wins.
