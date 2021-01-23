import aglet, aglet/window/glfw
import c4/messages, c4/threads
import glm
from nimPNG import decodePng32
import sets
import synthesis

import core
import drawMessages
import gameplayMessages

# I literally just took these shaders from one of the test projects,
#  and I have no idea how they work
const
  VertexSource = glsl("""
    #version 330 core
    uniform vec2 offset;
    layout (location = 0) in vec2 position;
    layout (location = 1) in vec2 textureCoords;
    out vec2 fragTextureCoords;
    void main(void) {
      gl_Position = vec4(-1 + 2*(offset.x + position.x) / """ & $gameFieldWidth & """.0, -1 + 2*(offset.y + position.y) / """ & $gameFieldHeight & """.0, 0.0, 1.0);
      fragTextureCoords = textureCoords;
    }
  """)

  FragmentSource = glsl"""
    #version 330 core
    in vec2 fragTextureCoords;
    uniform sampler2D mainTexture;
    out vec4 color;
    void main(void) {
      vec2 uv = vec2(fragTextureCoords.x, 1.0 - fragTextureCoords.y);
      vec4 texColor = texture(mainTexture, fragTextureCoords);
      if(texColor.a < 0.1)
          discard;
      color = texColor;
    }
  """

let drawParams = defaultDrawParams()

type
  Vertex = object
    position: Vec2f
    textureCoords: Vec2f
  Vertex2D = object
    position: Vec2f
    textureCoords: Vec2f

type DrawState = enum
  Idle
  ProcessMessage
  RenderLayers
  CommitLayers

type DrawEvent = enum
  OnMessage
  OnUpdated
  OnRendered
  Quit

declareAutomaton(drawAutomaton, DrawState, DrawEvent)

setPrologue(drawAutomaton):
  var agl = initAglet()
  agl.initWindow()
  var win = agl.newWindowGlfw(
    800, 800, "Snake",
    winHints(resizable = true)
  )

  var prog = win.newProgram[:Vertex](VertexSource, FragmentSource)

  let fullScreen = win.newMesh(
    primitive = dpTriangles,
    vertices = [
      Vertex2D(position: vec2f(                  0.0,                    0.0), textureCoords: vec2f(0.0, 1.0)),
      Vertex2D(position: vec2f(float(gameFieldWidth),                    0.0), textureCoords: vec2f(1.0, 1.0)),
      Vertex2D(position: vec2f(                  0.0, float(gameFieldHeight)), textureCoords: vec2f(0.0, 0.0)),
      Vertex2D(position: vec2f(float(gameFieldWidth), float(gameFieldHeight)), textureCoords: vec2f(1.0, 0.0)),
    ],
    indices = [uint8 0, 1, 2, 1, 2, 3],
  )

  var fieldMeshes: array[4, Mesh[Vertex2D]]
  block:
    let vertexPositions = [vec2f(0, 0), vec2f(1, 0), vec2f(1, 1), vec2f(0, 1)]
    for i in 0..<4:
      fieldMeshes[i] = win.newMesh(
        primitive = dpTriangles,
        vertices = [
          Vertex2D(position: vertexPositions[(4 - i + 0) mod 4], textureCoords: vec2f(0.0, 0.0)),
          Vertex2D(position: vertexPositions[(4 - i + 1) mod 4], textureCoords: vec2f(1.0, 0.0)),
          Vertex2D(position: vertexPositions[(4 - i + 2) mod 4], textureCoords: vec2f(1.0, 1.0)),
          Vertex2D(position: vertexPositions[(4 - i + 3) mod 4], textureCoords: vec2f(0.0, 1.0)),
        ],
        indices = [uint8 0, 1, 2, 0, 3, 2],
      )

  const
    PngSnakeBody = slurp("textures/Body.png")
    PngSnakeHead = slurp("textures/Head.png")
    PngPellet = slurp("textures/Pellet.png")

  var decodedSnakeHead = decodePng32(PngSnakeHead)
  var decodedSnakeBody = decodePng32(PngSnakeBody)
  var decodedPellet = decodePng32(PngPellet)

  var textureBody = win.newTexture2D(Rgba8, decodedSnakeBody)
  var textureHead = win.newTexture2D(Rgba8, decodedSnakeHead)
  var texturePellet = win.newTexture2D(Rgba8, decodedPellet)

  var layerTextures = [
    win.newTexture2D[:Rgba8](gameFieldInPixels).toFramebuffer,
    win.newTexture2D[:Rgba8](gameFieldInPixels).toFramebuffer,
  ]
  var message: ref Message = nil
  var updated = toHashSet([0, 1])
  var lowestRenderedLayer = -1


  var positionPellet: Vec2i = vec2(int32(0), int32(0))
  var positionBodies: seq[Vec2i]
  var positionHead: Vec2i = vec2(int32(0), int32(0))
  var directionHead: Direction

