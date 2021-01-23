import c4/messages
import glm

import core

type SnakeDirectionMessage* = ref object of Message
  direction*: Direction

type SnakeMessage* = ref object of Message
  headPosition*: Vec2i
  bodyPositions*: seq[Vec2i]


type PelletMessage* = ref object of Message
  pelletPosition*: Vec2i