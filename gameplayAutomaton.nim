import c4/messages, c4/threads
import glm
import os
import random
import sequtils
import sets
import sugar
import synthesis
import times

import core
import drawMessages
import gameplayMessages

type
  GameplayState = enum
    Waiting
    ReadMessage
    Moving

  GameplayEvent = enum
    OnMessage
    Move
    EatPellet
    EatTail

declareAutomaton(gameplay, GameplayState, GameplayEvent)

setPrologue(gameplay):
  var snakeHeadPos: Vec2i
  var pelletPos: Vec2i
  var tailPos: seq[Vec2i] = @[vec2[int32](-1, -1), vec2[int32](-1, -1)]
  var pelletsEaten = 0
  var moveInterval: float
  var nextSnakeMove: float = cpuTime() + (if waitExtra: 5.0 else: 1.5)
  var time: float = 0
  var message: ref Message = nil
  var nextDirection, direction: Direction = Right
  var ignoreDirection: Direction = NoDirection

  proc randomEmptyLocation(): Vec2i =
    if len(tailPos) < totalFieldSize div 2:
      result = vec2(int32(rand(gameFieldWidth - 1)), int32(rand(gameFieldHeight - 1)))
      while result == snakeHeadPos or result in tailPos:
        result = vec2(int32(rand(gameFieldWidth - 1)), int32(rand(gameFieldHeight - 1)))
    else:
      var validPositions = toHashSet(
        toSeq(int32(0)..<gameFieldHeight).map(
          y => toSeq(int32(0)..<gameFieldWidth).map(x => [x, y])
        ).foldl(a & b)
      )
      validPositions.excl([snakeHeadPos.x, snakeHeadPos.y])
      for pos in tailPos:
        validPositions.excl([pos.x, pos.y])
      if len(validPositions)==0:
        result = vec2(int32(rand(gameFieldWidth - 1)), int32(rand(gameFieldHeight - 1)))
      else:
        let selected = sample(validPositions.toSeq())
        result = vec2(selected[0], selected[1])

  proc movePellet() =
    pelletPos = randomEmptyLocation()
    let pelletMessage = PelletMessage(pelletPosition: pelletPos)
    pelletMessage.send(mainThread)

  proc setMoveInterval() =
    let movesPerSecond = (3 - (1+2/3)/(1+pelletsEaten/16))
    moveInterval = 1/movesPerSecond

  block:
    setMoveInterval()
    snakeHeadPos = randomEmptyLocation()
    let snakeMessage = SnakeMessage(headPosition: snakeHeadPos)
    snakeMessage.send(mainThread)
    movePellet()


implEvent(gameplay, Move):
  time = cpuTime()
  time >= nextSnakeMove

implEvent(gameplay, OnMessage):
  message = tryRecv()
  message != nil

implEvent(gameplay, EatPellet):
  snakeHeadPos == pelletPos

implEvent(gameplay, EatTail):
  snakeHeadPos in tailPos

setInitialState(gameplay, Waiting)
setTerminalState(gameplay, Exit)

behavior(gameplay):
  ini: Waiting
  fin: Moving
  event: Move
  transition:
    nextSnakeMove += moveInterval
    var prevPos = snakeHeadPos
    var filteredPositions: seq[Vec2i]

    for i in tailPos.low..tailPos.high:
      var temp = tailPos[i]
      tailPos[i] = prevPos
      prevPos = temp

      if tailPos[i].x < 0 or tailPos[i].y < 0:
        continue
      filteredPositions.add(tailPos[i])

    case direction:
      of Up:
        ignoreDirection = Down
        snakeHeadPos = vec2[int32](snakeHeadPos.x, (snakeHeadPos.y + gameFieldHeight - 1) mod gameFieldHeight)
      of Left:
        ignoreDirection = Right
        snakeHeadPos = vec2[int32]((snakeHeadPos.x + gameFieldWidth - 1) mod gameFieldWidth, snakeHeadPos.y)
      of Down:
        ignoreDirection = Up
        snakeHeadPos = vec2[int32](snakeHeadPos.x, (snakeHeadPos.y + 1) mod gameFieldHeight)
      of Right, NoDirection:
        ignoreDirection = Left
        snakeHeadPos = vec2[int32]((snakeHeadPos.x + 1) mod gameFieldWidth, snakeHeadPos.y)

    if direction != nextDirection and nextDirection != ignoreDirection:
      direction = nextDirection
      let snakeDirectionMessage = SnakeDirectionMessage(direction: direction)
      snakeDirectionMessage.send(mainThread)

    let snakeMessage = SnakeMessage(headPosition: snakeHeadPos, bodyPositions: filteredPositions)
    snakeMessage.send(mainThread)


behavior(gameplay):
  ini: Moving
  fin: Waiting
  event: EatPellet
  transition:
    movePellet()
    tailPos.add(vec2[int32](-1, -1))
    pelletsEaten += 1
    setMoveInterval()

behavior(gameplay):
  ini: Moving
  fin: Exit
  event: EatTail
  transition:
    let waitUntil = 3 + cpuTime()
    while cpuTime() < waitUntil:
      sleep(0)


behavior(gameplay):
  ini: Waiting
  fin: ReadMessage
  event: OnMessage
  transition:
    let currentMessage = message
    message = nil
    if currentMessage of DirectionMessage:
      let directionMessage = DirectionMessage(currentMessage)
      nextDirection = directionMessage.direction
      if nextDirection != ignoreDirection:
        direction = directionMessage.direction
        let snakeDirectionMessage = SnakeDirectionMessage(direction: direction)
        snakeDirectionMessage.send(mainThread)

behavior(gameplay):
  ini: [ReadMessage, Moving]
  fin: Waiting
  transition:
    discard

behavior(gameplay):
  ini: Waiting
  fin: Waiting
  transition:
    sleep(0)

synthesize(gameplay):
  proc initSystem(waitExtra: bool)

when defined(export_graph):
  const dotRepr = toGraphviz(gameplay)
  writeFile("gameplay.dot", dotRepr)

proc initGameplaySystem*() =
  spawn("gameplay"):
    initSystem(true)
    while true:
      initSystem(false)