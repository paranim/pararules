import unittest
import pararules, pararules/engine
import tables

type
  Id = enum
    Alice, Bob, Charlie, David, George,
    Seth, Thomas, Xavier, Yair, Zach
  Attr = enum
    Color, LeftOf, RightOf, Height, On, Self

schema Data(Id, Attr, string, int)

test "number of conditions != number of facts":
  let prod =
    rule(Data):
      what:
        (b, Color, "blue")
        (y, LeftOf, z)
        (a, Color, "maize")
        (y, RightOf, b)
        (x, Height, h)
      then:
        check a == newData(Alice)
        check b == newData(Bob)
        check y == newData(Yair)
        check z == newData(Zach)

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((newData(Bob), newData(Color), newData("blue")))
  session.addFact((newData(Yair), newData(LeftOf), newData(Zach)))
  session.addFact((newData(Alice), newData(Color), newData("maize")))
  session.addFact((newData(Yair), newData(RightOf), newData(Bob)))

  session.addFact((newData(Xavier), newData(Height), newData(72)))
  session.addFact((newData(Thomas), newData(Height), newData(72)))
  session.addFact((newData(George), newData(Height), newData(72)))

  check prodNode.debugFacts.len == 3
  check prodNode.debugFacts[0].len == 5

test "adding facts out of order":
  let prod =
    rule(Data):
      what:
        (x, On, y)
        (y, LeftOf, z)
        (z, Color, "red")
        (a, Color, "maize")
        (b, Color, "blue")
        (c, Color, "green")
        (d, Color, "white")
        (s, On, "table")
        (y, RightOf, b)
        (a, LeftOf, d)
      then:
        check a == newData(Alice)
        check b == newData(Bob)
        check y == newData(Yair)
        check z == newData(Zach)

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((newData(Xavier), newData(On), newData(Yair)))
  session.addFact((newData(Yair), newData(LeftOf), newData(Zach)))
  session.addFact((newData(Zach), newData(Color), newData("red")))
  session.addFact((newData(Alice), newData(Color), newData("maize")))
  session.addFact((newData(Bob), newData(Color), newData("blue")))
  session.addFact((newData(Charlie), newData(Color), newData("green")))
 
  session.addFact((newData(Seth), newData(On), newData("table")))
  session.addFact((newData(Yair), newData(RightOf), newData(Bob)))
  session.addFact((newData(Alice), newData(LeftOf), newData(David)))

  session.addFact((newData(David), newData(Color), newData("white")))

  check prodNode.debugFacts.len == 1
  check prodNode.debugFacts[0].len == 10

test "duplicate facts":
  let prod =
    rule(Data):
      what:
        (x, Self, y)
        (x, Color, "red")
        (y, Color, "red")

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((newData(Bob), newData(Self), newData(Bob)))
  session.addFact((newData(Bob), newData(Color), newData("red")))

  check prodNode.debugFacts.len == 1
  check prodNode.debugFacts[0].len == 3

test "removing facts":
  let prod =
    rule(Data):
      what:
        (b, Color, "blue")
        (y, LeftOf, z)
        (a, Color, "maize")
        (y, RightOf, b)

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((newData(Bob), newData(Color), newData("blue")))
  session.addFact((newData(Yair), newData(LeftOf), newData(Zach)))
  session.addFact((newData(Alice), newData(Color), newData("maize")))
  session.addFact((newData(Yair), newData(RightOf), newData(Bob)))
  check prodNode.debugFacts.len == 1

  session.removeFact((newData(Yair), newData(RightOf), newData(Bob)))
  check prodNode.debugFacts.len == 0
  check prodNode.getParent.debugFacts.len == 1
  check prodNode.getParent.debugFacts[0].len == 3

  session.removeFact((newData(Bob), newData(Color), newData("blue")))
  check prodNode.debugFacts.len == 0
  check prodNode.getParent.debugFacts.len == 0

test "updating facts":
  var zVal: Data

  let prod =
    rule(Data):
      what:
        (b, Color, "blue")
        (y, LeftOf, z)
        (a, Color, "maize")
        (y, RightOf, b)
      then:
        zVal = z

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((newData(Bob), newData(Color), newData("blue")))
  session.addFact((newData(Yair), newData(LeftOf), newData(Zach)))
  session.addFact((newData(Alice), newData(Color), newData("maize")))
  session.addFact((newData(Yair), newData(RightOf), newData(Bob)))
  check prodNode.debugFacts.len == 1
  check zVal == newData(Zach)

  session.addFact((newData(Yair), newData(LeftOf), newData(Xavier)))
  check prodNode.debugFacts.len == 1
  check zVal == newData(Xavier)

test "updating facts in different alpha nodes":
  let prod =
    rule(Data):
      what:
        (b, Color, "blue")
        (y, LeftOf, Zach)
        (a, Color, "maize")
        (y, RightOf, b)

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((newData(Bob), newData(Color), newData("blue")))
  session.addFact((newData(Yair), newData(LeftOf), newData(Zach)))
  session.addFact((newData(Alice), newData(Color), newData("maize")))
  session.addFact((newData(Yair), newData(RightOf), newData(Bob)))
  check prodNode.debugFacts.len == 1

  session.addFact((newData(Yair), newData(LeftOf), newData(Xavier)))
  check prodNode.debugFacts.len == 0

test "complex conditions":
  let prod =
    rule(Data):
      what:
        (b, Color, "blue")
        (y, LeftOf, z)
        (a, Color, "maize")
        (y, RightOf, b)
      cond:
        z != newData(Zach)

  var session = newSession[Data]()
  let prodNode = session.addProduction(prod)
  session.addFact((newData(Bob), newData(Color), newData("blue")))
  session.addFact((newData(Yair), newData(LeftOf), newData(Zach)))
  session.addFact((newData(Alice), newData(Color), newData("maize")))
  session.addFact((newData(Yair), newData(RightOf), newData(Bob)))
  check prodNode.debugFacts.len == 0

  session.addFact((newData(Yair), newData(LeftOf), newData(Charlie)))
  check prodNode.debugFacts.len == 1

