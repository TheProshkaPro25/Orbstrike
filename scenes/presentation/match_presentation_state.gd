extends RefCounted
## One presentation state per match. Input requests and mode persistence live elsewhere.
var definitions: Dictionary[int,CreatureDef] = {}
var owners: Dictionary[int,int] = {}
var active_ball: CreatureBall
var card_nodes: Dictionary[int,ArenaCardNode] = {}
var captures: Array[int] = [0, 0]
var pip_indices: Dictionary[int,int] = {}
var stats: Dictionary = {"wins": [0, 0], "abilities": [0, 0], "traps": 0, "battles": []}
var alive: Array[int] = [3, 3]
var turn := 0
var active_player := 0
var opponent_uid := -1
var opponent_power := -1
var own_uid := -1
var own_power := -1
var label_focus: Array = []
var battle_uids: Array[int] = []