implEvent(drawAutomaton, Quit):
  win.closeRequested()

implEvent(drawAutomaton, OnMessage):
  message = tryRecv()
  message != nil

implEvent(drawAutomaton, OnUpdated):
  len(updated) > 0

implEvent(drawAutomaton, OnRendered):
  lowestRenderedLayer >= 0

setInitialState(drawAutomaton, Idle)
setTerminalState(drawAutomaton, Exit)

behavior(drawAutomaton):
  ini: [Idle, ProcessMessage, RenderLayers, CommitLayers]
  fin: Exit
  interrupt: Quit
  transition:
    discard

behavior(drawAutomaton):
  ini: Idle
  fin: ProcessMessage
  event: OnMessage
  transition:
    let currentMessage = message
    message = nil
    if currentMessage of SnakeMessage:
      updated.incl(0)
      let snakeMessage = SnakeMessage(currentMessage)
      positionBodies = snakeMessage.bodyPositions
      positionHead = snakeMessage.headPosition
    elif currentMessage of PelletMessage:
      updated.incl(1)
      positionPellet = PelletMessage(currentMessage).pelletPosition
    elif currentMessage of SnakeDirectionMessage:
      updated.incl(0)
      directionHead = SnakeDirectionMessage(currentMessage).direction


behavior(drawAutomaton):
  ini: Idle
  fin: RenderLayers
  event: OnUpdated
  transition:
    var layerToUpdate = updated.pop()

    if lowestRenderedLayer < 0 or layerToUpdate < lowestRenderedLayer:
      lowestRenderedLayer = layerToUpdate

    var target = layerTextures[layerToUpdate].render()
    target.clearColor(rgba(1.0, 1.0, 1.0, 0.0))

    if layerToUpdate == 0:
      for position in positionBodies:
        target.draw(
          prog,
          fieldMeshes[0],
          uniforms {
            ?offset: vec2f(float(position.x), float(position.y)),
            ?mainTexture: textureBody.sampler(),
          },
          drawParams
        )
      target.draw(
        prog,
        fieldMeshes[ord(directionHead) mod 4],
        uniforms {
          ?offset: vec2f(float(positionHead.x), float(positionHead.y)),
          ?mainTexture: textureHead.sampler(),
        },
        drawParams
      )
    elif layerToUpdate == 1:
      target.draw(
        prog,
        fieldMeshes[0],
        uniforms {
          ?offset: vec2f(float(positionPellet.x), float(positionPellet.y)),
          ?mainTexture: texturePellet.sampler(),
        },
        drawParams
      )

behavior(drawAutomaton):
  ini: Idle
  fin: CommitLayers
  event: OnRendered
  transition:
    lowestRenderedLayer = -1
    var frame = win.render()
    frame.clearColor(rgba(0.0, 0.0, 1.0, 1.0))
    for layerTexture in layerTextures:
      frame.draw(
        prog,
        fullScreen,
        uniforms {
          ?offset: vec2f(0, 0),
          ?mainTexture: layerTexture.sampler(),
        },
        drawParams
      )

    frame.finish()

behavior(drawAutomaton):
  ini: [Idle, ProcessMessage, RenderLayers, CommitLayers]
  fin: Idle
  transition:
    win.pollEvents do (event: InputEvent):
      case event.kind:
      of iekWindowScale, iekWindowMaximize, iekWindowFrameResize:
        updated = toHashSet([0, 1])
      of iekKeyPress:
        var direction = case event.key:
          of keyW, keyUp:
            Up
          of keyA, keyLeft:
            Left
          of Key.keyS, keyDown:
            Down
          of keyD, keyRight:
            Right
          else:
            NoDirection
        if direction != NoDirection:
          let directionMessage = DirectionMessage(direction: direction)
          directionMessage.send("gameplay")

      else: discard

synthesize(drawAutomaton):
  proc initSystem()


when defined(export_graph):
  const dotRepr = toGraphviz(drawAutomaton)
  writeFile("drawAutomaton.dot", dotRepr)


proc initDrawSystem*() =
  initSystem()