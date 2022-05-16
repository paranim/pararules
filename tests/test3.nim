import unittest
import pararules
import macros

# this module shows how you can use staticRuleset
# without having to define all your rules in one place.
# instead, you make functions that return your rules
# as quoted AST, and then create a "wrapper macro" that
# calls them at compile time and passes their results
# to staticRuleset. kinda hacky, but it works.

from test1 import nil

type
  Id = enum
    Global, Player,
  Attr = enum
    DeltaTime, TotalTime,
    X, Y,
    WindowWidth, WindowHeight,
    Width, Height,
    AllPeople,

schema Fact(Id, Attr):
  DeltaTime: float
  TotalTime: float
  X: float
  Y: float
  WindowWidth: int
  WindowHeight: int
  Width: float
  Height: float
  AllPeople: test1.People

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
    rule getGlobals(Fact):
      what:
        (Global, WindowWidth, windowWidth)
        (Global, AllPeople, allPeople)

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

macro staticRuleset(): untyped =
  let
    getters = getterRules()
    movers = moveRules()
  quote:
    staticRuleset(Fact, FactMatch):
      `getters`
      `movers`

# call the wrapper macro

let (initSession, rules) = staticRuleset()

test "can use wrapper macro to break up rules":
  var session = initSession(autoFire = false)
  for r in rules.fields:
    session.add(r)
  session.insert(Player, X, 0.0)
  session.insert(Player, Y, 1.0)
  session.insert(Global, WindowWidth, 100)
  session.insert(Global, DeltaTime, 100.0)
  session.insert(Global, AllPeople, @[(id: 1, color: "blue", leftOf: 2, height: 72)])
  session.fireRules
  check session.query(rules.getPlayer).x == 0.0
  check session.query(rules.getGlobals).allPeople.len == 1

