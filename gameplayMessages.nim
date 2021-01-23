import c4/messages

import core

type DirectionMessage* = ref object of Message
  direction*: Direction