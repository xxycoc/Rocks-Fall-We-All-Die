extends Node
## STUB of P1's GameManager autoload, only so P2 code can run on its own.
## Replace with P1's real file when merging. Signal names follow CONTRACT.md.

signal hiker_died(id: int)
signal hiker_revived(id: int)
signal hiker_eliminated(id: int)
signal hiker_extracted(id: int)
signal game_over(winner: String)  # "hikers" or "mountain"
