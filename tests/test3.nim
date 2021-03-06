import unittest
import pararules
import macros

# this module shows how you can use initSessionWithRules
# without having to define all your rules in one place.
# instead, you make functions that return your rules
# as quoted AST, and then create a "wrapper macro" that
# calls them at compile time and passes their results
# to initSessionWithRules. kinda hacky, but it works.

type
  Id = enum
    Global, Player,
  Attr = enum
    DeltaTime, TotalTime,
    X, Y,
    WindowWidth, WindowHeight,
    Width, Height,

schema Fact(Id, Attr):
  DeltaTime: float
  TotalTime: float
  X: float
  Y: float
  WindowWidth: int
  WindowHeight: int
  Width: float
  Height: float

# define functions that return your rules as quoted code

proc getterRules(): NimNode =
  quote:
    rule getPlayer(Fact):
      what:
        (Player, X, x)
        (Player, Y, y)
    rule getCharacter(Fact):
      what:
        (id, X, x)
        (id, Y, y)

proc moveRules(): NimNode =
  quote:
    rule movePlayer(Fact):
      what:
        (Global, DeltaTime, dt)
        (Player, X, x, then = false)
      then:
        session.insert(Player, X, x + dt)
    rule stopPlayer(Fact):
      what:
        (Global, WindowWidth, windowWidth)
        (Player, X, x)
      cond:
        x >= float(windowWidth)
        windowWidth > 0
      then:
        session.insert(Player, X, 0.0)

# define a wrapper macro that calls your functions

macro initSessionWithRules(): untyped =
  let
    getters = getterRules()
    movers = moveRules()
  quote:
    initSessionWithRules(Fact):
      `getters`
      `movers`

# call the wrapper macro

var (session, rules) = initSessionWithRules()

test "can use wrapper macro to break up rules":
  session.insert(Player, X, 0.0)
  session.insert(Player, Y, 1.0)
  session.insert(Global, WindowWidth, 100)
  session.insert(Global, DeltaTime, 100.0)
  check session.query(rules.getPlayer).x == 0.0

