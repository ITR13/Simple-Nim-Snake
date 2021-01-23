import glm

const
  gameTick*: float = 15/1000 # In seconds
  gameFieldWidth*: int32 = 16
  gameFieldHeight*: int32 = 16
  gameFieldSize*: Vec2i = vec2(gameFieldWidth, gameFieldHeight)
  totalFieldSize*: int32 = gameFieldWidth * gameFieldHeight

  pixelsPerUnit*: int32 = 64
  gameFieldInPixels*: Vec2i = gameFieldSize*pixelsPerUnit
  totalPixelCount*: int32 = gameFieldWidth*gameFieldHeight*pixelsPerUnit*pixelsPerUnit

type
  Direction* = enum
    NoDirection
    Up, Left, Down, Right